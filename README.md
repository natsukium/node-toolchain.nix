# node-toolchain.nix

Builds Node.js and the package manager pinned in your project (`package.json`, `.node-version`, `.nvmrc`) with Nix, so version pins live in one place and nothing downloads them at run time.

pnpm (>= 9.7) and Corepack read `package.json#packageManager` and attempt to download the pinned release themselves whenever the binary on `PATH` does not match. Instead of falling back to whatever nixpkgs ships, `node-toolchain.nix` fetches the exact pinned release and verifies it by hash.

- **Node.js**: 14 and later (`aarch64-darwin`, `aarch64-linux`, `x86_64-linux`)
- **Package managers**: `pnpm`, `yarn` (v1 Classic and v2+ Berry), `npm`

> [!WARNING]
> The API is not yet stable and may change without notice.

## Usage

### Development shell

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    node-toolchain.url = "git+https://git.natsukium.com/natsukium/node-toolchain.nix";
  };

  outputs =
    { nixpkgs, node-toolchain, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      toolchain = node-toolchain.lib.mkToolchain {
        inherit pkgs;
        src = ./.;
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = toolchain.packages;
      };
    };
}
```

### Building a package with `fetchPnpmDeps`

The `pnpm` derivation exposes `nodejs-slim` and `version`, so it works directly with `fetchPnpmDeps` and `pnpmConfigHook`:

```nix
let
  toolchain = node-toolchain.lib.mkToolchain {
    inherit pkgs;
    src = ./.;
  };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "my-app";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    toolchain.nodejs
    toolchain.pnpm
    pkgs.pnpmConfigHook
  ];

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit (toolchain) pnpm;
    fetcherVersion = 3;
    hash = "sha256-...";
  };

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';
})
```

### Overlay and standalone binaries

`overlays.default` adds `pkgs.node-toolchain.fromProject`, which accepts either a project path (including a flake's `self`) or the attribute set passed to `mkToolchain` without `pkgs`:

```nix
pkgs.node-toolchain.fromProject ./.
pkgs.node-toolchain.fromProject {
  src = ./.;
  nodeVersion = "24";
}
```

It also exposes every cataloged Node.js and pnpm release under `pkgs.node-bin` and `pkgs.pnpm-bin`:

```nix
pkgs.node-bin.latest
pkgs.node-bin.majors."24"
pkgs.node-bin.versions."24.20.0"
pkgs.node-bin.fromVersion "22.1"

pkgs.pnpm-bin.latest
pkgs.pnpm-bin.versions."10.34.5".override { nodejs = pkgs.node-bin.majors."24"; }
```

`latest` and `majors` only consider stable `x.y.z` releases. The overlay does not replace `pkgs.nodejs` or `pkgs.pnpm`, which would rebuild or alter the dependency hashes of every nixpkgs package that depends on them.

## Version detection

### Node.js

The Node.js version is taken from the first of these sources that specifies a plain version (`22`, `22.1`, `22.1.0`, with an optional `v` prefix):

1. `nodeVersion` passed to `mkToolchain` / `fromProject`
2. `package.json#devEngines.runtime` (entry with `name = "node"`)
3. `.node-version`
4. `.nvmrc`
5. `package.json#volta.node`
6. `pkgs.nodejs` (when none of the above is present)

Version ranges such as `>=20` are skipped so that a project can keep a broad constraint in `devEngines.runtime` alongside an exact pin in `.node-version` or `.nvmrc`. Evaluation fails only if one or more sources exist and none of them holds a plain version.

How the resolved version is built depends on its precision:

- **Exact version (`24.20.0`)**: Fetches the official prebuilt binary from `nodejs.org`.
- **Partial version (`24` or `24.1`)**: Prefers nixpkgs' `pkgs.nodejs_<major>` when its version matches the prefix (reusing the nixpkgs binary cache), and otherwise falls back to the newest matching official binary in the catalog.

### Package manager

The package manager is read from `package.json#packageManager` (`<name>@<exact-version>[+<algo>.<hex>]`). When the field is absent, `toolchain.packageManager` is `null` and `toolchain.packages` contains only `[ nodejs ]`.

