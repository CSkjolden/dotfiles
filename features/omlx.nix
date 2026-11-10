{ ... }:
{
  homebrew.taps = [
    {
      name = "jundot/omlx";
      clone_target = "https://github.com/jundot/omlx";
      trusted = true;
    }
  ];

  homebrew.brews = [
    "jundot/omlx/omlx" # Local LLM inference server for Apple Silicon
  ];
}
