# Noctalia personal

This package builds pinned upstream Noctalia with a general bar icon policy
and landscape playback cards on the Control Center Media page. The patches
contain no application names or application-specific artwork.

Each available MPRIS endpoint gets its own compact card with artwork, track
metadata, previous/play-pause/next controls, and a seek bar when supported.
Paused sources remain visible. Endpoints are keyed by bus name, never grouped
by app identity or window; two endpoints with the same app name remain separate.
Controls address the card's endpoint directly. The small pin sets the media-key
target and moves that card to the top; clicking it again restores automatic
selection and the normal order. Transport controls do not change the pin or
reorder cards. Pins survive playback changes and clear when the source closes.
Artwork, metadata, controls, and timelines use shared column widths. MPRIS
signals are checked against the source's unique bus owner so a seek update from
one source cannot overwrite another card's timeline.

The Media page contains no audio-stream mixer or visualizer. Volume and mute
remain on the Audio page. A browser may expose only one selected MPRIS session
for several tabs: this page shows what the browser actually exports and cannot
provide independent per-tab playback without browser integration.

Set `symbolic_icons = true` in `[widget.active_window]` or `[widget.taskbar]`
to prefer symbolic artwork from the current icon theme. The resolver checks
standard symbolic and indicator naming conventions, including lowercase names,
and accepts icons in symbolic, panel or status contexts. These glyphs follow
the widget's foreground color. Icons without symbolic artwork retain their
original image: recoloring arbitrary images can erase logos or turn their
backgrounds into solid squares. Dock and launcher resolution stays upstream.

Tray lookup preserves the exact advertised icon name before considering desktop
application mappings. This keeps status-specific assets from being replaced by
ordinary app icons. Symbolic tray images follow the foreground; attention images
and overlays retain their status information. Applications supplying only a
pixmap retain that pixmap, which may contain badges or changing state.

For a known static pixmap, an explicit `[widget.tray.icon_overrides]` table can
map a stable tray identity to an icon-theme name. The existing tray identifier
matcher handles identities, and missing overrides fall back to normal lookup.
Overrides do not replace attention icons or overlays. This is configuration
data, not a new source patch for every application.

The build checks symbolic precedence, lowercase matching, missing icons,
explicit paths, opt-out behavior, and safe fallback for non-symbolic artwork.
When updating `source.nix`, review the three widget integrations and check
palette changes, focus changes and status icons in a running Wayland session.

## Build expression

`upstream.nix` records upstream's package expression at the revision in
`source.nix`, with source and version supplied as arguments. Evaluation does
not need to fetch upstream files to discover the build definition. Review
this expression alongside source updates. The local override places the linked
`jemalloc` library in target inputs so strict dependency checking works.

The build verifies that the Meson version matches the pinned package version.
