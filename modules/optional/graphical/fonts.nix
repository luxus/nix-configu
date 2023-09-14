{
  lib,
  pkgs,
  ...
}: {
  fonts = {
    fontconfig = {
      # Always prefer emojis even if the original font would provide a glyph
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
        <fontconfig>
            <alias binding="weak">
                <family>monospace</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
            <alias binding="weak">
                <family>sans-serif</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
            <alias binding="weak">
                <family>serif</family>
                <prefer>
                    <family>emoji</family>
                </prefer>
            </alias>
        </fontconfig>
      '';
      defaultFonts = {
        sansSerif = lib.mkBefore ["Segoe UI"];
        monospace = ["FiraCode Nerd Font"];
        emoji = ["Segoe UI Emoji" "Noto Fonts Emoji"];
      };
    };

    packages = with pkgs; [
      (nerdfonts.override {fonts = ["FiraCode"];})
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      noto-fonts-extra
      segoe-ui-ttf
    ];
  };
}
