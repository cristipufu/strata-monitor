#include "StrataSystem.h"
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <errno.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <string.h>
#include <stdlib.h>

static void read_cpu(SBSystemCounters *result) {
    natural_t cores = 0;
    processor_info_array_t ticks = NULL;
    mach_msg_type_number_t count = 0;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &ticks, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return;
    result->core_count = cores < SB_MAX_CORES ? cores : SB_MAX_CORES;
    for (size_t i = 0; i < result->core_count; i++) {
        size_t base = i * CPU_STATE_MAX;
        uint64_t busy = (uint32_t)ticks[base + CPU_STATE_USER] + (uint64_t)(uint32_t)ticks[base + CPU_STATE_SYSTEM] + (uint32_t)ticks[base + CPU_STATE_NICE];
        result->busy[i] = busy;
        result->total[i] = busy + (uint32_t)ticks[base + CPU_STATE_IDLE];
    }
    result->cpu_valid = result->core_count > 0;
    vm_deallocate(mach_task_self(), (vm_address_t)ticks, count * sizeof(integer_t));
}

static void read_memory(SBSystemCounters *result) {
    vm_statistics64_data_t stats = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stats, &count);
    vm_size_t page = 0;
    kern_return_t page_status = host_page_size(host, &page);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS || page_status != KERN_SUCCESS) return;
    size_t size = sizeof(result->memory_total);
    if (sysctlbyname("hw.memsize", &result->memory_total, &size, NULL, 0) != 0) return;
    result->active = (uint64_t)stats.active_count * page;
    result->wired = (uint64_t)stats.wire_count * page;
    result->compressed = (uint64_t)stats.compressor_page_count * page;
    result->cached = (uint64_t)stats.inactive_count * page;
    result->free_bytes = (uint64_t)stats.free_count * page;
    struct xsw_usage swap = {0}; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) {
        result->swap = swap.xsu_used;
        result->swap_valid = true;
    }
    size = sizeof(result->pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &result->pressure, &size, NULL, 0) != 0) result->pressure = 0;
    result->memory_valid = true;
}

void sb_add_link_traffic(SBSystemCounters *result, const char *name, uint32_t flags,
                         uint64_t received, uint64_t sent) {
    // Count physical Ethernet/Wi-Fi links only. Tunnel, bridge and peer-to-peer
    // counters repeat traffic their underlying interfaces already carried.
    if (strncmp(name, "en", 2) != 0 || !(flags & IFF_UP) || !(flags & IFF_RUNNING)) return;
    // Idle Thunderbolt bridge ports stay up and running without ever carrying bytes.
    if (received == 0 && sent == 0) return;
    result->received += received;
    result->sent += sent;
    if (result->interfaces[0]) strlcat(result->interfaces, ", ", sizeof(result->interfaces));
    strlcat(result->interfaces, name, sizeof(result->interfaces));
}

// The interface MIB reports 64-bit byte counters; the route interface list
// truncates them to 32 bits on current macOS, so they wrap every 4 GB.
static void read_network(SBSystemCounters *result) {
    int count_query[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT};
    int count = 0;
    size_t size = sizeof(count);
    if (sysctl(count_query, 5, &count, &size, NULL, 0) != 0 || count < 0 || count > 4096) return;
    for (int index = 1; index <= count; index++) {
        int query[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL};
        struct ifmibdata data;
        size = sizeof(data);
        if (sysctl(query, 6, &data, &size, NULL, 0) != 0) {
            if (errno == ENOENT) continue;
            return;
        }
        char name[IFNAMSIZ + 1] = {0};
        memcpy(name, data.ifmd_name, IFNAMSIZ);
        sb_add_link_traffic(result, name, data.ifmd_flags,
                            data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes);
    }
    result->network_valid = true;
}

SBSystemCounters sb_system_counters(void) {
    SBSystemCounters result = {0};
    read_cpu(&result); read_memory(&result); read_network(&result);
    return result;
}

void sb_free(void *buffer) { free(buffer); }
