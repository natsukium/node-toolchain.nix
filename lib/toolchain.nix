{
  pkgs,
  # Directory containing package.json and optionally .node-version / .nvmrc.
  src,
  # Overrides the version detected from `src`.
  nodeVersion ? null,
  # Explicit hashes take precedence over the packageManager hash and the catalog.
  hashes ? { },
}:
let
  inherit (pkgs) lib;
  parse = import ./parse.nix { inherit lib; };
  packages = import ./packages.nix { inherit pkgs; };
  catalog = import ./catalog.nix { inherit lib; };

  manifest = lib.importJSON (src + "/package.json");
  system = pkgs.stdenv.hostPlatform.system;

  nodeVersion' =
    if nodeVersion == null then
      parse.detectNodeVersion src manifest
    else
      lib.defaultTo (throw "node-toolchain: unsupported `nodeVersion` '${nodeVersion}'; expected a version such as 22, 22.1 or 22.1.0") (
        parse.parseNodeVersion nodeVersion
      );
  isExact = v: builtins.length (lib.splitVersion v) == 3;

  nodejs =
    if nodeVersion' == null then
      pkgs.nodejs
    else if hashes ? nodejs then
      if !isExact nodeVersion' then
        throw "node-toolchain: `hashes.nodejs` pins an exact binary, but node version '${nodeVersion'}' is not a full x.y.z version"
      else
        packages.mkNodejs {
          version = nodeVersion';
          hash =
            hashes.nodejs.${system} or (throw "node-toolchain: `hashes.nodejs` has no entry for ${system}");
        }
    else if isExact nodeVersion' then
      packages.mkNodejs { version = nodeVersion'; }
    else
      # A partial version leaves the patch release open, so nixpkgs' build is preferred
      # for its binary cache and falls back to the newest matching official binary.
      let
        # End-of-life majors remain in nixpkgs as aliases that throw.
        found = builtins.tryEval (pkgs."nodejs_${lib.versions.major nodeVersion'}" or null);
        candidate = if found.success then found.value else null;
      in
      if candidate != null && catalog.matches nodeVersion' candidate.version then
        candidate
      else
        packages.node-bin.fromVersion nodeVersion';

  spec =
    if manifest ? packageManager then parse.parsePackageManager manifest.packageManager else null;

  # Script-based package managers are platform independent, so the packageManager hash suffices.
  pmHash =
    hashes.packageManager or (
      if spec.hash != null then
        spec.hash
      else
        throw "node-toolchain: packageManager '${manifest.packageManager}' has no hash Nix can verify; add one with `corepack use ${spec.name}@${spec.version}` or pass `hashes.packageManager`"
    );

  scriptPackage =
    args:
    packages.mkScript (
      {
        inherit nodejs;
        pname = spec.name;
        inherit (spec) version;
        hash = pmHash;
      }
      // args
    );

  packageManager =
    if spec == null then
      null
    else if spec.name == "pnpm" then
      packages.mkPnpm (
        {
          inherit nodejs;
          inherit (spec) version;
        }
        // lib.optionalAttrs (hashes ? packageManager || spec.hash != null) { hash = pmHash; }
        // lib.optionalAttrs (hashes ? pnpmExe) { exeHashes = hashes.pnpmExe; }
      )
    else if spec.name == "yarn" then
      if lib.versionOlder spec.version "2" then
        scriptPackage {
          url = "https://registry.yarnpkg.com/yarn/-/yarn-${spec.version}.tgz";
          bins = {
            yarn = "bin/yarn.js";
            yarnpkg = "bin/yarn.js";
          };
        }
      else
        scriptPackage {
          url = "https://repo.yarnpkg.com/${spec.version}/packages/yarnpkg-cli/bin/yarn.js";
          isArchive = false;
          bins = {
            yarn = "yarn.js";
            yarnpkg = "yarn.js";
          };
        }
    else if spec.name == "npm" then
      scriptPackage {
        url = "https://registry.npmjs.org/npm/-/npm-${spec.version}.tgz";
        bins = {
          npm = "bin/npm-cli.js";
          npx = "bin/npx-cli.js";
        };
      }
    else
      throw "node-toolchain: unsupported package manager '${spec.name}'";
in
{
  inherit nodejs packageManager;
  # The package manager comes first so that its npm shadows the one bundled with Node.js.
  packages = lib.optional (packageManager != null) packageManager ++ [ nodejs ];
}
// lib.optionalAttrs (spec != null) { ${spec.name} = packageManager; }
