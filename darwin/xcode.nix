{ ... }:
let
  # Accept xcode license
  xcodeSetup = ''
    if [ -d /Applications/Xcode.app ]; then
      xcode-select -s /Applications/Xcode.app/Contents/Developer
      xcodebuild -license accept
      xcodebuild -runFirstLaunch
    fi
  '';
in
{
  system.activationScripts.extraActivation.text = xcodeSetup;
  system.activationScripts.postActivation.text = xcodeSetup;

  homebrew.masApps.Xcode = 497799835;
}
