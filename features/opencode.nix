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
            name = "oMLX (local)";
            options.baseURL = "http://localhost:8000/v1";
          };
        };
      };
    })
  ];
}
