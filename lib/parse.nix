{ lib }:
let
  readIfExists = path: if builtins.pathExists path then lib.trim (builtins.readFile path) else null;

  hashAlgos = [
    "md5"
    "sha1"
    "sha256"
    "sha512"
  ];
in
rec {
  # "pnpm@10.0.0+sha512.<hex>" -> { name; version; hash; }
  # `hash` is null when the spec has none or uses an algorithm Nix cannot verify (e.g. sha224).
  parsePackageManager =
    spec:
    let
      m = builtins.match "([^@]+)@([0-9]+\\.[0-9]+\\.[0-9]+[^+]*)(\\+([a-z0-9]+)\\.([0-9a-f]+))?" spec;
      algo = builtins.elemAt m 3;
    in
    if m == null then
      throw "node-toolchain: cannot parse packageManager '${spec}'; expected <name>@<exact version>[+<algo>.<hex>]"
    else
      {
        name = builtins.elemAt m 0;
        version = builtins.elemAt m 1;
        hash =
          if algo != null && builtins.elem algo hashAlgos then
            builtins.convertHash {
              hash = builtins.elemAt m 4;
              hashAlgo = algo;
              toHashFormat = "sri";
            }
          else
            null;
      };

  # Accepts "22", "22.1", "22.1.0" with an optional leading "v"; null for anything else.
  parseNodeVersion =
    raw:
    let
      m = builtins.match "v?([0-9]+(\\.[0-9]+(\\.[0-9]+)?)?)" raw;
    in
    if m == null then null else builtins.head m;

  devEnginesRuntime =
    manifest:
    let
      runtime = manifest.devEngines.runtime or [ ];
      node = lib.findFirst (r: (r.name or null) == "node") null (lib.toList runtime);
    in
    if node == null then null else node.version or null;

  # Sources in order of precedence; the first one present wins.
  nodeVersionSources = src: manifest: [
    {
      origin = "package.json#devEngines.runtime";
      value = devEnginesRuntime manifest;
    }
    {
      origin = ".node-version";
      value = readIfExists (src + "/.node-version");
    }
    {
      origin = ".nvmrc";
      value = readIfExists (src + "/.nvmrc");
    }
    {
      origin = "package.json#volta.node";
      value = manifest.volta.node or null;
    }
  ];

  # A range such as ">=20" in one source falls through to the next, since projects often
  # keep a range in devEngines next to an exact pin in .node-version or .nvmrc.
  detectNodeVersion =
    src: manifest:
    let
      present = builtins.filter (s: s.value != null) (nodeVersionSources src manifest);
      parsed = lib.findFirst (v: v != null) null (map (s: parseNodeVersion s.value) present);
      first = builtins.head present;
    in
    if present == [ ] then
      null
    else if parsed == null then
      throw "node-toolchain: unsupported node version '${first.value}' in ${first.origin}; only exact versions such as 22, 22.1 or 22.1.0 are supported, pass `nodeVersion` to override"
    else
      parsed;
}
