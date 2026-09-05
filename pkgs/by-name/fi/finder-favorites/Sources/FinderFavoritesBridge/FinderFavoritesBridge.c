#include "FinderFavoritesBridge.h"

#include <CoreServices/CoreServices.h>
#include <crt_externs.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

struct FFBridgeSnapshot {
  CFArrayRef items;
  uint32_t seed;
  size_t count;
  char **display_names;
  char **paths;
  bool *resolved;
};

int ff_bridge_argument_count(void) { return *_NSGetArgc(); }

const char *ff_bridge_argument_at(int index) {
  int count = ff_bridge_argument_count();
  if (index < 0 || index >= count) {
    return NULL;
  }
  return (*_NSGetArgv())[index];
}

static void ff_set_error(char **error_message, const char *operation, int status) {
  if (error_message == NULL) {
    return;
  }

  char buffer[256];
  if (status == 0) {
    (void)snprintf(buffer, sizeof(buffer), "%s failed", operation);
  } else {
    (void)snprintf(buffer, sizeof(buffer), "%s failed with status %d", operation, status);
  }
  *error_message = strdup(buffer);
}

static char *ff_copy_cf_string(CFStringRef value) {
  if (value == NULL) {
    return strdup("");
  }

  CFIndex length = CFStringGetLength(value);
  CFIndex capacity = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
  char *buffer = calloc((size_t)capacity, sizeof(char));
  if (buffer == NULL) {
    return NULL;
  }
  if (!CFStringGetCString(value, buffer, capacity, kCFStringEncodingUTF8)) {
    free(buffer);
    return NULL;
  }
  return buffer;
}

static LSSharedFileListRef ff_create_list(char **error_message) {
  LSSharedFileListRef list =
      LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListFavoriteItems, NULL);
  if (list == NULL) {
    ff_set_error(error_message, "opening the Finder favorites list", 0);
  }
  return list;
}

static LSSharedFileListItemRef ff_item_at(CFArrayRef items, CFIndex index) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
  LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, index);
#pragma clang diagnostic pop
  return item;
}

static LSSharedFileListItemRef ff_find_item(CFArrayRef items, uint32_t item_id) {
  CFIndex count = CFArrayGetCount(items);
  for (CFIndex index = 0; index < count; index++) {
    LSSharedFileListItemRef item = ff_item_at(items, index);
    if (LSSharedFileListItemGetID(item) == item_id) {
      return item;
    }
  }
  return NULL;
}

static LSSharedFileListItemRef ff_resolve_position(CFArrayRef items, enum FFBridgePosition position,
                                                   uint32_t after_item_id, char **error_message) {
  switch (position) {
  case FFBridgePositionBeforeFirst:
    return kLSSharedFileListItemBeforeFirst;
  case FFBridgePositionLast:
    return kLSSharedFileListItemLast;
  case FFBridgePositionAfterItem: {
    LSSharedFileListItemRef item = ff_find_item(items, after_item_id);
    if (item == NULL) {
      ff_set_error(error_message, "finding the requested anchor item", 0);
    }
    return item;
  }
  default:
    ff_set_error(error_message, "decoding the requested list position", EINVAL);
    return NULL;
  }
}

FFBridgeSnapshot *ff_bridge_copy_snapshot(char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  LSSharedFileListRef list = ff_create_list(error_message);
  if (list == NULL) {
    return NULL;
  }

  uint32_t seed = 0;
  CFArrayRef items = LSSharedFileListCopySnapshot(list, &seed);
  CFRelease(list);
  if (items == NULL) {
    ff_set_error(error_message, "reading the Finder favorites list", 0);
    return NULL;
  }

  size_t count = (size_t)CFArrayGetCount(items);
  FFBridgeSnapshot *snapshot = calloc(1, sizeof(FFBridgeSnapshot));
  if (snapshot == NULL) {
    CFRelease(items);
    ff_set_error(error_message, "allocating a Finder favorites snapshot", ENOMEM);
    return NULL;
  }
  snapshot->items = items;
  snapshot->seed = seed;
  snapshot->count = count;
  snapshot->display_names = calloc(count, sizeof(char *));
  snapshot->paths = calloc(count, sizeof(char *));
  snapshot->resolved = calloc(count, sizeof(bool));
  if ((count > 0) &&
      (snapshot->display_names == NULL || snapshot->paths == NULL || snapshot->resolved == NULL)) {
    ff_bridge_free_snapshot(snapshot);
    ff_set_error(error_message, "allocating Finder favorites item storage", ENOMEM);
    return NULL;
  }

  LSSharedFileListResolutionFlags flags =
      kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
  for (size_t index = 0; index < count; index++) {
    LSSharedFileListItemRef item = ff_item_at(items, (CFIndex)index);
    CFStringRef name = LSSharedFileListItemCopyDisplayName(item);
    snapshot->display_names[index] = ff_copy_cf_string(name);
    if (name != NULL) {
      CFRelease(name);
    }

    CFErrorRef resolution_error = NULL;
    CFURLRef url = LSSharedFileListItemCopyResolvedURL(item, flags, &resolution_error);
    if (url != NULL) {
      CFStringRef path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
      snapshot->paths[index] = ff_copy_cf_string(path);
      snapshot->resolved[index] = snapshot->paths[index] != NULL;
      if (path != NULL) {
        CFRelease(path);
      }
      CFRelease(url);
    }
    if (resolution_error != NULL) {
      CFRelease(resolution_error);
    }
    if (snapshot->display_names[index] == NULL) {
      snapshot->display_names[index] = strdup("");
    }
    if (snapshot->paths[index] == NULL) {
      snapshot->paths[index] = strdup("");
    }
  }
  return snapshot;
}

