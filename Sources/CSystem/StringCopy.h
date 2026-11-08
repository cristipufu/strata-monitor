#ifndef SB_STRING_COPY_H
#define SB_STRING_COPY_H
#include <string.h>

// Kernel fixed-width fields need not contain a terminator.
static inline void sb_copy_string(char *destination, size_t capacity, const char *source, size_t source_capacity) {
    if (capacity == 0) return;
    size_t length = strnlen(source, source_capacity);
    if (length >= capacity) length = capacity - 1;
    memcpy(destination, source, length);
    destination[length] = '\0';
}
#endif
