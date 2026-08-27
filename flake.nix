{
  description = "noctalia plugins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages = {
            catalog = pkgs.writeShellApplication {
              name = "noctalia-plugins-catalog";

              runtimeInputs = [ pkgs.python3 ];

              text = ''
                exec python3 ${./tools/generate-catalog.py} "''${1:-$PWD}"
              '';

              meta.description = "regenerate catalog.toml from the plugin manifests";
            };

            default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.catalog;
          };

          devShells.default = pkgs.mkShell {
            packages = [ pkgs.python3 ];
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
