#ifndef STRATA_DEVICE_NOTIFICATIONS_H
#define STRATA_DEVICE_NOTIFICATIONS_H
#include <stdint.h>

/* The notification service copies the callback and releases it on cancellation. */
#ifdef __BLOCKS__
uint32_t sb_observe_dispatch_notification(const char *_Nullable name, void (^_Nullable changed)(void), int32_t *_Nullable token);
#endif
uint32_t sb_cancel_dispatch_notification(int32_t token);
#endif
