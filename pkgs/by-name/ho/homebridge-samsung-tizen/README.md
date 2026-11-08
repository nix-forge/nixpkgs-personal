# Homebridge Samsung Tizen

This packages upstream version 6.1.1 from its tagged source and lockfile. It
targets Samsung Tizen TVs from 2017 onward, though individual model support
still requires a pairing test. The package does not contain a TV address, token,
or Homebridge configuration.

The build compiles upstream TypeScript and the configuration UI. The install
check loads the installed ESM plugin entrypoint. Build on the target
architecture and test pairing separately. The plugin uses Node 24, which is
supported by its upstream engine declaration.

Updates require reviewing the plugin's Homebridge and Node engine ranges, any
new network behavior, and its lockfile. Then update `source.nix` and build on
both Linux architectures. There is no unattended updater because compatibility
and pairing behavior require manual review.

## Experimental opt-in power-state compatibility

This option is not enabled in the deployed configuration. HTTP confirmation
alone does not prove panel illumination. Enable the option only after physical
panel state has been independently verified for the target model. Frame TVs are
rejected because their art-mode state requires a different detector.

The local `PowerState.Strict` device option is for televisions verified to return
`on` during viewing and an empty string, `standby`, or `off` in standby. Upstream falls back to reachability when the power field is unsupported. The option reads the HTTP power field
rather than TCP reachability, and corroborates it with a read-only UPnP
RenderingControl GetVolume response. HTTP On requires a valid volume response;
an observed standby value requires the rendering endpoint to refuse connection.
Contradictions, timeouts, malformed responses and other network failures remain
unknown. Failed cache reads are released so later checks can recover. The
rendering service is a corroborating signal, not proof of panel illumination.

On and Off requests re-read HTTP power state immediately before sending the
existing Samsung KEY_POWER command, and send nothing when already in the requested
state. An unknown On state may attempt Wake-on-LAN; an unknown Off state errors.
Queued requests wait up to 15 seconds for corroborated network observations to
confirm the requested state.
An unconfirmed command prevents another toggle until its target is confirmed. This is a guard around a toggle,
not a claim that this model supports a discrete off key. Network errors cannot
authorize the toggle. Preserve accessory MAC and UUID when enabling the option.

The installed-code regression check covers observed states, unknown/errors,
no command when already in the requested state, unknown-state WOL authorization, command ordering, refusing repeated unconfirmed
toggles, and the actual upstream SSDP, Frame and UPnP event router. A real TV must still be tested for wake, off, and extended standby.
See [upstream state issue 702](https://github.com/tavicu/homebridge-samsung-tizen/issues/702).
Retire this patch when a released upstream detector provides equivalent tested
state and safe command behavior.
