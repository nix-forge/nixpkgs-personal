# NUR and non-flake consumers supply their own Nixpkgs and package policy.
{ pkgs }: import ./pkgs { inherit pkgs; }
