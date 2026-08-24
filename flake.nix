{
  description = "noctalia plugins, and the helper binary one of them needs";

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
        { pkgs, lib, ... }:
        let
          extWorkspaceXml = "${pkgs.wayland-protocols}/share/wayland-protocols/staging/ext-workspace/ext-workspace-v1.xml";
        in
        {
          packages = {
            omarchy-import =
              let
                raw = pkgs.writers.writePython3Bin "omarchy-import" {
                  flakeIgnore = [
                    "E501"
                    "E203"
                    "W503"
                  ];
                } (builtins.readFile ./omarchy-import/omarchy_import.py);
              in
              pkgs.symlinkJoin {
                name = "omarchy-import";
                paths = [ raw ];
                nativeBuildInputs = [ pkgs.makeWrapper ];

                postBuild = ''
                  wrapProgram $out/bin/omarchy-import \
                    --prefix PATH : ${
                      lib.makeBinPath (
                        with pkgs;
                        [
                          git
                          imagemagick
                          lua5_4
                        ]
                      )
                    } \
                    --set-default OMARCHY_IMPORT_EXTRACTOR ${./omarchy-import/extract_spec.lua}
                '';

                meta = {
                  description = "import an omarchy theme as a noctalia palette, wallpaper folder and neovim entry";
                  mainProgram = "omarchy-import";
                  license = lib.licenses.mit;
                  platforms = lib.platforms.linux;
                };
              };

            umbriel-workspace-watch = pkgs.stdenv.mkDerivation {
              pname = "umbriel-workspace-watch";
              version = "1.0.0";

              src = lib.fileset.toSource {
                root = ./umbriel-layout/watch;
                fileset = ./umbriel-layout/watch/main.c;
              };

              nativeBuildInputs = with pkgs; [
                pkg-config
                wayland-scanner
              ];

              buildInputs = [ pkgs.wayland ];

              buildPhase = ''
                runHook preBuild

                wayland-scanner client-header ${extWorkspaceXml} ext-workspace-v1-client-protocol.h
                wayland-scanner private-code ${extWorkspaceXml} ext-workspace-v1-protocol.c

                $CC -O2 -Wall -Wextra -o umbriel-workspace-watch \
                  main.c ext-workspace-v1-protocol.c \
                  $(pkg-config --cflags --libs wayland-client)

                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                install -Dm755 umbriel-workspace-watch $out/bin/umbriel-workspace-watch
                runHook postInstall
              '';

              meta = {
                description = "print the active ext-workspace workspace per output, one line per change";
                mainProgram = "umbriel-workspace-watch";
                license = lib.licenses.mit;
                platforms = lib.platforms.linux;
              };
            };

            default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.umbriel-workspace-watch;

            watch-dev = pkgs.writeShellApplication {
              name = "umbriel-workspace-watch-dev";

              runtimeInputs = [ pkgs.wayland-scanner ];

              text = ''
                target=''${1:-$PWD}
                if [ ! -f "$target/main.c" ]; then
                  echo "umbriel-workspace-watch-dev: no main.c in $target" >&2
                  echo "run this from umbriel-layout/watch, or pass it as an argument" >&2
                  exit 1
                fi
                cd "$target"

                wayland-scanner client-header ${extWorkspaceXml} ext-workspace-v1-client-protocol.h
                wayland-scanner private-code ${extWorkspaceXml} ext-workspace-v1-protocol.c

                printf '%s\n' \
                  -std=c11 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion \
                  -I. "-I${lib.getDev pkgs.wayland}/include" > compile_flags.txt

                echo "wrote ext-workspace-v1-client-protocol.h, ext-workspace-v1-protocol.c, compile_flags.txt"
                echo "restart the language server to pick them up"
              '';

              meta.description = "generate the protocol header and clangd flags for umbriel-workspace-watch";
            };

            catalog = pkgs.writeShellApplication {
              name = "noctalia-plugins-catalog";

              runtimeInputs = [ pkgs.python3 ];

              text = ''
                exec python3 ${./tools/generate-catalog.py} "''${1:-$PWD}"
              '';

              meta.description = "regenerate catalog.toml from the plugin manifests";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              wayland
              wayland-scanner
              wayland-protocols
              pkg-config
              clang-tools
              python3
            ];
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
