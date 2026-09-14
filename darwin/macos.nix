{ config, lib, ... }:

{
  system.defaults = {
    dock = {
      persistent-apps = [ ];
      autohide = true;
      tilesize = 48;
      enable-spring-load-actions-on-all-items = true;
      show-recents = false;
      autohide-time-modifier = 0.1;
      autohide-delay = 0.05;
      scroll-to-open = true;
    };

    screencapture = {
      location = "/Users/${config.system.primaryUser}/Screenshots";
      type = "png";
    };

    finder = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
      _FXSortFoldersFirst = true;
      FXEnableExtensionChangeWarning = false;
      ShowStatusBar = true;
      ShowExternalHardDrivesOnDesktop = false;
      ShowRemovableMediaOnDesktop = false;
    };

    trackpad = {
      Clicking = true;
      FirstClickThreshold = 0;
      DragLock = false;
    };

    ".GlobalPreferences"."com.apple.mouse.scaling" = 1.0;

    hitoolbox.AppleFnUsageType = "Do Nothing";

    ActivityMonitor.IconType = 5;

    LaunchServices.LSQuarantine = true;

    menuExtraClock = {
      ShowAMPM = true;
      ShowDate = 0;
      ShowDayOfWeek = true;
    };

    WindowManager = {
      GloballyEnabled = false;
      AutoHide = false;
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
      HideDesktop = true;
      StandardHideWidgets = true;
      StageManagerHideWidgets = true;
      AppWindowGroupingBehavior = true;
    };

    magicmouse.MouseButtonMode = "OneButton";

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      NSTableViewDefaultSizeMode = 1;
      ApplePressAndHoldEnabled = false;
      "com.apple.keyboard.fnState" = false;
      AppleKeyboardUIMode = 2;
      NSAutomaticPeriodSubstitutionEnabled = false;
      AppleInterfaceStyle = "Dark";
      "com.apple.trackpad.forceClick" = true;
      "com.apple.springing.enabled" = true;
      "com.apple.springing.delay" = 0.5;
    };

    # Settings without a typed nix-darwin option; written to the plists directly.
    CustomUserPreferences = {
      "com.apple.appleseed.FeedbackAssistant".Autogather = false;
      "com.apple.TextEdit".SmartQuotes = false;
      "com.apple.ActivityMonitor".UpdatePeriod = 2;

      "com.apple.AppleMultitouchMouse" = {
        MouseButtonDivision = 55;
        MouseOneFingerDoubleTapGesture = 0;
        MouseTwoFingerDoubleTapGesture = 3;
        MouseTwoFingerHorizSwipeGesture = 2;
        MouseHorizontalScroll = true;
        MouseVerticalScroll = true;
        MouseMomentumScroll = true;
      };

      NSGlobalDomain = {
        "com.apple.mouse.linear" = false;
        NSQuitAlwaysKeepsWindows = true;
        AppleActionOnDoubleClick = "Fill";
        AppleMiniaturizeOnDoubleClick = false;
        AppleLanguages = [ "en-US" "da-DK" ];
        AppleLocale = "en_US@rg=dkzzzz";
        KB_DoubleQuoteOption = "\\U201cabc\\U201d";
        KB_SingleQuoteOption = "\\U2018abc\\U2019";
        "com.apple.sound.beep.flash" = false;
      };

      "com.apple.HIToolbox" = {
        AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.Danish";
        AppleSelectedInputSources = [
          { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 9; "KeyboardLayout Name" = "Danish"; }
          { "Bundle ID" = "com.apple.PressAndHold"; InputSourceKind = "Non Keyboard Input Method"; }
        ];
        AppleEnabledInputSources = [
          { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 9; "KeyboardLayout Name" = "Danish"; }
          { "Bundle ID" = "com.apple.CharacterPaletteIM"; InputSourceKind = "Non Keyboard Input Method"; }
          { "Bundle ID" = "com.apple.PressAndHold"; InputSourceKind = "Non Keyboard Input Method"; }
        ];
      };
    };

    # Login screen clock font is a system (not per-user) preference.
    CustomSystemPreferences."com.apple.loginwindow" = {
      ClockFontIdentifier = "rail";
      ClockFontWeight = 400;
    };
  };

  # system.defaults.screencapture.location doesn't create the folder itself.
  system.activationScripts.postActivation.text = ''
    mkdir -p "/Users/${config.system.primaryUser}/Screenshots"
  '';
}
