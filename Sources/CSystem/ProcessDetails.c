#include "StrataSystem.h"
#include "StringCopy.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <mach/vm_prot.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

enum { maximum_mapping_results = 4096, maximum_regions = 65536, maximum_argument_bytes = 1024 * 1024 };

SBExecutableMapping *sb_executable_mappings(int32_t pid, size_t *count, SBScanStatus *status,
                                          const SBCancellation *cancellation) {
    *count = 0; *status = (SBScanStatus){0};
    if (pid <= 0) { status->error = EINVAL; return NULL; }
    size_t capacity = 32;
    SBExecutableMapping *results = calloc(capacity, sizeof(*results));
    if (!results) { status->error = ENOMEM; return NULL; }
    uint64_t address = 0;
    size_t iteration = 0;
    for (; iteration < maximum_regions; iteration++) {
        if (sb_cancellation_is_cancelled(cancellation)) { status->error = ECANCELED; break; }
        struct proc_regionwithpathinfo region = {0};
        errno = 0;
        int size = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, sizeof(region));
        if (size != sizeof(region)) {
            if (errno == EPERM || errno == EACCES) status->restricted = true;
            else if (errno == ESRCH) status->ended = true;
            else if (errno != EINVAL && errno != ENOENT && errno != 0) status->error = errno;
            break;
        }
        uint64_t start = region.prp_prinfo.pri_address, length = region.prp_prinfo.pri_size;
        if (length == 0 || start > UINT64_MAX - length || start + length <= address) break;
        address = start + length;
        if (!(region.prp_prinfo.pri_protection & VM_PROT_EXECUTE) || !region.prp_vip.vip_path[0]) continue;
        if (*count >= maximum_mapping_results) { status->truncated = true; break; }
        if (*count == capacity) {
            capacity *= 2;
            SBExecutableMapping *grown = realloc(results, capacity * sizeof(*results));
            if (!grown) { status->error = ENOMEM; break; }
            results = grown;
        }
        sb_copy_string(results[*count].path, sizeof(results[*count].path), region.prp_vip.vip_path, sizeof(region.prp_vip.vip_path));
        (*count)++;
    }
    if (iteration == maximum_regions) status->truncated = true;
    return results;
}

void *sb_process_arguments(int32_t pid, size_t *length, int *error) {
    *length = 0; *error = 0;
    if (pid <= 0) { *error = EINVAL; return NULL; }
    int capacity = 0; size_t size = sizeof(capacity);
    if (sysctlbyname("kern.argmax", &capacity, &size, NULL, 0) != 0) { *error = errno; return NULL; }
    if (capacity <= 0 || capacity > maximum_argument_bytes) { *error = EOVERFLOW; return NULL; }
    void *buffer = malloc((size_t)capacity);
    if (!buffer) { *error = ENOMEM; return NULL; }
    int query[] = {CTL_KERN, KERN_PROCARGS2, pid};
    size = (size_t)capacity;
    if (sysctl(query, 3, buffer, &size, NULL, 0) != 0) {
        *error = errno; sb_sensitive_free(buffer, (size_t)capacity); return NULL;
    }
    *length = size;
    return buffer;
}

void sb_sensitive_free(void *buffer, size_t length) {
    if (buffer) { memset_s(buffer, length, 0, length); free(buffer); }
}
