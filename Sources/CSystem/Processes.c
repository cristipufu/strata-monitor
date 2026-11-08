#include "StrataSystem.h"
#include "StringCopy.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

enum { maximum_processes = 65536 };

static bool to_nanoseconds(uint64_t ticks, mach_timebase_info_data_t timebase, uint64_t *nanoseconds) {
    if (timebase.denom == 0) return false;
    __uint128_t value = (__uint128_t)ticks * timebase.numer / timebase.denom;
    if (value > UINT64_MAX) return false;
    *nanoseconds = (uint64_t)value;
    return true;
}

static bool kernel_record(int32_t pid, struct kinfo_proc *info) {
    int query[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t size = sizeof(*info);
    // A pid with no process answers success with an empty record.
    return sysctl(query, 4, info, &size, NULL, 0) == 0 && size == sizeof(*info);
}

static void read_identity(const struct kinfo_proc *info, SBProcess *result) {
    result->pid = info->kp_proc.p_pid;
    result->parent_pid = info->kp_eproc.e_ppid;
    result->uid = info->kp_eproc.e_ucred.cr_uid;
    result->start_seconds = (uint64_t)info->kp_proc.p_starttime.tv_sec;
    result->start_microseconds = (uint64_t)info->kp_proc.p_starttime.tv_usec;
    result->run_state = info->kp_proc.p_stat;
    result->translated = (info->kp_proc.p_flag & P_TRANSLATED) != 0;
    sb_copy_string(result->name, sizeof(result->name), info->kp_proc.p_comm, sizeof(info->kp_proc.p_comm));
}

static bool read_usage(SBProcess *result, mach_timebase_info_data_t timebase) {
    int32_t pid = result->pid;
    struct proc_taskinfo task = {0};
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
        result->usage_valid = to_nanoseconds(task.pti_total_user + task.pti_total_system, timebase, &result->cpu_ns);
        result->resident = task.pti_resident_size; result->threads = task.pti_threadnum;
    }
    struct rusage_info_v6 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&usage) == 0) {
        result->rusage_valid = to_nanoseconds(usage.ri_user_ptime + usage.ri_system_ptime, timebase,
                                              &result->performance_cpu_ns);
        result->footprint = usage.ri_phys_footprint; result->peak_footprint = usage.ri_lifetime_max_phys_footprint;
        result->disk_read = usage.ri_diskio_bytesread; result->disk_written = usage.ri_diskio_byteswritten;
        result->energy_nj = usage.ri_energy_nj; result->instructions = usage.ri_instructions;
        result->cycles = usage.ri_cycles; result->wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups;
    }
    return result->usage_valid || result->rusage_valid;
}

// Without root, usage calls on another user's process always fail; skipping them halves a scan.
static bool may_inspect(uint32_t uid) {
    uid_t self = geteuid();
    return self == 0 || uid == self;
}

typedef struct {
    char *bytes;
    size_t length, capacity;
} PathPool;

// A path that cannot be stored is left empty, which readers show as an unknown path.
static void store_path(PathPool *pool, const char *path, SBProcess *result) {
    size_t length = strnlen(path, PROC_PIDPATHINFO_MAXSIZE);
    if (length == 0 || pool->length > UINT32_MAX - length) return;
    if (pool->length + length > pool->capacity) {
        size_t capacity = pool->capacity * 2 > pool->length + length ? pool->capacity * 2 : pool->length + length;
        char *grown = realloc(pool->bytes, capacity);
        if (!grown) return;
        pool->bytes = grown;
        pool->capacity = capacity;
    }
    memcpy(pool->bytes + pool->length, path, length);
    result->path_offset = (uint32_t)pool->length;
    result->path_length = (uint32_t)length;
    pool->length += length;
}

static void read_process(const struct kinfo_proc *info, SBProcess *result, PathPool *paths,
                         mach_timebase_info_data_t timebase, SBScanStatus *status) {
    *result = (SBProcess){0};
    read_identity(info, result);
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (result->pid > 0 && proc_pidpath(result->pid, path, sizeof(path)) > 0) store_path(paths, path, result);
    errno = 0;
    bool measured = result->pid > 0 && may_inspect(result->uid) && read_usage(result, timebase);
    if (!measured) status->restricted = true;
}

static int compare_pid(const void *lhs, const void *rhs) {
    pid_t left = ((const struct kinfo_proc *)lhs)->kp_proc.p_pid;
    pid_t right = ((const struct kinfo_proc *)rhs)->kp_proc.p_pid;
    return (left > right) - (left < right);
}

