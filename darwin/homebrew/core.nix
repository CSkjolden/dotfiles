{ ... }:
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      extraFlags = [ "--verbose" ];
    };

    casks = [
      "visual-studio-code" # Visual Studio Code
      "vorssaint" # Menu bar toolkit with keep-awake, system monitor and volume mixer
      "mos" # Smooth scrolling on mouse
      "displaylink" # Drivers to allow display link monitors
    ];
  };
}
