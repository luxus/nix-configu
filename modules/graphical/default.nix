{pkgs, ...}: {
  imports = [
    ./fonts.nix
  ];

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = with pkgs; [xdg-desktop-portal-gtk];
  };
}
