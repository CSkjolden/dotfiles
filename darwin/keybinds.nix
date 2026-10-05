{ lib, ... }:
let
  ctrl = 262144;
  shift = 131072;
  opt = 524288;
  cmd = 1048576;
  fn = 8388608; # also set on arrow and F-keys
  noChar = 65535;

  # sc id enabled character keycode modifiers
  sc = id: enabled: char: code: mods: { inherit id enabled; params = [ char code mods ]; };

  # Flip a shortcut's boolean to turn it on or off. Applied as the whole dict,
  # so a shortcut missing here reverts to the macOS default.
  shortcuts = {
    # App switcher (Tab keycode is 48)
    appSwitcher = sc 1 false noChar 48 (cmd);
    appSwitcherReverse = sc 2 false noChar 48 (cmd + shift);

    # Keyboard navigation
    focusMenuBar = sc 7 true noChar 120 ctrl;
    focusDock = sc 8 true noChar 99 ctrl;
    focusActiveWindow = sc 9 true noChar 118 ctrl;
    focusToolbar = sc 10 true noChar 96 ctrl;
    focusFloatingWindow = sc 11 true noChar 97 ctrl;
    toggleFullKeyboardAccess = sc 12 true noChar 122 ctrl;
    changeTabFocus = sc 13 true noChar 98 ctrl;
    focusStatusMenus = sc 57 true noChar 100 ctrl;
    focusNextWindowInApp = sc 27 false 96 50 cmd;
    showContextMenu = sc 159 true noChar 36 ctrl;
    toggleTrackpadHandwriting = sc 156 true noChar 49 (ctrl + shift);

    # Accessibility zoom, color and contrast
    zoomToggle = sc 15 false 56 28 (cmd + opt);
    zoomIn = sc 17 false 61 24 (cmd + opt);
    zoomOut = sc 19 false 45 27 (cmd + opt);
    invertColors = sc 21 false 56 28 (ctrl + opt + cmd);
    zoomSmoothing = sc 23 false 92 42 (cmd + opt);
    increaseContrast = sc 25 false 46 47 (ctrl + opt + cmd);
    decreaseContrast = sc 26 false 44 43 (ctrl + opt + cmd);
    voiceOver = sc 59 true noChar 96 cmd;
    accessibilityControls = sc 162 true noChar 96 (cmd + opt);

    # Screenshots
    screenshotScreen = sc 28 true 51 20 (shift + cmd);
    screenshotScreenToClipboard = sc 29 true 51 20 (ctrl + shift + cmd);
    screenshotArea = sc 30 true 52 21 (shift + cmd);
    screenshotAreaToClipboard = sc 31 true 52 21 (ctrl + shift + cmd);
    screenshotOptions = sc 184 true 53 23 (shift + cmd);

    # Mission Control, App Exposé, Show Desktop (FlashSpace uses ctrl+arrows)
    missionControl = sc 32 false noChar 126 (ctrl + fn);
    appExpose = sc 33 false noChar 125 (ctrl + fn);
    showDesktop = sc 36 true noChar 103 0;
    toggleDockAutohide = sc 52 true 100 2 (cmd + opt);

    # Spaces
    moveSpaceLeft = sc 79 false noChar 123 (ctrl + fn);
    moveSpaceLeftSlow = sc 80 true noChar 123 (ctrl + shift + fn);
    moveSpaceRight = sc 81 false noChar 124 (ctrl + fn);
    moveSpaceRightSlow = sc 82 true noChar 124 (ctrl + shift + fn);

    # Input sources and Spotlight
    previousInputSource = sc 60 false 32 49 ctrl;
    nextInputSource = sc 61 false 32 49 (ctrl + opt);
    spotlightSearch = sc 64 false 32 49 cmd;
    spotlightFinderWindow = sc 65 false 32 49 (cmd + opt);

    # Display, notes and window management
    decreaseBrightness = sc 53 true noChar 107 0;
    increaseBrightness = sc 54 true noChar 113 0;
    quickNote = sc 190 true 113 12 fn;
    gameOverlay = sc 260 true noChar 53 cmd;
    minimize = sc 233 true 109 46 cmd;
    fill = sc 237 true 102 3 (ctrl + fn);
    center = sc 238 true 99 8 (ctrl + fn);
    returnToPreviousSize = sc 239 true 114 15 (ctrl + fn);
    tileLeftHalf = sc 240 true noChar 123 (ctrl + fn);
    tileRightHalf = sc 241 true noChar 124 (ctrl + fn);
    tileTopHalf = sc 242 true noChar 126 (ctrl + fn);
    tileBottomHalf = sc 243 true noChar 125 (ctrl + fn);
    arrangeLeftRight = sc 248 true noChar 123 (ctrl + shift + fn);
    arrangeRightLeft = sc 249 true noChar 124 (ctrl + shift + fn);
    arrangeTopBottom = sc 250 true noChar 126 (ctrl + shift + fn);
    arrangeBottomTop = sc 251 true noChar 125 (ctrl + shift + fn);
  }
  // lib.listToAttrs (lib.imap1
    (n: code: lib.nameValuePair "switchToDesktop${toString n}" (sc (117 + n) false noChar code ctrl))
    # Keycodes for the keys 1-9 and 0.
    [ 18 19 20 21 23 22 26 28 25 29 ]);

  symbolicHotKeys = lib.listToAttrs (lib.mapAttrsToList
    (_: s: lib.nameValuePair (toString s.id) {
      inherit (s) enabled;
      value = { type = "standard"; parameters = s.params; };
    })
    shortcuts);
in
{
  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = symbolicHotKeys;
}
