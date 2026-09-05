/*
 * Opt-in CEF scale override for Steam's 64-bit steamwebhelper.
 *
 * Derived from steam-hidpi-shim commit f6651b1d6e85800885ea2b251ffc37c4e68df7e4:
 * https://github.com/katerinakosac51-creator/steam-hidpi-shim
 * SPDX-License-Identifier: MIT
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MINIMUM_SCALE 0.25
#define MAXIMUM_SCALE 8.0
#define EXECUTABLE_BUFFER_SIZE 4096

typedef int (*cef_initialize_fn)(const void *, const void *, void *, void *);
typedef void (*cef_set_scale_fn)(double);

__attribute__((visibility("default"))) int
cef_initialize(const void *args,
               const void *settings,
               void *application,
               void *windows_sandbox_info);

static bool debug_enabled(void)
{
    const char *value = getenv("STEAM_SCALE_DEBUG");

    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static void debug_log(const char *message)
{
    if (debug_enabled()) {
        (void)fprintf(stderr, "[steam-cef-scale-override] %s\n", message);
    }
}

static void warning_log(const char *message)
{
    (void)fprintf(stderr, "[steam-cef-scale-override] warning: %s\n", message);
}

static bool is_steam_webhelper(void)
{
    char executable[EXECUTABLE_BUFFER_SIZE];
    const ssize_t length = readlink(
        "/proc/self/exe",
        executable,
        sizeof(executable) - 1U
    );

    if (length < 0 || (size_t)length >= sizeof(executable)) {
        return false;
    }

    executable[(size_t)length] = '\0';
    const char *separator = strrchr(executable, '/');
    const char *basename = separator == NULL ? executable : separator + 1;

    return strcmp(basename, "steamwebhelper") == 0;
}

static bool read_scale(double *scale)
{
    const char *value = getenv("STEAM_SCALE_FACTOR");
    char *remainder = NULL;

    if (value == NULL || value[0] == '\0') {
        return false;
    }

    errno = 0;
    const double parsed = strtod(value, &remainder);
    if (errno == ERANGE || remainder == value || remainder == NULL
        || remainder[0] != '\0' || !isfinite(parsed)
        || parsed < MINIMUM_SCALE || parsed > MAXIMUM_SCALE) {
        warning_log("ignoring invalid STEAM_SCALE_FACTOR");
        return false;
    }

    *scale = parsed;
    return true;
}

static cef_initialize_fn find_real_initialize(void)
{
    cef_initialize_fn function = NULL;
    void *symbol = dlsym(RTLD_NEXT, "cef_initialize");

    _Static_assert(
        sizeof(function) == sizeof(symbol),
        "dlsym pointer size differs from a CEF function pointer"
    );
    (void)memcpy(&function, &symbol, sizeof(function));
    return function;
}

static cef_set_scale_fn find_set_scale(void)
{
    cef_set_scale_fn function = NULL;
    void *symbol = dlsym(RTLD_NEXT, "cef_set_force_device_scale_factor");

    _Static_assert(
        sizeof(function) == sizeof(symbol),
        "dlsym pointer size differs from a CEF function pointer"
    );
    (void)memcpy(&function, &symbol, sizeof(function));
    return function;
}

int cef_initialize(const void *args,
                   const void *settings,
                   void *application,
                   void *windows_sandbox_info)
{
    const cef_initialize_fn real_initialize = find_real_initialize();
    if (real_initialize == NULL) {
        warning_log("the real cef_initialize symbol is unavailable");
        return 0;
    }

    const int result = real_initialize(
        args,
        settings,
        application,
        windows_sandbox_info
    );

    if (result == 0 || !is_steam_webhelper()) {
        return result;
    }

    double scale = 0.0;
    if (!read_scale(&scale)) {
        return result;
    }

    const cef_set_scale_fn set_scale = find_set_scale();
    if (set_scale == NULL) {
        warning_log("CEF's device-scale function is unavailable; continuing unscaled");
        return result;
    }

    set_scale(scale);
    debug_log("applied the requested device scale to steamwebhelper");
    return result;
}
