{ pkgs, self }:
let
  inherit (pkgs) lib;
  packages = import ../lib/packages.nix { inherit pkgs; };

  toolchain =
    name: args:
    self.lib.mkToolchain (
      {
        inherit pkgs;
        src = ./fixtures/${name};
      }
      // args
    );

  # Fails unless every command prints exactly the expected version.
  expectVersions =
    name: tc: expected:
    pkgs.runCommand "test-${name}" { nativeBuildInputs = tc.packages; } ''
      export HOME=$TMPDIR
      ${lib.concatStrings (
        lib.mapAttrsToList (cmd: version: ''
          actual=$(${cmd})
          if [ "$actual" != "${version}" ]; then
            echo "${cmd}: expected ${version}, got $actual" >&2
            exit 1
          fi
        '') expected
      )}
      touch $out
    '';

  expectThrow =
    name: value:
    assert lib.assertMsg (!(builtins.tryEval value).success) "${name}: expected evaluation to fail";
    pkgs.emptyFile;

  expectEqual =
    name: actual: expected:
    assert lib.assertMsg (actual == expected) "${name}: expected ${expected}, got ${actual}";
    pkgs.emptyFile;
in
{
  pnpm10-uses-hash-from-packageManager = expectVersions "pnpm10" (toolchain "pnpm10" { }) {
    "pnpm --version" = "10.34.5";
  };

  pnpm11-takes-node-major-from-nvmrc = expectVersions "pnpm11" (toolchain "pnpm11" { }) {
    "pnpm --version" = "11.27.0";
    "node --version | cut -d. -f1" = "v22";
  };

  pnpm12-takes-native-binary-from-catalog = expectVersions "pnpm12" (toolchain "pnpm12" { }) {
    "pnpm --version" = "12.9.0";
  };

  pnpm-without-hash-takes-catalog = expectVersions "no-hash" (toolchain "no-hash" { }) {
    "pnpm --version" = "10.34.5";
  };

  explicit-hash-overrides-catalog =
    let
      hash = "sha512-${lib.fixedWidthString 86 "A" ""}==";
    in
    expectEqual "explicit-hash"
      (toolchain "no-hash" { hashes.packageManager = hash; }).pnpm.src.outputHash
      hash;

  yarn-without-hash-requires-explicit-hash =
    expectThrow "yarn-no-hash"
      (toolchain "yarn-no-hash" { }).yarn.drvPath;

  yarn1-classic = expectVersions "yarn1" (toolchain "yarn1" { }) { "yarn --version" = "1.22.22"; };

  yarn4-berry-takes-node-major-from-devEngines = expectVersions "yarn4" (toolchain "yarn4" { }) {
    "yarn --version" = "4.18.1";
    "node --version | cut -d. -f1" = "v26";
  };

  npm-shadows-bundled-npm = expectVersions "npm" (toolchain "npm" { }) {
    "npm --version" = "12.2.1";
  };

  node-exact-takes-official-binary-from-catalog = expectVersions "node-exact" (toolchain "node-exact"
    { }
  ) { "node --version" = "v24.20.0"; };

  node-exact-accepts-explicit-hashes = expectVersions "node-exact-explicit" (toolchain "node-exact" {
    hashes.nodejs = {
      aarch64-darwin = "sha256-t793BwcLlQuh7F8a87tt4PKxlixQM5c9lAaKsCHvMBQ=";
      aarch64-linux = "sha256-X03athDBqyAWs8Inzr2/bZSVFhSH5HOce5AJBZX0Zfc=";
      x86_64-linux = "sha256-LywNoWIxjw3kdmVBDHyMLtPTbI8xBd5LvGEXbHCny/I=";
    };
  }) { "node --version" = "v24.20.0"; };

  node-partial-falls-back-to-catalog-without-nixpkgs-major = expectVersions "node-partial" (toolchain
    "node-partial"
    { }
  ) { "node --version" = "v${packages.node-bin.majors."20".version}"; };

  node-range-in-devEngines-falls-through-to-nvmrc = expectVersions "node-range" (toolchain
    "node-range"
    { }
  ) { "node --version | cut -d. -f1" = "v22"; };

  nodeVersion-argument-accepts-v-prefix = expectVersions "node-arg" (toolchain "no-hash" {
    nodeVersion = "v24.20.0";
  }) { "node --version" = "v24.20.0"; };

  pnpm-takes-entry-points-from-catalog = expectVersions "pnpm2" {
    packages = [ packages.pnpm-bin.versions."2.16.2" ];
  } { "pnpm --version" = "2.16.2"; };

  overlay-adds-version-sets =
    let
      pkgs' = pkgs.extend self.overlays.default;
    in
    assert pkgs'.pnpm == pkgs.pnpm;
    expectVersions "overlay" {
      packages = [ pkgs'.pnpm-bin.versions."11.27.0" ];
    } { "pnpm --version" = "11.27.0"; };

  overlay-fromProject-accepts-path =
    let
      pkgs' = pkgs.extend self.overlays.default;
    in
    expectVersions "fromProject-path" (pkgs'.node-toolchain.fromProject ./fixtures/pnpm10) {
      "pnpm --version" = "10.34.5";
    };

  overlay-fromProject-accepts-flake-self =
    let
      pkgs' = pkgs.extend self.overlays.default;
    in
    expectVersions "fromProject-self" (pkgs'.node-toolchain.fromProject {
      outPath = ./fixtures/pnpm10;
      _type = "flake";
    }) { "pnpm --version" = "10.34.5"; };

  overlay-fromProject-accepts-arguments =
    let
      pkgs' = pkgs.extend self.overlays.default;
    in
    expectVersions "fromProject-args"
      (pkgs'.node-toolchain.fromProject {
        src = ./fixtures/pnpm10;
        nodeVersion = "24.20.0";
      })
      {
        "pnpm --version" = "10.34.5";
        "node --version" = "v24.20.0";
      };
}
