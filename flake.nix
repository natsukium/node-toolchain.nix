{
  description = "Nix packages for Node.js and the package manager pinned in package.json";

  outputs =
    { self }:
    {
      lib.mkToolchain = import ./lib/toolchain.nix;

      # Adds attributes without replacing `nodejs` or `pnpm`, which would rebuild
      # everything in nixpkgs that depends on them.
      overlays.default = final: _prev: {
        inherit (import ./lib/packages.nix { pkgs = final; }) node-bin pnpm-bin;
        # A flake's `self` is an attrset too; its `outPath` marks it as the project.
        node-toolchain.fromProject =
          arg:
          self.lib.mkToolchain (
            { pkgs = final; } // (if builtins.isAttrs arg && !(arg ? outPath) then arg else { src = arg; })
          );
      };
    };
}