## Hashes and pinning

Every downloaded artifact is verified by hash, resolved in the following order:

1. Explicit `hashes.*` passed to `mkToolchain` or `fromProject`
2. The `+sha512.<hex>` (or `sha256` / `sha1` / `md5`) suffix in `package.json#packageManager`
3. The bundled catalog (`versions/nodejs.json` and `versions/pnpm.json`)

If a version is missing from all three, evaluation fails rather than falling back to a different version.

### Node.js and pnpm (cataloged)

`versions/nodejs.json` and `versions/pnpm.json` record upstream hashes for Node.js 14+ and every pnpm release, refreshed automatically by a scheduled workflow (`./scripts/update.sh`). No hash configuration is needed in `package.json` or `flake.nix` for cataloged releases.

### Yarn and npm (require a hash)

Yarn and npm are not tracked in the catalog. Pin them with Corepack so `package.json#packageManager` includes a `+sha512.<hex>` suffix:

```sh
corepack use yarn@4.18.1
```

Or pass `hashes.packageManager` explicitly:

```nix
node-toolchain.lib.mkToolchain {
  inherit pkgs;
  src = ./.;
  hashes.packageManager = "sha512-...";
}
```

### Pinning releases not yet in the catalog

If a newly published Node.js or pnpm release is not yet in your locked `node-toolchain` input, either run `nix flake update node-toolchain` or supply the hashes directly:

```nix
node-toolchain.lib.mkToolchain {
  inherit pkgs;
  src = ./.;
  hashes = {
    # Requires an exact x.y.z Node.js version.
    nodejs = {
      aarch64-darwin = "sha256-...";
      aarch64-linux = "sha256-...";
      x86_64-linux = "sha256-...";
    };
    packageManager = "sha512-...";
    # Only needed for uncataloged pnpm >= 12 releases (dist.integrity of @pnpm/exe.<target>).
    pnpmExe = {
      aarch64-darwin = "sha512-...";
      aarch64-linux = "sha512-...";
      x86_64-linux = "sha512-...";
    };
  };
}
```

### Package manager artifacts

| `packageManager` | Fetched from | In catalog |
| ---------------- | ------------ | ---------- |
| `pnpm@<12` | `registry.npmjs.org/pnpm`, run with Node.js | yes |
| `pnpm@>=12` | the npm wrapper above plus the native `@pnpm/exe.<target>` binary | yes |
| `yarn@1` | `registry.yarnpkg.com/yarn` | no |
| `yarn@>=2` | `repo.yarnpkg.com/<version>/.../yarn.js` | no |
| `npm` | `registry.npmjs.org/npm` | no |

The `packageManager` hash corresponds to the artifact Corepack downloads. For pnpm 12 and later, the npm package is a wrapper that downloads a platform-specific `@pnpm/exe.<target>` binary on first run; `node-toolchain.nix` fetches both at build time using the catalog or `hashes.pnpmExe.<system>`.

## API reference

### `mkToolchain` / `pkgs.node-toolchain.fromProject`

**Arguments:**

| Argument | Default | Description |
| -------- | ------- | ----------- |
| `pkgs` | *(required in `mkToolchain`)* | Nixpkgs set for the target system |
| `src` | *(required)* | Project root containing `package.json` (and optionally `.node-version` / `.nvmrc`) |
| `nodeVersion` | `null` | Override the detected Node.js version (`"24"`, `"24.1"`, `"24.20.0"`) |
| `hashes` | `{ }` | Explicit SRI hashes (`nodejs.<system>`, `packageManager`, `pnpmExe.<system>`) |

**Returned attributes:**

| Attribute | Value |
| --------- | ----- |
| `packages` | `[ packageManager nodejs ]` (or `[ nodejs ]`), with the package manager first so a pinned `npm` shadows the one bundled with Node.js |
| `nodejs` | Selected Node.js derivation |
| `packageManager` | Selected package manager derivation, or `null` |
| `pnpm` / `yarn` / `npm` | Present when `packageManager` is set, aliased under its own name |

## License

[Apache License 2.0](./LICENSE)
