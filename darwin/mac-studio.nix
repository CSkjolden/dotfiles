{ pkgs, ... }:
{
  # Headless Mac Studio server configuration and kernel optimizations

  # Disable Touch ID for sudo to prevent PAM authorization hangs during SSH sessions
  security.pam.services.sudo_local.touchIdAuth = false;

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
          # Allocate ~88% of unified memory to single Metal process allocations (prevents premature OOM)
          wired_limit=$(( mem_bytes * 88 / 100 ))
          /usr/sbin/sysctl -w iogpu.wired_mem_limit="$wired_limit"
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

    # 3. VRAM Allocation Ceiling: Raise Metal allocation limit immediately without requiring reboot
    mem_bytes=$(/usr/sbin/sysctl -n hw.memsize)
    wired_limit=$(( mem_bytes * 88 / 100 ))
    /usr/sbin/sysctl -w iogpu.wired_mem_limit="$wired_limit" || true
  '';
}
