#ifndef STRATA_PROCESS_WORKING_DIRECTORY_H
#define STRATA_PROCESS_WORKING_DIRECTORY_H
#include <stdint.h>
#include <stddef.h>

/* Returns 0 or an errno value. The buffer always holds a terminated string, empty on failure. */
int sb_process_cwd(int32_t pid, char *buffer, size_t size);
#endif
