# WireGuard roaming controller

`wireguard-roaming-controller` safely manages a full-system `wg-quick` tunnel
on macOS. It is self-contained: it does not identify the local Wi-Fi network,
query another host, or require a NixOS system.

The nix-darwin module defaults to manual control:

```nix
{
  services.wireguardRoaming = {
    enable = true;
    interfaceName = "home-vpn";
    autoConnect = false;
  };
}
```

The configured interface must use `autostart = false` and keep its private key
outside the Nix store. The module installs the `wireguard-roaming` command:

```console
sudo wireguard-roaming up
sudo wireguard-roaming down
sudo wireguard-roaming status
sudo wireguard-roaming recover-dns
```

Manual mode installs no background daemon. Set `autoConnect = true` only for an
always-on tunnel that should connect on every usable network. In that mode the
controller yields to an active native macOS VPN, validates a fresh WireGuard
handshake and HTTPS connectivity after activation, and rolls back routes and
DNS if activation is unhealthy.

The module deliberately has no automatic trusted-network exception. macOS can
provide that policy through a signed Network Extension VPN app, but a generic
`wg-quick` daemon cannot securely identify one Wi-Fi network without either
location-sensitive SSID access or an external trust dependency.