void ff_bridge_free_snapshot(FFBridgeSnapshot *snapshot) {
  if (snapshot == NULL) {
    return;
  }
  for (size_t index = 0; index < snapshot->count; index++) {
    free(snapshot->display_names == NULL ? NULL : snapshot->display_names[index]);
    free(snapshot->paths == NULL ? NULL : snapshot->paths[index]);
  }
  free(snapshot->display_names);
  free(snapshot->paths);
  free(snapshot->resolved);
  if (snapshot->items != NULL) {
    CFRelease(snapshot->items);
  }
  free(snapshot);
}

uint32_t ff_bridge_snapshot_seed(const FFBridgeSnapshot *snapshot) {
  return snapshot == NULL ? 0 : snapshot->seed;
}

size_t ff_bridge_snapshot_count(const FFBridgeSnapshot *snapshot) {
  return snapshot == NULL ? 0 : snapshot->count;
}

bool ff_bridge_snapshot_item(const FFBridgeSnapshot *snapshot, size_t index, uint32_t *item_id,
                             const char **display_name, const char **path, bool *resolved) {
  if (snapshot == NULL || index >= snapshot->count || item_id == NULL || display_name == NULL ||
      path == NULL || resolved == NULL) {
    return false;
  }
  LSSharedFileListItemRef item = ff_item_at(snapshot->items, (CFIndex)index);
  *item_id = LSSharedFileListItemGetID(item);
  *display_name = snapshot->display_names[index];
  *path = snapshot->paths[index];
  *resolved = snapshot->resolved[index];
  return true;
}

int ff_bridge_insert(const char *display_name, const char *path, enum FFBridgePosition position,
                     uint32_t after_item_id, uint32_t *inserted_item_id, char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (display_name == NULL || path == NULL || inserted_item_id == NULL) {
    ff_set_error(error_message, "validating an insertion request", EINVAL);
    return EINVAL;
  }
  LSSharedFileListRef list = ff_create_list(error_message);
  if (list == NULL) {
    return EIO;
  }
  CFArrayRef items = LSSharedFileListCopySnapshot(list, NULL);
  if (items == NULL) {
    CFRelease(list);
    ff_set_error(error_message, "reading the Finder favorites list", 0);
    return EIO;
  }
  LSSharedFileListItemRef anchor =
      ff_resolve_position(items, position, after_item_id, error_message);
  if (anchor == NULL) {
    CFRelease(items);
    CFRelease(list);
    return ENOENT;
  }

  CFStringRef name =
      CFStringCreateWithCString(kCFAllocatorDefault, display_name, kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)path,
                                                         (CFIndex)strlen(path), true);
  if (name == NULL || url == NULL) {
    if (name != NULL) {
      CFRelease(name);
    }
    if (url != NULL) {
      CFRelease(url);
    }
    CFRelease(items);
    CFRelease(list);
    ff_set_error(error_message, "encoding an insertion request", EINVAL);
    return EINVAL;
  }

  LSSharedFileListItemRef inserted =
      LSSharedFileListInsertItemURL(list, anchor, name, NULL, url, NULL, NULL);
  CFRelease(name);
  CFRelease(url);
  CFRelease(items);
  CFRelease(list);
  if (inserted == NULL) {
    ff_set_error(error_message, "inserting a Finder favorite", 0);
    return EIO;
  }
  *inserted_item_id = LSSharedFileListItemGetID(inserted);
  CFRelease(inserted);
  return 0;
}

int ff_bridge_move(uint32_t item_id, enum FFBridgePosition position, uint32_t after_item_id,
                   char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  LSSharedFileListRef list = ff_create_list(error_message);
  if (list == NULL) {
    return EIO;
  }
  CFArrayRef items = LSSharedFileListCopySnapshot(list, NULL);
  if (items == NULL) {
    CFRelease(list);
    ff_set_error(error_message, "reading the Finder favorites list", 0);
    return EIO;
  }
  LSSharedFileListItemRef item = ff_find_item(items, item_id);
  LSSharedFileListItemRef anchor =
      ff_resolve_position(items, position, after_item_id, error_message);
  if (item == NULL || anchor == NULL) {
    CFRelease(items);
    CFRelease(list);
    if (item == NULL) {
      ff_set_error(error_message, "finding the item to move", 0);
    }
    return ENOENT;
  }
  OSStatus status = LSSharedFileListItemMove(list, item, anchor);
  CFRelease(items);
  CFRelease(list);
  if (status != noErr) {
    ff_set_error(error_message, "moving a Finder favorite", (int)status);
    return (int)status;
  }
  return 0;
}

int ff_bridge_remove(uint32_t item_id, char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  LSSharedFileListRef list = ff_create_list(error_message);
  if (list == NULL) {
    return EIO;
  }
  CFArrayRef items = LSSharedFileListCopySnapshot(list, NULL);
  if (items == NULL) {
    CFRelease(list);
    ff_set_error(error_message, "reading the Finder favorites list", 0);
    return EIO;
  }
  LSSharedFileListItemRef item = ff_find_item(items, item_id);
  if (item == NULL) {
    CFRelease(items);
    CFRelease(list);
    return 0;
  }
  OSStatus status = LSSharedFileListItemRemove(list, item);
  CFRelease(items);
  CFRelease(list);
  if (status != noErr) {
    ff_set_error(error_message, "removing a Finder favorite", (int)status);
    return (int)status;
  }
  return 0;
}

void ff_bridge_free_error(char *error_message) { free(error_message); }

#pragma clang diagnostic pop
