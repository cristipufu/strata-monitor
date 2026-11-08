#include "ProcessWorkingDirectory.h"
#include "StringCopy.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <errno.h>

int sb_process_cwd(int32_t pid, char *buffer, size_t size) {
    if (!buffer || size == 0) return EINVAL;
    buffer[0] = '\0';
    if (pid <= 0) return EINVAL;
    struct proc_vnodepathinfo info = {0};
    errno = 0;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) != sizeof(info)) {
        return errno ? errno : ESRCH;
    }
    const char *path = info.pvi_cdir.vip_path;
    size_t length = strnlen(path, sizeof(info.pvi_cdir.vip_path));
    if (length == 0) return ENOENT;
    if (length >= size) return ERANGE;
    sb_copy_string(buffer, size, path, sizeof(info.pvi_cdir.vip_path));
    return 0;
}
