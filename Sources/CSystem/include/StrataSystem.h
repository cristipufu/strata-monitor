#ifndef STRATA_SYSTEM_H
#define STRATA_SYSTEM_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define SB_MAX_CORES 256
typedef struct {
    bool cpu_valid, memory_valid, network_valid, swap_valid;
    uint64_t busy[SB_MAX_CORES], total[SB_MAX_CORES];
    size_t core_count;
    uint64_t memory_total, active, wired, compressed, cached, free_bytes, swap;
    int pressure;
    uint64_t received, sent;
    char interfaces[1024];
} SBSystemCounters;

// Identity, parent, owner and run state come from the kernel's process table for every
// process. Usage fields are valid only where the caller may inspect the process. Paths live in
// one shared buffer, since a fixed path field would make every record 4 KB.
typedef struct {
    int32_t pid, parent_pid;
    uint32_t uid;
    uint64_t start_seconds, start_microseconds, cpu_ns, resident, footprint, disk_read, disk_written;
    uint64_t energy_nj, wakeups, instructions, cycles, peak_footprint, performance_cpu_ns;
    int threads, run_state;
    bool usage_valid, rusage_valid, translated;
    uint32_t path_offset, path_length;
    char name[32];
} SBProcess;

typedef struct {
    int32_t descriptor, kind;
    uint16_t local_port, remote_port;
    int tcp_state;
    bool file_system_valid;
    int32_t file_system_id[2];
    char path[4096], local_address[128], remote_address[128];
} SBResource;

typedef struct {
    int error;
    size_t unreadable_descriptors;
    bool restricted, ended, truncated;
} SBScanStatus;

typedef struct SBCancellation SBCancellation;
SBCancellation *sb_cancellation_create(void);
void sb_cancellation_cancel(SBCancellation *cancellation);
bool sb_cancellation_is_cancelled(const SBCancellation *cancellation);
void sb_cancellation_destroy(SBCancellation *cancellation);

typedef struct { uint32_t values[8]; } SBActionToken;
int sb_prepare_signal(int32_t pid, uint64_t seconds, uint64_t microseconds, SBActionToken *target);
int sb_send_signal(const SBActionToken *target, int signal);

SBSystemCounters sb_system_counters(void);
void sb_add_link_traffic(SBSystemCounters *result, const char *name, uint32_t flags,
                         uint64_t received, uint64_t sent);
// On success the caller frees both the records and `paths` with sb_free.
SBProcess *sb_processes(size_t *count, char **paths, SBScanStatus *status);
bool sb_process_start_time(int32_t pid, uint64_t *seconds, uint64_t *microseconds);
bool sb_process_identity(int32_t pid, uint64_t seconds, uint64_t microseconds);
bool sb_process_path_matches(int32_t pid, const char *path);
typedef struct { char path[4096]; } SBExecutableMapping;
SBExecutableMapping *sb_executable_mappings(int32_t pid, size_t *count, SBScanStatus *status,
                                          const SBCancellation *cancellation);
void *sb_process_arguments(int32_t pid, size_t *length, int *error);
void sb_sensitive_free(void *buffer, size_t length);
SBResource *sb_resources(int32_t pid, size_t *count, bool sockets_only,
                        SBScanStatus *status, const SBCancellation *cancellation);
void sb_free(void *buffer);
bool sb_user_is_administrator(uint32_t uid);

#include "DeviceNotifications.h"
#endif
