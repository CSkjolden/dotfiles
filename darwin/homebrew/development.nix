{ ... }:
{
  homebrew = {
    brews = [
      "container" # Create and run Linux containers using lightweight virtual machines
    ];

    casks = [
      "github" # Desktop client for GitHub repositories
      "jetbrains-toolbox" # JetBrains tools manager
    ];
  };
}