static bool still_running(const SBProcess *process, const struct kinfo_proc *sorted, size_t count) {
    // The kernel never reuses pid 0.
    if (process->pid == 0) return true;
    struct kinfo_proc key = {0};
    key.kp_proc.p_pid = process->pid;
    const struct kinfo_proc *current = bsearch(&key, sorted, count, sizeof(key), compare_pid);
    return current && (uint64_t)current->kp_proc.p_starttime.tv_sec == process->start_seconds
        && (uint64_t)current->kp_proc.p_starttime.tv_usec == process->start_microseconds;
}

static struct kinfo_proc *process_table(size_t *count, SBScanStatus *status) {
    int query[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    const size_t limit = maximum_processes * sizeof(struct kinfo_proc);
    for (int attempt = 0; attempt < 4; attempt++) {
        size_t size = 0;
        if (sysctl(query, 3, NULL, &size, NULL, 0) != 0) { status->error = errno ? errno : EIO; return NULL; }
        // Processes started between the size query and the read need room too.
        size += size / 4 + 32 * sizeof(struct kinfo_proc);
        if (size > limit) { size = limit; status->truncated = true; }
        struct kinfo_proc *table = malloc(size);
        if (!table) { status->error = ENOMEM; return NULL; }
        if (sysctl(query, 3, table, &size, NULL, 0) == 0) {
            *count = size / sizeof(struct kinfo_proc);
            return table;
        }
        int error = errno;
        free(table);
        if (error != ENOMEM) { status->error = error ? error : EIO; return NULL; }
    }
    status->error = ENOMEM;
    return NULL;
}

SBProcess *sb_processes(size_t *count, char **paths, SBScanStatus *status) {
    *count = 0;
    *paths = NULL;
    *status = (SBScanStatus){0};
    mach_timebase_info_data_t timebase = {0};
    mach_timebase_info(&timebase);
    size_t listed = 0;
    struct kinfo_proc *table = process_table(&listed, status);
    if (!table) return NULL;
    SBProcess *results = calloc(listed > 0 ? listed : 1, sizeof(SBProcess));
    // Most executable paths are well under 128 bytes.
    PathPool pool = {.capacity = (listed > 0 ? listed : 1) * 128};
    pool.bytes = malloc(pool.capacity);
    if (!results || !pool.bytes) {
        free(results); free(pool.bytes); free(table);
        status->error = ENOMEM;
        return NULL;
    }
    for (size_t i = 0; i < listed; i++) read_process(&table[i], &results[i], &pool, timebase, status);
    free(table);
    // A row is kept only when its pid still names the process that was read, so a pid reused
    // during the scan cannot lend its path or usage to the exited process.
    size_t current_count = 0;
    SBScanStatus reread = {0};
    struct kinfo_proc *current = process_table(&current_count, &reread);
    if (!current) {
        free(results); free(pool.bytes);
        status->error = reread.error ? reread.error : EIO;
        return NULL;
    }
    qsort(current, current_count, sizeof(*current), compare_pid);
    for (size_t i = 0; i < listed; i++) {
        if (still_running(&results[i], current, current_count)) results[(*count)++] = results[i];
        else status->ended = true;
    }
    free(current);
    *paths = pool.bytes;
    return results;
}

bool sb_process_start_time(int32_t pid, uint64_t *seconds, uint64_t *microseconds) {
    if (!seconds || !microseconds) return false;
    *seconds = 0;
    *microseconds = 0;
    struct kinfo_proc info = {0};
    if (pid <= 0 || !kernel_record(pid, &info)) return false;
    *seconds = (uint64_t)info.kp_proc.p_starttime.tv_sec;
    *microseconds = (uint64_t)info.kp_proc.p_starttime.tv_usec;
    return true;
}

bool sb_process_identity(int32_t pid, uint64_t seconds, uint64_t microseconds) {
    uint64_t current_seconds, current_microseconds;
    return sb_process_start_time(pid, &current_seconds, &current_microseconds)
        && current_seconds == seconds && current_microseconds == microseconds;
}

bool sb_process_path_matches(int32_t pid, const char *path) {
    if (!path || !path[0]) return true;
    char current[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, current, sizeof(current)) <= 0) return false;
    return strncmp(current, path, sizeof(current)) == 0;
}
