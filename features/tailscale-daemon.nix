{ ... }:
{
  homebrew.brews = [
    "tailscale"
  ];

  # Run tailscaled as a native system daemon before user login
  launchd.daemons.tailscaled = {
    serviceConfig = {
      Label = "com.tailscale.tailscaled";
      ProgramArguments = [
        "/opt/homebrew/bin/tailscaled"
        "--state=/var/lib/tailscale/tailscaled.state"
        "--socket=/var/run/tailscaled.socket"
        "--port=41641"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "/var/log/tailscaled.log";
      StandardOutPath = "/var/log/tailscaled.log";
    };
  };

  system.activationScripts.postActivation.text = ''
    mkdir -p /var/lib/tailscale
    chmod 700 /var/lib/tailscale
  '';
}
