#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void append_event(const char *event)
{
    const char *path = getenv("STEAM_SCALE_TEST_LOG");
    if (path == NULL) {
        abort();
    }

    FILE *stream = fopen(path, "a");
    if (stream == NULL) {
        abort();
    }

    (void)fprintf(stream, "%s\n", event);
    if (fclose(stream) != 0) {
        abort();
    }
}

__attribute__((visibility("default"))) int
cef_initialize(const void *args,
               const void *settings,
               void *application,
               void *windows_sandbox_info)
{
    (void)args;
    (void)settings;
    (void)application;
    (void)windows_sandbox_info;
    append_event("initialize");

    const char *fail = getenv("STEAM_SCALE_TEST_INIT_FAIL");
    return fail == NULL || strcmp(fail, "1") != 0;
}

__attribute__((visibility("default"))) void
cef_set_force_device_scale_factor(double scale)
{
    char event[64];
    (void)snprintf(event, sizeof(event), "scale=%.2f", scale);
    append_event(event);
}
