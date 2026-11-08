#include "DeviceNotifications.h"
#include <dispatch/dispatch.h>
#include <notify.h>

uint32_t sb_observe_dispatch_notification(const char *name, void (^changed)(void), int32_t *token) {
    if (token) *token = -1;
    if (!name || !changed || !token) return NOTIFY_STATUS_INVALID_REQUEST;
    if (name[0] == '\0') return NOTIFY_STATUS_INVALID_NAME;
    return notify_register_dispatch(name, token,
                                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                                   ^(int notification_token) {
        (void)notification_token;
        changed();
    });
}

uint32_t sb_cancel_dispatch_notification(int32_t token) {
    return notify_cancel(token);
}
