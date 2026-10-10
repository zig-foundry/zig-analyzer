{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    zig-flake.url = "github:silversquirl/zig-flake";
    zig-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    zig-flake,
  }: let
    lib = nixpkgs.lib;
    parseVersionFieldFromZon = name:
      lib.pipe ./build.zig.zon [
        builtins.readFile
        (builtins.match ".*\n[[:space:]]*\\.${name}[[:space:]]=[[:space:]]\"([^\"]+)\".*")
        builtins.head
      ];
    minimum_zig_version = parseVersionFieldFromZon "minimum_zig_version";
    zigAnalyzerVersionShort = parseVersionFieldFromZon "version";
    zigAnalyzerVersionFull =
      zigAnalyzerVersionShort
      + (
        if (builtins.length (builtins.splitVersion zigAnalyzerVersionShort)) == 3
        then ""
        else "+" + lib.replaceString "-" "." (self.dirtyShortRev or self.shortRev)
      );
  in
    builtins.foldl' lib.recursiveUpdate {} (
      builtins.map
      (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          fs = lib.fileset;
          zigVersion = lib.pipe minimum_zig_version [
            builtins.splitVersion
            (lib.sublist 0 5)
            (lib.concatStringsSep "_")
          ];
          zig = zig-flake.packages.${system}."zig_${zigVersion}";
          target = builtins.replaceStrings ["darwin"] ["macos"] system;
        in {
          formatter.${system} = pkgs.alejandra;
          packages.${system} = rec {
            default = zigAnalyzer;
            zigAnalyzer = pkgs.stdenvNoCC.mkDerivation {
              name = "zig-analyzer";
              version = zigAnalyzerVersionShort;
              meta.mainProgram = "zig_analyzer";
              src = fs.toSource {
                root = ./.;
                fileset = fs.intersection (fs.fromSource (lib.sources.cleanSource ./.)) (
                  fs.unions [
                    ./src
                    ./tests
                    ./build.zig
                    ./build.zig.zon
                    ./deps.nix
                  ]
                );
              };
              nativeBuildInputs = [zig];
              dontInstall = true;
              doCheck = true;
              configurePhase = ''
                export ZIG_GLOBAL_CACHE_DIR=$TEMP/.cache
                PACKAGE_DIR=${pkgs.callPackage ./deps.nix {}}
              '';
              buildPhase = ''
                zig build install --system $PACKAGE_DIR -Dtarget=${target} -Doptimize=ReleaseSafe -Dversion-string=${zigAnalyzerVersionFull} --color off --prefix $out
              '';
              checkPhase = ''
                zig build test --system $PACKAGE_DIR -Dtarget=${target} -Dversion-string=${zigAnalyzerVersionFull} --color off
              '';
            };
          };
        }
      )
      ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"]
    );
}
