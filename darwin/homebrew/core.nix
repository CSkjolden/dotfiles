{ ... }:
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = true;
      extraFlags = [ "--verbose" ];
    };

    casks = [
      "visual-studio-code" # Visual Studio Code
      "ghostty" # Terminal emulator
      "vorssaint" # Menu bar toolkit with keep-awake, system monitor and volume mixer
      "flashspace" # Fast virtual workspace manager for macOS
      "mos" # Smooth scrolling on mouse
      "displaylink" # Drivers to allow display link monitors
    ];
  };
}
