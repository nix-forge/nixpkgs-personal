# Noctalia greeter with authentication feedback

This variant of Nixpkgs' Noctalia Greeter 1.5.0 adds a clock and date, keyboard
layout and Caps Lock feedback, stable authentication-status space, and explicit
confirmation before shutdown, restart, or firmware restart. Cancel receives
initial keyboard focus in the confirmation dialog. PAM and greetd remain the
authentication authorities.

The password reveal control supports keyboard focus and activation. Clearing or
submitting a password restores masking; pending authentication disables reveal.
Cancelling a power confirmation restores focus to its invoking control. Pointer
clicks activate only when released over the pressed control, so dragging away
cancels a press. Rebuilding a closed menu preserves pointer presses on other
controls, including the first power-button click from the password field.
Placeholder text uses the theme's full readable text color.
Text scaling follows the desktop independently of control and icon dimensions.
Focus rings use the secondary role; errors clear when a new password is edited.
Checking and failure captions share a centered reserved row.

The patch adds optional settings under `[appearance]`:

```toml
panel_width = 540
input_height = 48
font_scale = 1.0
clock_time_format = "%-I:%M %p"
clock_date_format = "%a, %b %-d"
```

Sizes are logical pixels. An omitted panel width keeps adaptive sizing; the
input defaults to 36 pixels. Clock formats use strftime and update once a minute.
`font_scale` is a positive text-only multiplier with a default of 1.0.
Omitting a format hides that label. Appearance, output policy and account
selection belong to the consuming configuration.
On compact outputs, the decorative bottom logo is hidden when it would
overlap the login panel.

The Meson check exercises confirmation and cancellation without invoking power
operations. The package build compiles the complete greeter and compositor.
These checks do not establish authentication, monitor wake or GPU behavior on a
particular workstation.

Source comes from the caller's Nixpkgs package and retains upstream's MIT
license. Nixpkgs updates select the upstream release. The package applies the
patch, compiles the greeter, and runs its tests on each build. A failed patch or
check calls for a review of the changed input and power-action paths before
rebasing the patch. A passing build still needs a preview to establish runtime
behavior on the target display.

Upstream: [Noctalia Greeter](https://github.com/noctalia-dev/noctalia-greeter).
