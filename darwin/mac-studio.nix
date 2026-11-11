{ config, pkgs, ... }:
{
  # Headless Mac Studio server configuration and kernel optimizations

  # Disable Touch ID for sudo to prevent PAM authorization hangs during SSH sessions
  security.pam.services.sudo_local.touchIdAuth = false;

  # Headless system defaults to prevent popups and dialogs
  system.defaults = {
    # Disable quarantine dialogs for downloaded tools and models
    LaunchServices.LSQuarantine = false;

    CustomUserPreferences = {
      # Never pop up "Do you want to use this disk with Time Machine?" when external NVMe is plugged in
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;

      # Disable Siri and Assistant daemons on headless server to save unified memory
      "com.apple.Siri".StatusMenuVisible = false;
      "com.apple.assistant.support"."Assistant Enabled" = false;
    };

    CustomSystemPreferences = {
      # Suppress GUI crash reporter dialogs on headless server
      "com.apple.CrashReporter".DialogType = "none";
    };
  };

  # Convenient authenticated reboot helper for FileVault
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "studio-reboot" ''
      set -euo pipefail
      if [ "$(/usr/bin/fdesetup isactive 2>/dev/null)" = "true" ]; then
        echo "FileVault is active. Initiating one-time authenticated restart..."
        echo "The system will automatically unlock FileVault and boot into macOS."
        sudo /usr/bin/fdesetup authrestart
      else
        echo "FileVault is inactive. Initiating normal reboot..."
        sudo /sbin/reboot
      fi
    '')
  ];

  # Ensure high memory allocation ceiling for Metal persists across system reboots
  launchd.daemons.iogpu-wired-mem-limit = {
    serviceConfig = {
      Label = "iogpu.wired-mem-limit";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          mem_bytes=$(/usr/sbin/sysctl -n hw.memsize)
          mem_mb=$(( mem_bytes / 1024 / 1024 ))
          wired_limit_mb=$(( mem_mb * 88 / 100 ))

          # Modern Apple Silicon sysctl accepts limit in MB
          if /usr/sbin/sysctl iogpu.wired_limit_mb >/dev/null 2>&1; then
            /usr/sbin/sysctl -w iogpu.wired_limit_mb="$wired_limit_mb" || true
          elif /usr/sbin/sysctl debug.iogpu.wired_limit >/dev/null 2>&1; then
            /usr/sbin/sysctl -w debug.iogpu.wired_limit="$wired_limit_mb" || true
          elif /usr/sbin/sysctl iogpu.wired_mem_limit >/dev/null 2>&1; then
            /usr/sbin/sysctl -w iogpu.wired_mem_limit="$(( mem_bytes * 88 / 100 ))" || true
          fi
        ''
      ];
      RunAtLoad = true;
    };
  };

  system.activationScripts.postActivation.text = ''
    # 1. Sleep Suppression: Never sleep idle, disks, or display; keep Wake-on-LAN and auto-power-recovery active
    /usr/bin/pmset -a sleep 0 disablesleep 1 disksleep 0 displaysleep 0 womp 1 autorestart 1 || true

    # 2. Remote Access: Ensure SSH daemon is enabled
    /usr/sbin/systemsetup -setremotelogin on || true

    # 3. Developer Tools: Authorize debuggers/profilers and add user to _developer group without GUI prompts
    /usr/sbin/DevToolsSecurity -enable || true
    /usr/sbin/dseditgroup -o edit -a "${config.system.primaryUser}" -t user _developer 2>/dev/null || true

    # 4. VRAM Allocation Ceiling: Raise Metal allocation limit immediately without requiring reboot
    mem_bytes=$(/usr/sbin/sysctl -n hw.memsize)
    mem_mb=$(( mem_bytes / 1024 / 1024 ))
    wired_limit_mb=$(( mem_mb * 88 / 100 ))

    if /usr/sbin/sysctl iogpu.wired_limit_mb >/dev/null 2>&1; then
      /usr/sbin/sysctl -w iogpu.wired_limit_mb="$wired_limit_mb" || true
    elif /usr/sbin/sysctl debug.iogpu.wired_limit >/dev/null 2>&1; then
      /usr/sbin/sysctl -w debug.iogpu.wired_limit="$wired_limit_mb" || true
    elif /usr/sbin/sysctl iogpu.wired_mem_limit >/dev/null 2>&1; then
      /usr/sbin/sysctl -w iogpu.wired_mem_limit="$(( mem_bytes * 88 / 100 ))" || true
    fi

    # 5. Headless Memory Sweep: Disable background daemons that waste unified memory
    # Spotlight: Prevent mds_stores and mdworker from indexing 30GB+ of weights and millions of KV cache blocks
    touch /Volumes/StudioStorage/.metadata_never_index 2>/dev/null || true
    /usr/bin/mdutil -i off /Volumes/StudioStorage 2>/dev/null || true

    # Disable local APFS Time Machine snapshots that pin dirty memory pages
    /usr/bin/tmutil disablelocal 2>/dev/null || true

    # Disable background AirPlay receiver daemon
    /usr/bin/defaults write /Library/Preferences/com.apple.airplay.plist "AirPlayReceiverEnabled" -bool false 2>/dev/null || true

    # Purge inactive disk cache pages
    /usr/sbin/purge 2>/dev/null || true
  '';
}
