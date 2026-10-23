{ lib }:
let
  nodejs = lib.importJSON ../versions/nodejs.json;
  pnpm = lib.importJSON ../versions/pnpm.json;

  isStable = v: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" v != null;
  newest = vs: lib.last (lib.sort lib.versionOlder vs);
  # A partial version such as "22" or "22.1" matches 22.1.x.
  matches =
    prefix: v:
    let
      p = lib.splitVersion prefix;
    in
    lib.take (builtins.length p) (lib.splitVersion v) == p;
in
{
  nodejsVersions = system: builtins.filter (v: nodejs.${v} ? ${system}) (builtins.attrNames nodejs);

  nodejsHash =
    version: system:
    let
      hex = nodejs.${version}.${system} or null;
    in
    if hex == null then
      null
    else
      builtins.convertHash {
        hash = hex;
        hashAlgo = "sha256";
        toHashFormat = "sri";
      };

  pnpmVersions = builtins.attrNames pnpm;
  pnpmHash = version: pnpm.${version}.integrity or null;
  pnpmExeHashes = version: pnpm.${version}.exe or { };
  pnpmBins = version: pnpm.${version}.bin or null;

  # The newest stable version among `versions` that `prefix` matches, or null.
  resolve =
    versions: prefix:
    let
      candidates = builtins.filter (v: isStable v && matches prefix v) versions;
    in
    if candidates == [ ] then null else newest candidates;

  inherit isStable newest matches;
}
