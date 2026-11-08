#include "StrataSystem.h"
#include <stdatomic.h>
#include <stdlib.h>

struct SBCancellation { atomic_bool cancelled; };

SBCancellation *sb_cancellation_create(void) {
    SBCancellation *cancellation = malloc(sizeof(*cancellation));
    if (cancellation) atomic_init(&cancellation->cancelled, false);
    return cancellation;
}

void sb_cancellation_cancel(SBCancellation *cancellation) {
    if (cancellation) atomic_store_explicit(&cancellation->cancelled, true, memory_order_relaxed);
}

bool sb_cancellation_is_cancelled(const SBCancellation *cancellation) {
    return cancellation && atomic_load_explicit(&cancellation->cancelled, memory_order_relaxed);
}

void sb_cancellation_destroy(SBCancellation *cancellation) { free(cancellation); }
