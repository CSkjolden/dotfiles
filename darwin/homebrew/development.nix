{ ... }:
{
  homebrew = {
    brews = [
      "podman" # Tool for managing OCI containers and pods
      "container" # Create and run Linux containers using lightweight virtual machines
    ];

    casks = [
      "podman-desktop" # Browse, manage, inspect containers and images
      "github" # Desktop client for GitHub repositories
      "jetbrains-toolbox" # JetBrains tools manager
    ];
  };
}
