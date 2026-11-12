{ ... }:
{
  homebrew.brews = [
    "opencode" # AI coding agent for the terminal
  ];

  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      xdg.configFile."opencode/opencode.json".source = (pkgs.formats.json { }).generate "opencode.json" {
        "$schema" = "https://opencode.ai/config.json";
        provider = {
          omlx = {
            npm = "@ai-sdk/openai-compatible";
            name = "oMLX (Mac Studio)";
            options.baseURL = "http://skjolds-mac-studio:8000/v1";
          };
        };
      };
    })
  ];
}
