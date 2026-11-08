# Noctalia personal

This package builds pinned upstream Noctalia with a general bar icon policy
and landscape playback cards on the Control Center Media page. The patches
contain no application names or application-specific artwork.

On IWD systems where another service configures IP addresses and routes, the
network bar uses the kernel's preferred default-route interface when it is a
physical wired link. The Control Center's current connection then shows that
wired link, while its Wi-Fi list still shows the associated access point. Its
current-connection disconnect button is hidden in this state because IWD does
not control the wired link. Route changes update the display through netlink.
If IPv4 and IPv6 prefer different links, the bar keeps the IWD connection view
instead of claiming that either link is the sole uplink. This behavior does not
change routes, Wi-Fi association, or NetworkManager systems.

The pin is Noctalia 5.4.1, whose Hyprland backend supports both the legacy
numeric workspace IDs and the stable `address`/`type` workspace identities
used by newer Hyprland revisions. Keep that compatibility when updating the
source pin. Current Hyprland also includes a numeric `id` with `address` and
`type`, and uses `normal` for ordinary workspaces. The workspace backend accepts
that shape across workspace, monitor, and client snapshots.

Updates are manual because the local patches need review against each new
source revision. Refresh the pin in `source.nix`,
check each patch, and build the package before selecting it.

Upstream now supplies the Home date card behavior, so the local backport of
[PR #4578](https://github.com/noctalia-dev/noctalia/pull/4578) has been retired.
Its Hyprland backend also handles the current `id`/`address`/`normal` schema,
so the workspace IPC backport has been retired.

Version 5.3.0 also supplies size-aware vector tray icons, including theme
thresholds, scalable ranges and inherited status directories. Its upstream
icon-resolver regressions replace the former local tray-size patch. The
symbolic-icon and independently managed wired-uplink patches are rebased onto
the new tooltip settings and IWD diagnostics without changing their behavior.
The 5.4.1 port retains physical-size icon lookup and upstream symbolic-taskbar
rendering, including the separate `prefer_symbolic_icons` option. The existing
`symbolic_icons` option keeps its broader indicator-name fallback policy.
All six local patches apply without fuzz.

Configured tray overrides and explicit icon names use the same upstream
size-aware resolver as the remaining tray paths.

Upstream now hides the Home date card's weather row when the weather service is
disabled and opens the calendar instead. Enabling weather restores both its row
and its weather-page action. Review this behavior when updating the pinned source.

Minimal workspace capsules with inline labels and application icons use equal
label and icon hit cells, with larger gaps between workspaces than within them.
Application artwork remains at the configured size. Empty workspaces keep a
full label cell; longer names expand to fit. Inactive groups blend into the bar.
Selection and inactive-group hover share the standard taskbar foreground tint.
Urgency retains its semantic color. There are no outlines or stacked cell
highlights. Hovering an inactive group's label, icons, padding or gaps reveals
the fill behind the whole group. It persists while crossing between cells and
fades when leaving. Groups omit outer cross-axis padding, leaving more bar
surface above and below their 24-pixel hit cells. All states retain the same
geometry, and the application artwork stays the same size and opacity.
Other taskbar layouts retain upstream styling. Review the grouped rendering
when updating the source pin.

Placeholders and adjacent-month calendar labels use the semantic secondary-text
color at full opacity. Applying another opacity reduction to that role can make
an otherwise readable custom palette fail text contrast. Disabled controls keep
their upstream treatment. Slider handles use secondary text for their outline,
and scrollbars retain 85% of that role's opacity, so both remain visible on dark
surfaces. Palette authors still need to supply contrasting foreground/background
pairs. Review these five UI integrations when updating the pinned source.

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

On the Audio page, an exact PipeWire `application.id` match to an installed
desktop entry takes precedence over the audio renderer's executable name. This
lets applications using a helper such as mpv retain their own name and icon in
Application Volumes. Unknown IDs continue through upstream's binary and fuzzy
lookup. The pinned upstream source has no isolated test seam for this resolver;
check the displayed application name and icon with an identified helper stream
after updating the pin.

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

Vector status icons are selected for their displayed logical size within the
normal winner's theme, then rendered at the output's resolution. Fixed,
Threshold and Scalable directory ranges guide selection. Every root of a theme
uses its first usable index.theme metadata, including roots without an index.
This preserves size-specific artwork and prevents inherited status icons from
replacing higher-priority application or bitmap icons. The tray's attention-icon
and overlay handling remains intact.

The build checks symbolic precedence, lowercase matching, missing icons,
explicit paths, opt-out behavior, and safe fallback for non-symbolic artwork.
Resolver regressions cover size ranges and defaults, split themes, inheritance
collisions, and metadata-change invalidation.
When updating `source.nix`, review the three widget integrations and check
palette changes, focus changes and status icons in a running Wayland session.

## Build expression

The package extends the selected Nixpkgs `noctalia` builder and supplies the
source and version from `source.nix`. Nixpkgs owns library placement, wrappers,
completions, and version checks. The local override preserves its semantic
patches and notices, runs the upstream Meson suite with bounded parallelism,
and adds the bar icon,
route preference, and widget configuration checks. Review the selected builder
when updating Nixpkgs or the source pin.

The build verifies that upstream's `VERSION` file matches the pinned package version.

The native check supplies a private D-Bus session for all twelve upstream
integration cases and verifies the complete pinned test inventory before running
it. The inherited Nixpkgs updater is removed because this variant pins its own
source and requires patch review. The Nixpkgs binary wrapper adds Git and the
GSettings schema as fallbacks after caller paths. This differs from the former
prefix behavior; native wrapper and icon tests remain part of update review.
