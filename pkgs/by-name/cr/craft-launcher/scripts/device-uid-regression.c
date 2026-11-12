#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct gomp_device_descr {
  char *uid;
  char *(*get_uid_func)(int);
  int target_id;
};

static void *gomp_malloc(size_t size) {
  void *result = malloc(size);
  assert(result != NULL);
  return result;
}

#include "upstream-device-uid.h"

static char *provider_uid(int device) {
  static char uid[] = "PROVIDER_UID";
  assert(device == 7);
  return uid;
}

int main(void) {
  /* Negative values test the downstream buffer's defensive full-int bound.
     Public callers exclude them; this is not a reachable API truncation test.  */
  const int values[] = {INT_MIN, -1, 0, 1, INT_MAX};
  for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); ++index) {
    char expected[128];
    int length = snprintf(expected, sizeof(expected), "OMP_DEV_%d", values[index]);
    assert(length > 0 && (size_t)length < sizeof(expected));
    struct gomp_device_descr device = {0};
    const char *actual = gomp_get_uid_for_device(&device, values[index]);
    if (strcmp(actual, expected) != 0) {
      fprintf(
          stderr, "UID mismatch for %d: expected %s, got %s\n", values[index], expected, actual);
      free(device.uid);
      return 1;
    }
    assert(gomp_get_uid_for_device(&device, 0) == actual);
    free(device.uid);
  }
  char cached[] = "CACHED_UID";
  struct gomp_device_descr existing = {.uid = cached};
  assert(gomp_get_uid_for_device(&existing, 0) == cached);
  struct gomp_device_descr provider = {.get_uid_func = provider_uid, .target_id = 7};
  assert(strcmp(gomp_get_uid_for_device(&provider, 0), "PROVIDER_UID") == 0);
  return 0;
}
