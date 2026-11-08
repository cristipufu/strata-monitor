#include "StrataSystem.h"
#include "StringCopy.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

enum { maximum_descriptors = 16384 };

static void record_query_failure(SBScanStatus *status) {
    if (errno == EPERM || errno == EACCES) status->restricted = true;
    if (errno != EBADF && errno != ESRCH) status->unreadable_descriptors++;
}

static void read_socket(int32_t pid, int fd, SBResource *result, SBScanStatus *status) {
    struct socket_fdinfo socket = {0};
    errno = 0;
    if (proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &socket, sizeof(socket)) != sizeof(socket)) {
        record_query_failure(status); return;
    }
    if (socket.psi.soi_kind == SOCKINFO_UN) {
        result->kind = 5;
        const struct sockaddr_un *address = &socket.psi.soi_proto.pri_un.unsi_addr.ua_sun;
        sb_copy_string(result->path, sizeof(result->path), address->sun_path, sizeof(address->sun_path));
        return;
    }
    bool tcp = socket.psi.soi_kind == SOCKINFO_TCP;
    if (!tcp && socket.psi.soi_kind != SOCKINFO_IN) return;
    if (!tcp && socket.psi.soi_protocol != IPPROTO_UDP) return;
    const struct in_sockinfo *address = tcp ? &socket.psi.soi_proto.pri_tcp.tcpsi_ini : &socket.psi.soi_proto.pri_in;
    result->kind = tcp ? 6 : 7;
    result->tcp_state = tcp ? socket.psi.soi_proto.pri_tcp.tcpsi_state : 0;
    result->local_port = ntohs((uint16_t)address->insi_lport);
    result->remote_port = ntohs((uint16_t)address->insi_fport);
    bool ipv6 = socket.psi.soi_family == AF_INET6;
    inet_ntop(ipv6 ? AF_INET6 : AF_INET,
              ipv6 ? (const void *)&address->insi_laddr.ina_6 : (const void *)&address->insi_laddr.ina_46.i46a_addr4,
              result->local_address, sizeof(result->local_address));
    inet_ntop(ipv6 ? AF_INET6 : AF_INET,
              ipv6 ? (const void *)&address->insi_faddr.ina_6 : (const void *)&address->insi_faddr.ina_46.i46a_addr4,
              result->remote_address, sizeof(result->remote_address));
}

static void read_descriptor(int32_t pid, struct proc_fdinfo descriptor, SBResource *result, SBScanStatus *status) {
    result->descriptor = descriptor.proc_fd;
    if (descriptor.proc_fdtype == PROX_FDTYPE_SOCKET) { read_socket(pid, descriptor.proc_fd, result, status); return; }
    if (descriptor.proc_fdtype == PROX_FDTYPE_PIPE) { result->kind = 4; strlcpy(result->path, "Pipe", sizeof(result->path)); return; }
    if (descriptor.proc_fdtype != PROX_FDTYPE_VNODE) return;
    struct vnode_fdinfowithpath file = {0};
    errno = 0;
    if (proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &file, sizeof(file)) != sizeof(file)) {
        record_query_failure(status); return;
    }
    sb_copy_string(result->path, sizeof(result->path), file.pvip.vip_path, sizeof(file.pvip.vip_path));
    result->file_system_valid = true;
    result->file_system_id[0] = file.pvip.vip_vi.vi_fsid.val[0];
    result->file_system_id[1] = file.pvip.vip_vi.vi_fsid.val[1];
    mode_t mode = file.pvip.vip_vi.vi_stat.vst_mode;
    result->kind = S_ISDIR(mode) ? 2 : (S_ISCHR(mode) || S_ISBLK(mode)) ? 3 : 1;
}

static void record_scan_failure(SBScanStatus *status) {
    if (errno == EPERM || errno == EACCES) status->restricted = true;
    else if (errno == ESRCH) status->ended = true;
    else status->error = errno ? errno : EIO;
}

SBResource *sb_resources(int32_t pid, size_t *count, bool sockets_only,
                        SBScanStatus *status, const SBCancellation *cancellation) {
    *count = 0; *status = (SBScanStatus){0};
    if (pid <= 0) { status->error = EINVAL; return NULL; }
    if (sb_cancellation_is_cancelled(cancellation)) { status->error = ECANCELED; return NULL; }
    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (bytes <= 0) { if (errno != 0 || bytes < 0) record_scan_failure(status); return NULL; }
    size_t capacity = (size_t)bytes / sizeof(struct proc_fdinfo) + 32;
    if (capacity > maximum_descriptors) { capacity = maximum_descriptors; status->truncated = true; }
    struct proc_fdinfo *descriptors = calloc(capacity, sizeof(struct proc_fdinfo));
    SBResource *results = calloc(capacity, sizeof(SBResource));
    if (!descriptors || !results) { free(descriptors); free(results); status->error = ENOMEM; return NULL; }
    errno = 0;
    int actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, descriptors, (int)(capacity * sizeof(struct proc_fdinfo)));
    if (actual <= 0) {
        if (errno != 0 || actual < 0) record_scan_failure(status);
        free(descriptors); free(results); return NULL;
    }
    if ((size_t)actual >= capacity * sizeof(struct proc_fdinfo)) status->truncated = true;
    size_t available = (size_t)actual / sizeof(struct proc_fdinfo);
    if (available > capacity) available = capacity;
    for (size_t i = 0; i < available; i++) {
        if (sb_cancellation_is_cancelled(cancellation)) { status->error = ECANCELED; break; }
        if (sockets_only && descriptors[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
        SBResource item = {0};
        read_descriptor(pid, descriptors[i], &item, status);
        if (item.kind != 0) results[(*count)++] = item;
    }
    free(descriptors);
    return results;
}
