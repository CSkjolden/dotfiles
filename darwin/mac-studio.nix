{ config, pkgs, ... }:
let
  user = config.system.primaryUser;

  # Consumer / GUI / telemetry User LaunchAgents that load even in Background (SSH) sessions
  disabledUserAgents = [
    # Apple Intelligence & Proactive / CoreDuet / Biome
    "com.apple.intelligenceplatformd"
    "com.apple.intelligenceflowd"
    "com.apple.intelligencecontextd"
    "com.apple.intelligencetasksd"
    "com.apple.privatecloudcomputed"
    "com.apple.callintelligenced"
    "com.apple.duetexpertd"
    "com.apple.knowledge-agent"
    "com.apple.knowledgeconstructiond"
    "com.apple.BiomeAgent"
    "com.apple.suggestd"
    "com.apple.triald"
    "com.apple.parsec-fbf"

    # Siri, Voice & Dictation
    "com.apple.Siri.agent"
    "com.apple.SiriTTSTrainingAgent"
    "com.apple.sirittsd"
    "com.apple.siriactionsd"
    "com.apple.siriinferenced"
    "com.apple.siriknowledged"
    "com.apple.assistantd"
    "com.apple.assistant_service"
    "com.apple.assistant_cdmd"

    # Media, Photos & Vision Analysis
    "com.apple.mediaanalysisd"
    "com.apple.photoanalysisd"
    "com.apple.photolibraryd"
    "com.apple.cloudphotod"
    "com.apple.mediastream.mstreamd"
    "com.apple.amp.mediasharingd"
    "com.apple.itunescloudd"

    # Spotlight User Agents
    "com.apple.Spotlight"
    "com.apple.corespotlightd"
    "com.apple.corespotlightservice"
    "com.apple.managedcorespotlightd"
    "com.apple.spotlightknowledged"
    "com.apple.spotlightknowledged.importer"
    "com.apple.spotlightknowledged.updater"
    "com.apple.searchtoold"
    "com.apple.mdworker.mail"

    # Widgets, Weather, News, HomeKit & Game Center
    "com.apple.chronod"
    "com.apple.weatherd"
    "com.apple.newsd"
    "com.apple.homed"
    "com.apple.homeenergyd"
    "com.apple.homeeventsd"
    "com.apple.gamed"
    "com.apple.gamesaved"
    "com.apple.GameController.gamecontrolleragentd"
    "com.apple.GamePolicyAgent"

    # Safari & WebKit Background Services
    "com.apple.Safari.History"
    "com.apple.Safari.PasswordBreachAgent"
    "com.apple.Safari.SafeBrowsing.Service"
    "com.apple.SafariBookmarksSyncAgent"
    "com.apple.SafariHistoryServiceAgent"
    "com.apple.SafariLaunchAgent"
    "com.apple.SafariNotificationAgent"
    "com.apple.webkit.webpushd"

    # Analytics & Ad Tracking
    "com.apple.analyticsagent"
    "com.apple.geoanalyticsd"
    "com.apple.inputanalyticsd"
    "com.apple.ap.adprivacyd"
    "com.apple.ap.promotedcontentd"
  ];

  # System LaunchDaemons unnecessary on a dedicated headless inference server
  disabledSystemDaemons = [
    "com.apple.analyticsd"
    "com.apple.audioanalyticsd"
    "com.apple.biomed"
    "com.apple.gamecontrollerd"
    "com.apple.modelmanagerd"
    "com.apple.siriinferenced"
    "com.apple.suggestd"
    "com.apple.triald.system"
    "com.apple.spindump"
    "com.apple.tailspind"
  ];

  # Process names of bloat agents to terminate if already running
  bloatProcessNames = [
    "mediaanalysisd"
    "photoanalysisd"
    "photolibraryd"
    "cloudphotod"
    "sirittsd"
    "siriactionsd"
    "siriinferenced"
    "siriknowledged"
    "Siri"
    "assistantd"
    "assistant_service"
    "assistant_cdmd"
    "intelligenceplatformd"
    "IntelligencePlatformComputeService"
    "duetexpertd"
    "knowledge-agent"
    "knowledgeconstructiond"
    "BiomeAgent"
    "biomed"
    "suggestd"
    "triald"
    "corespotlightd"
    "spotlightknowledged"
    "Spotlight"
    "chronod"
    "WeatherWidget"
    "PhotosReliveWidget"
    "weatherd"
    "newsd"
    "homed"
    "gamed"
    "com.apple.Safari.SafeBrowsing.Service"
    "analyticsd"
  ];
