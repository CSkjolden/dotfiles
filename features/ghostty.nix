{ ... }:
{
  homebrew.casks = [
    "ghostty" # Terminal emulator
  ];

  home-manager.sharedModules = [
    {
      programs.ghostty = {
        enable = true;
        package = null;

        settings = {
          macos-option-as-alt = true;
          bell-features = "no-system,no-audio,border";
          background-opacity = 0.75;
          background-blur = 10;
          auto-update = "off";
          notify-on-command-finish = "unfocused";
          scrollback-limit = 50000000;
          mouse-hide-while-typing = true;
          cursor-style-blink = false;
          macos-titlebar-style = "tabs";
          window-padding-x = 8;
          window-padding-y = 6;
          window-padding-balance = true;
        };
      };
    }
  ];
}
