# pnpm >= 12: the npm package is a wrapper that downloads a native binary on first run,
# so the binary is fetched here per platform and put where the wrapper's install.js
# would put it, next to the dist/ payload it loads node-gyp from.
{
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
  version,
  hash,
  exeHashes,
}:
let
  targets = {
    aarch64-darwin = "darwin-arm64";
    x86_64-darwin = "darwin-x64";
    # musl builds are statically linked and need no patchelf.
    aarch64-linux = "linux-arm64-musl";
    x86_64-linux = "linux-x64-musl";
  };
  system = stdenvNoCC.hostPlatform.system;
  target = targets.${system} or (throw "node-toolchain: pnpm ${version} has no binary for ${system}");
  exeHash =
    exeHashes.${system}
      or (throw "node-toolchain: the pnpm ${version} binary for ${system} is not in the catalog; update the node-toolchain input or pass `hashes.pnpmExe.${system}` (integrity of @pnpm/exe.${target}@${version})");
in
stdenvNoCC.mkDerivation {
  pname = "pnpm";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
    inherit hash;
  };

  exe = fetchurl {
    url = "https://registry.npmjs.org/@pnpm/exe.${target}/-/exe.${target}-${version}.tgz";
    hash = exeHash;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    cp -R . $out/libexec/pnpm
    tar -xzf $exe -O package/pnpm > $out/libexec/pnpm/pnpm
    chmod 755 $out/libexec/pnpm/pnpm
    # A wrapper rather than a symlink, so the binary's own path stays next to dist/.
    makeWrapper $out/libexec/pnpm/pnpm $out/bin/pnpm
    makeWrapper $out/libexec/pnpm/pnpm $out/bin/pnpx --add-flags dlx
    ln -s pnpm $out/bin/pn
    ln -s pnpx $out/bin/pnx
    runHook postInstall
  '';

  passthru.nodejs-slim = nodejs;

  meta.mainProgram = "pnpm";
}
