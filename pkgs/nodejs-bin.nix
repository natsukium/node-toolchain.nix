{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  version,
  hash,
}:
let
  platforms = {
    aarch64-darwin = "darwin-arm64";
    x86_64-darwin = "darwin-x64";
    aarch64-linux = "linux-arm64";
    x86_64-linux = "linux-x64";
  };
  system = stdenv.hostPlatform.system;
  platform =
    platforms.${system} or (throw "node-toolchain: no official Node.js binary for ${system}");
in
stdenv.mkDerivation {
  pname = "nodejs";
  inherit version;

  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-${platform}.tar.xz";
    inherit hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];

  dontConfigure = true;
  dontBuild = true;
  # Stripping or adding an RPATH (as autoPatchelfHook does) relocates .dynamic in
  # the official binary and makes it segfault on start, so the libraries outside
  # glibc are linked by absolute path instead.
  dontStrip = true;
  dontPatchELF = true;

  # The official macOS binary reads the system OpenSSL configuration on start, which
  # the build sandbox denies unless every dependent build may read it.
  __propagatedImpureHostDeps = lib.optionals stdenv.hostPlatform.isDarwin [
    "/System/Library/OpenSSL"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R bin include lib share $out/
    runHook postInstall
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf $out/bin/node \
      --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
      --replace-needed libstdc++.so.6 ${lib.getLib stdenv.cc.cc}/lib/libstdc++.so.6 \
      --replace-needed libgcc_s.so.1 ${
        stdenv.cc.cc.libgcc or (lib.getLib stdenv.cc.cc)
      }/lib/libgcc_s.so.1
  '';

  meta = {
    description = "Official prebuilt Node.js binary";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    platforms = builtins.attrNames platforms;
    mainProgram = "node";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