in
{
  # Headless Mac Studio server configuration and kernel optimizations

  # Pure ARM64 server: skip Intel Homebrew prefix and Rosetta 2 translation daemon (oahd)
  nix-homebrew.enableRosetta = false;

  # Disable Touch ID for sudo to prevent PAM authorization hangs during SSH sessions
  security.pam.services.sudo_local.touchIdAuth = false;

  # Headless system defaults to prevent popups, animations, and background memory bloat
  system.defaults = {
    # Disable quarantine dialogs for downloaded tools and models
    LaunchServices.LSQuarantine = false;

    # Prevent automatic OS background downloads into RAM/disk cache
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

    # Minimize Dock & WindowManager footprint if a GUI session is ever opened via VNC
    dock = {
      autohide = true;
      persistent-apps = [ ];
      show-recents = false;
      launchanim = false;
      expose-animation-duration = 0.0;
    };

    WindowManager = {
      GloballyEnabled = false;
      StandardHideWidgets = true;
      StageManagerHideWidgets = true;
      HideDesktop = true;
    };

    NSGlobalDomain = {
      # Disable window and UI animations to minimize WindowServer memory allocations
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      # Disable automatic spellcheck/text-completion daemons (AppleSpell)
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    CustomUserPreferences = {
      NSGlobalDomain = {
        # Disable App Nap so background compute daemons are never throttled
        NSAppSleepDisabled = true;
        NSAutomaticTextCompletionEnabled = false;
      };

      # Never pop up "Do you want to use this disk with Time Machine?" when external NVMe is plugged in
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;

      # Disable Siri, Dictation, and Apple Intelligence daemons
      "com.apple.Siri" = {
        StatusMenuVisible = false;
        UserHasDeclinedEnable = true;
      };
      "com.apple.assistant.support" = {
        "Assistant Enabled" = false;
        "Dictation Enabled" = false;
      };
      "com.apple.CloudSubscriptionFeatures.optIn"."545129924" = false;

      # Avoid creating .DS_Store files on network or USB/Thunderbolt AI storage volumes
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };

      # Never reopen apps/windows after reboot
      "com.apple.loginwindow".TALLogoutSavesState = false;
    };

    CustomSystemPreferences = {
      # Suppress GUI crash reporter dialogs on headless server
      "com.apple.CrashReporter".DialogType = "none";
      # Disable Apple telemetry and diagnostic reporting
      "com.apple.SubmitDiagInfo".AutoSubmit = false;
      # Disable automatic login so headless boots stay at lightweight loginwindow (~1.5GB RAM saved)
      "com.apple.loginwindow".autoLoginUser = "";
      # Automatically mount external APFS/USB storage (e.g. /Volumes/StudioStorage) at headless boot without requiring a logged-in GUI user
      "/Library/Preferences/SystemConfiguration/autodiskmount".AutomountDisksWithoutUserLogin = true;
    };
  };

  # Convenient authenticated reboot & memory diagnostic helpers
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

    (pkgs.writeShellScriptBin "studio-mem" ''
      set -euo pipefail
      if [ "''${1:-}" = "--kill-gui" ]; then
        echo "Logging out idle local GUI desktop session (Aqua) to free ~1.5 GB unified memory..."
        echo "(SSH and launchd system daemons like tailscaled and omlx will stay online)"
        sudo /bin/launchctl bootout gui/"$(id -u ${user})" 2>/dev/null || true
        sleep 2
        sudo /usr/sbin/diskutil mount StudioStorage >/dev/null 2>&1 || true
      fi

      echo "=== Mac Studio Unified Memory Report ==="
      total_bytes=$(/usr/sbin/sysctl -n hw.memsize)
      wired_limit_mb=$(/usr/sbin/sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
      printf "Total Physical RAM:     %.2f GB (%d MB)\n" "$(echo "$total_bytes / 1073741824" | bc -l)" "$(( total_bytes / 1048576 ))"
      printf "Metal Wired Cap:        %.2f GB (%d MB)\n" "$(echo "$wired_limit_mb / 1024" | bc -l)" "$wired_limit_mb"
      echo ""
      /usr/bin/vm_stat | awk '
        NR==1 { split($0, a, " "); page_size=16384 }
        /Pages free/ { free=$3*16384/1073741824 }
        /Pages active/ { active=$3*16384/1073741824 }
        /Pages inactive/ { inactive=$3*16384/1073741824 }
        /Pages wired down/ { wired=$4*16384/1073741824 }
        /Pages occupied by compressor/ { comp=$5*16384/1073741824 }
        /File-backed pages/ { file=$3*16384/1073741824 }
        END {
          printf "Wired Memory:           %.2f GB\n", wired
          printf "Active Memory:          %.2f GB\n", active
          printf "Compressed Memory:      %.2f GB\n", comp
          printf "Inactive / File Cache:  %.2f GB (reclaimable by Metal/oMLX)\n", inactive
          printf "Free Memory:            %.2f GB\n", free
        }
      '
      echo ""
      non_omlx_mb=$(ps -axo rss,comm | awk '!/omlx/ {sum+=$1} END {printf "%.0f", sum/1024}')
      echo "Total non-oMLX RSS:     ''${non_omlx_mb} MB"
      if pgrep -q -u "${user}" Finder; then
        echo ""
        echo "NOTE: A local GUI desktop session (Finder/Dock/WindowServer) is currently logged in."
        echo "      Run 'studio-mem --kill-gui' (or 'studio-reboot') to close the GUI session and reclaim ~1.5 GB RAM."
      fi
      echo ""
      echo "--- Top 10 Processes by RSS ---"
      ps -axo rss,user,comm | awk 'NR>1 {rss[$2":"$3]+=$1} END {for (k in rss) printf "%8.1f MB  %s\n", rss[k]/1024, k}' | sort -rn | head -n 10
    '')
  ];

  # Ensure high memory allocation ceiling (95% of RAM, matching oMLX's safety ceiling) persists across reboots
  launchd.daemons.iogpu-wired-mem-limit = {
    serviceConfig = {
      Label = "iogpu.wired-mem-limit";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          mem_bytes=$(/usr/sbin/sysctl -n hw.memsize)
          # 95% of physical RAM floored to whole MiB (matches oMLX _wired_limit_suggestion_bytes)
          wired_limit_mb=$(( (mem_bytes - (mem_bytes / 20)) / 1048576 ))

          if /usr/sbin/sysctl iogpu.wired_limit_mb >/dev/null 2>&1; then
            /usr/sbin/sysctl -w iogpu.wired_limit_mb="$wired_limit_mb" || true
          elif /usr/sbin/sysctl debug.iogpu.wired_limit >/dev/null 2>&1; then
            /usr/sbin/sysctl -w debug.iogpu.wired_limit="$wired_limit_mb" || true
          elif /usr/sbin/sysctl iogpu.wired_mem_limit >/dev/null 2>&1; then
            /usr/sbin/sysctl -w iogpu.wired_mem_limit="$(( mem_bytes * 95 / 100 ))" || true
          fi
        ''
      ];
      RunAtLoad = true;
    };
  };

  system.activationScripts.postActivation.text = ''
    # 1. Sleep Suppression: Never sleep idle, disks, or display; keep Wake-on-LAN and auto-power-recovery active
    /usr/bin/pmset -a sleep 0 disablesleep 1 disksleep 0 displaysleep 0 womp 1 autorestart 1 powernap 0 proximitywake 0 || true

    # 2. Remote Access: Ensure SSH daemon is enabled
    /usr/sbin/systemsetup -setremotelogin on || true

    # 3. Developer Tools: Authorize debuggers/profilers and add user to _developer group without GUI prompts
    /usr/sbin/DevToolsSecurity -enable || true
    /usr/sbin/dseditgroup -o edit -a "${user}" -t user _developer 2>/dev/null || true

    # 4. VRAM Allocation Ceiling: Raise Metal allocation limit to 95% of RAM immediately
    mem_bytes=$(/usr/sbin/sysctl -n hw.memsize)
    wired_limit_mb=$(( (mem_bytes - (mem_bytes / 20)) / 1048576 ))

    if /usr/sbin/sysctl iogpu.wired_limit_mb >/dev/null 2>&1; then
      /usr/sbin/sysctl -w iogpu.wired_limit_mb="$wired_limit_mb" || true
    elif /usr/sbin/sysctl debug.iogpu.wired_limit >/dev/null 2>&1; then
      /usr/sbin/sysctl -w debug.iogpu.wired_limit="$wired_limit_mb" || true
    elif /usr/sbin/sysctl iogpu.wired_mem_limit >/dev/null 2>&1; then
      /usr/sbin/sysctl -w iogpu.wired_mem_limit="$(( mem_bytes * 95 / 100 ))" || true
    fi

    # 5. Headless Memory Sweep: Disable background agents & daemons that waste unified memory
    uid=$(id -u "${user}")
    for agent in ${builtins.concatStringsSep " " disabledUserAgents}; do
      /bin/launchctl disable "user/$uid/$agent" 2>/dev/null || true
      /bin/launchctl disable "gui/$uid/$agent" 2>/dev/null || true
    done

    for daemon in ${builtins.concatStringsSep " " disabledSystemDaemons}; do
      /bin/launchctl disable "system/$daemon" 2>/dev/null || true
    done

    # Terminate any currently running instances of disabled bloat processes
    for proc in ${builtins.concatStringsSep " " bloatProcessNames}; do
      for pid in $(/usr/bin/pgrep -x "$proc" 2>/dev/null || true); do
        kill -9 "$pid" 2>/dev/null || true
      done
    done

    # Spotlight: Disable metadata indexing across all volumes on headless server (saves ~1-2GB RAM)
    touch /Volumes/StudioStorage/.metadata_never_index 2>/dev/null || true
    /usr/bin/mdutil -a -i off 2>/dev/null || true

    # Disable local APFS Time Machine snapshots that pin dirty memory pages
    /usr/bin/tmutil disablelocal 2>/dev/null || true

    # Disable background AirPlay receiver daemon
    /usr/bin/defaults write /Library/Preferences/com.apple.airplay.plist "AirPlayReceiverEnabled" -bool false 2>/dev/null || true

    # Turn off automatic background software update downloads into RAM/disk cache
    /usr/sbin/softwareupdate --schedule off 2>/dev/null || true
  '';
}
