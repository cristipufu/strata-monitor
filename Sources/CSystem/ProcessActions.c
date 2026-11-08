#include "StrataSystem.h"
#include <mach/mach.h>
#include <bsm/libbsm.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static bool eligible_identity(int32_t pid, uint64_t seconds, uint64_t microseconds) {
    if (pid <= 1 || pid == getpid() || geteuid() == 0) return false;
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return false;
    return info.pbi_start_tvsec == seconds && info.pbi_start_tvusec == microseconds &&
        info.pbi_uid == geteuid() && info.pbi_ruid == getuid() && !(info.pbi_flags & PROC_FLAG_SYSTEM);
}

int sb_prepare_signal(int32_t pid, uint64_t seconds, uint64_t microseconds, SBActionToken *target) {
    if (!target) return EINVAL;
    memset(target, 0, sizeof(*target));
    if (!eligible_identity(pid, seconds, microseconds)) return EPERM;
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t status = task_name_for_pid(mach_task_self(), pid, &task);
    if (status != KERN_SUCCESS) return EACCES;
    audit_token_t token = {{0}};
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    status = task_info(task, TASK_AUDIT_TOKEN, (task_info_t)&token, &count);
    mach_port_deallocate(mach_task_self(), task);
    if (status != KERN_SUCCESS || count != TASK_AUDIT_TOKEN_COUNT) return EACCES;
    if (audit_token_to_pid(token) != pid || !eligible_identity(pid, seconds, microseconds)) return ESRCH;
    _Static_assert(sizeof(*target) == sizeof(token), "Audit token layout changed");
    memcpy(target->values, token.val, sizeof(*target));
    return 0;
}

int sb_send_signal(const SBActionToken *target, int signal) {
    if (!target || (signal != SIGTERM && signal != SIGKILL && signal != SIGSTOP && signal != SIGCONT))
        return EINVAL;
    audit_token_t token;
    memcpy(token.val, target->values, sizeof(token));
    pid_t pid = audit_token_to_pid(token);
    if (pid <= 1 || pid == getpid() || geteuid() == 0 ||
        audit_token_to_euid(token) != geteuid() || audit_token_to_ruid(token) != getuid()) return EPERM;
    // The kernel checks the audit token's process generation as well as caller
    // permissions. There is deliberately no PID-only fallback.
    return proc_signal_with_audittoken(&token, signal);
}
