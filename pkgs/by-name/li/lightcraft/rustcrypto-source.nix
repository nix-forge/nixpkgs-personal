# Preserve the existing crypto provider while removing its obsolete parser dependency.
{ applyPatches, fetchurl }:
applyPatches {
  name = "rustls-rustcrypto-0.0.2-alpha-craft-source";
  src = fetchurl {
    name = "rustls-rustcrypto-0.0.2-alpha.tar.gz";
    url = "https://static.crates.io/crates/rustls-rustcrypto/rustls-rustcrypto-0.0.2-alpha.crate";
    hash = "sha256-8SBSlHdjq4UV91MxU1dZnpsLTas7i6FfMPcl/m0CVVc=";
  };
  patches = [ ./rustcrypto-pki-types.patch ];
}
