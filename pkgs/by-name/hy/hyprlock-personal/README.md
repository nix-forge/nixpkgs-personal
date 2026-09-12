# Hyprlock authentication controls

This variant retains Hyprlock's PAM and fingerprint backends and the
ext-session-lock protocol. It adds a native pointer submit target and optional
left-aligned input text. Enter continues to submit through the existing handler.

```ini
general {
    hide_cursor = false
    ignore_empty_input = true
}
shape {
    submit_input = true
}
input-field {
    text_align = left
    padding_x = 23
    dots_center = false
}
```

Configure the shape's size, position and colors to create the button. Give only
its background shape the submit action. The action accepts the primary mouse
button, rejects input before lock acquisition or during checking/termination,
and respects the empty-input setting. It never executes an `onclick` command.
The disabled shape uses 0.55 opacity. Keyboard and pointer input use the
same authentication backend; no signal-based unlocking or input injection is used.

The submit shape can own `submit_icon` and `submit_icon_hover` PNG assets,
`submit_icon_size` in physical pixels, and `submit_hover_color`. The hover state
only applies while submission is available. Assets load through the existing
resource manager, and the background cache changes only with control state.
The icon retains its readable color when the button background dims.

`text_align` accepts `left` and `center`, with `center` as the default.
`padding_x` uses physical pixels. Its default of -1 preserves upstream spacing.
The submit action defaults off, preserving existing configurations.

Labels can use `$LAYOUT$CAPSLOCK` for the active keyboard layout and a Caps Lock
warning. Keyboard events update the label without external commands or polling.
`$CAPSLOCK` expands to " · Caps Lock is on" when active and to empty text otherwise.

`$AUTHCHECK` and `$AUTHFAIL` provide separate checking and failure captions.
Authentication state changes refresh them without polling. Failure messages are
escaped as text. Keep the input placeholder stable and place these captions in
a reserved status row to avoid moving the field on errors. A label can set
`capslock_color` to change its color while Caps Lock is active.
`input-field.check_opacity` dims the field during checking; its default of 1.0
preserves upstream rendering. It does not affect authentication or status labels.

Hyprlock draws borders outside the configured fill dimensions. Subtract both
border edges from a desired outer size and subtract the border from its corner
radius. Pango `span size` markup expresses fractional point sizes in units of
1/1024 of a point, avoiding the integer `font_size` rounding at fractional
output scales.

The source manifest pins commit 0332e40, including the upstream PAM termination
deadlock correction. The recipe uses the caller's upstream Nixpkgs build
dependencies. Consumers can override the `hyprlock` argument to retain another
reviewed dependency set. Source updates are manual because the submit guards
and backend lifecycle must be reviewed together. Review the patch, build the
package and test with a private compositor and synthetic PAM before updating.

The package builds the complete native binary. Runtime checks must include
empty input, first entry directly over submit, pointer re-entry, primary and
secondary clicks, delayed rejection, repeated clicks
while checking, keyboard Enter and fractional-scale hit detection. A rejected
credential must leave the private session locked. These tests do not establish
fingerprint hardware, monitor wake or real-session suspend behavior.

Upstream source and BSD-3-Clause license:
[Hyprlock](https://github.com/hyprwm/hyprlock/tree/0332e40b8e56404f11cd79f859f208a4b9de8714).
