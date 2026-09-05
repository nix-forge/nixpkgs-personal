#ifndef FINDER_FAVORITES_BRIDGE_H
#define FINDER_FAVORITES_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct FFBridgeSnapshot FFBridgeSnapshot;

int ff_bridge_argument_count(void);
const char *_Nullable ff_bridge_argument_at(int index);

enum FFBridgePosition {
  FFBridgePositionBeforeFirst = 0,
  FFBridgePositionLast = 1,
  FFBridgePositionAfterItem = 2,
};

/**
 * Copies a snapshot owned by the caller. Release it with
 * ff_bridge_free_snapshot. On failure, error_message receives an allocated
 * string that the caller releases with ff_bridge_free_error.
 */
FFBridgeSnapshot *_Nullable ff_bridge_copy_snapshot(char *_Nullable *_Nullable error_message);
void ff_bridge_free_snapshot(FFBridgeSnapshot *_Nullable snapshot);
uint32_t ff_bridge_snapshot_seed(const FFBridgeSnapshot *_Nonnull snapshot);
size_t ff_bridge_snapshot_count(const FFBridgeSnapshot *_Nonnull snapshot);

/** Returned display_name and path pointers are borrowed from snapshot. */
bool ff_bridge_snapshot_item(const FFBridgeSnapshot *_Nonnull snapshot, size_t index,
                             uint32_t *_Nonnull item_id,
                             const char *_Nullable *_Nonnull display_name,
                             const char *_Nullable *_Nonnull path, bool *_Nonnull resolved);

int ff_bridge_insert(const char *_Nonnull display_name, const char *_Nonnull path,
                     enum FFBridgePosition position, uint32_t after_item_id,
                     uint32_t *_Nonnull inserted_item_id, char *_Nullable *_Nullable error_message);
int ff_bridge_move(uint32_t item_id, enum FFBridgePosition position, uint32_t after_item_id,
                   char *_Nullable *_Nullable error_message);
int ff_bridge_remove(uint32_t item_id, char *_Nullable *_Nullable error_message);
void ff_bridge_free_error(char *_Nullable error_message);

#endif
