#include "StrataSystem.h"
#include <errno.h>
#include <grp.h>
#include <membership.h>
#include <stdlib.h>

// A large admin group needs a larger buffer; failing would wrongly treat an admin as a standard user.
static bool admin_group(gid_t *gid) {
    for (size_t size = 4096; size <= 1024 * 1024; size *= 4) {
        char *buffer = malloc(size);
        if (!buffer) return false;
        struct group entry, *found = NULL;
        int error = getgrnam_r("admin", &entry, buffer, size, &found);
        if (error == 0 && found) *gid = found->gr_gid;
        free(buffer);
        if (error != ERANGE) return error == 0 && found;
    }
    return false;
}

bool sb_user_is_administrator(uint32_t uid) {
    gid_t gid = 0;
    if (!admin_group(&gid)) return false;
    uuid_t user, group;
    int member = 0;
    if (mbr_uid_to_uuid(uid, user) != 0 || mbr_gid_to_uuid(gid, group) != 0) return false;
    return mbr_check_membership(user, group, &member) == 0 && member == 1;
}
