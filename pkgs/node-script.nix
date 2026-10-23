# Package managers distributed as JavaScript entry points run by Node.js.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
  pname,
  version,
  hash,
  url,
  # Single-file distributions such as Yarn Berry's yarn.js are not archives.
  isArchive ? true,
  # Executable name -> entry point relative to the unpacked package.
  bins,
  passthru ? { },
}:
stdenvNoCC.mkDerivation {
  inherit pname version passthru;

  # The wrappers run Node.js without it being an input of the builds that use them.
  __propagatedImpureHostDeps = nodejs.__propagatedImpureHostDeps or [ ];

  src = fetchurl { inherit url hash; };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = !isArchive;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec/${pname}
    ${
      if isArchive then
        "cp -R . $out/libexec/${pname}"
      else
        "install -m644 $src $out/libexec/${pname}/${builtins.head (builtins.attrValues bins)}"
    }
    ${lib.concatStrings (
      lib.mapAttrsToList (bin: entry: ''
        makeWrapper ${lib.getExe nodejs} $out/bin/${bin} \
          --add-flags $out/libexec/${pname}/${entry}
      '') bins
    )}
    runHook postInstall
  '';

  meta.mainProgram = pname;
}
