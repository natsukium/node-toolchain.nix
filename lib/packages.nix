{ pkgs }:
let
  inherit (pkgs) lib callPackage;
  catalog = import ./catalog.nix { inherit lib; };
  system = pkgs.stdenv.hostPlatform.system;

  orThrow = value: message: if value == null then throw "node-toolchain: ${message}" else value;

  # `versions` keyed by version, plus the newest stable release overall and per major.
  versionSet =
    versions:
    let
      names = builtins.attrNames versions;
      stable = builtins.filter catalog.isStable names;
    in
    {
      inherit versions;
      latest = versions.${catalog.newest stable};
      majors = lib.mapAttrs (_: vs: versions.${catalog.newest vs}) (
        lib.groupBy (v: lib.versions.major v) stable
      );
      fromVersion =
        prefix:
        versions.${orThrow (catalog.resolve names prefix) "no version matching '${prefix}' for ${system}"};
    };
in
rec {
  mkNodejs =
    {
      version,
      hash ? catalog.nodejsHash version system,
    }:
    callPackage ../pkgs/nodejs-bin.nix {
      inherit version;
      hash = orThrow hash "Node.js ${version} for ${system} is not in the catalog; update the node-toolchain input or pass `hashes.nodejs`";
    };

  mkScript = args: callPackage ../pkgs/node-script.nix ({ nodejs = pkgs.nodejs; } // args);

  mkPnpm =
    {
      version,
      hash ? catalog.pnpmHash version,
      exeHashes ? catalog.pnpmExeHashes version,
      nodejs ? pkgs.nodejs,
    }:
    let
      hash' = orThrow hash "pnpm ${version} is not in the catalog; pin it with `corepack use pnpm@${version}` or pass `hashes.packageManager`";
      # Releases newer than the catalog keep the entry points of the latest wrapper releases.
      bins = lib.defaultTo {
        pnpm = "bin/pnpm.mjs";
        pnpx = "bin/pnpx.mjs";
      } (catalog.pnpmBins version);
    in
    if lib.versionAtLeast version "12" then
      callPackage ../pkgs/pnpm-native.nix {
        inherit version nodejs exeHashes;
        hash = hash';
      }
    else if bins == { } then
      throw "node-toolchain: pnpm ${version} ships no executable"
    else
      mkScript {
        inherit version nodejs bins;
        pname = "pnpm";
        hash = hash';
        url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
        # fetchPnpmDeps reads the Node.js it runs pnpm with from here.
        passthru.nodejs-slim = nodejs;
      };

  node-bin = versionSet (
    lib.genAttrs (catalog.nodejsVersions system) (version: mkNodejs { inherit version; })
  );

  pnpm-bin = versionSet (lib.genAttrs catalog.pnpmVersions (version: mkPnpm { inherit version; }));
}
