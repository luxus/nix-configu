{
  self,
  pre-commit-hooks,
  ...
}: system:
with self.pkgs.${system}; {
  pre-commit-check =
    pre-commit-hooks.lib.${system}.run
    {
      src = lib.cleanSource ../.;
      hooks = {
        actionlint.enable = true;
        luacheck.enable = true;
        alejandra.enable = true;
        statix.enable = true;
        stylua.enable = true;
      };
    };
}
