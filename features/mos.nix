{ config, ... }:
let
  user = config.system.primaryUser;
in
{
  homebrew.casks = [
    "mos" # Smooth scrolling on mouse
  ];

  system.defaults.CustomUserPreferences."com.caldis.Mos" = {
    smooth = true;
    smoothVertical = true;
    smoothHorizontal = true;
    smoothSimTrackpad = false;
    reverse = false;
    reverseVertical = true;
    reverseHorizontal = true;
    step = 40.0;
    speed = 2.4;
    duration = 4.0;
    deadZone = 1.0;
    allowlist = false;
    hideStatusItem = false;
    updateCheckOnAppStart = false;
    updateIncludingBetaVersion = false;
  };

  # Mos reads this key as Data, which CustomUserPreferences can't express: {"code":58,"type":"keyboard"}
  system.activationScripts.postActivation.text = ''
    /usr/bin/sudo -u ${user} /usr/bin/defaults write com.caldis.Mos dash -data 7b22636f6465223a35382c2274797065223a226b6579626f617264227d || true
  '';
}
