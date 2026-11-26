{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.headscale ];

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;

    settings = {
      server_url = "https://headscale.private.cskjolden.com";

      dns = {
        base_domain = "net.private.cskjolden.com";
        magic_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };

      # IP prefixes allocated to your Tailnet devices
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };

      # Allow nodes to route traffic (exit nodes, subnet routers)
      derp = {
        server = {
          enabled = true;
          region_id = 999;
          region_code = "vps";
          region_name = "VPS DERP";
          stun_listen_addr = "0.0.0.0:3478";
        };
        urls = [ ];
      };

      # ACL Policy: Groups, Permissions, and Tailscale SSH
      policy = {
        mode = "file";
        path = pkgs.writeText "headscale-acl.hujson" (builtins.toJSON {
          groups = {
            "group:admin" = [
              "skjold@*"
              "skjold@private.cskjolden.com"
            ];
          };
          tagOwners = {
            "tag:server" = [ "group:admin" ];
            "tag:exit" = [ "group:admin" ];
            "tag:ai" = [ "group:admin" ];
            "tag:agent" = [ "group:admin" ];
          };
          acls = [
            {
              action = "accept";
              src = [ "*" ];
              dst = [ "*:*" ];
            }
          ];
          ssh = [
            {
              action = "accept";
              src = [
                "autogroup:member"
                "group:admin"
              ];
              dst = [
                "autogroup:self"
                "tag:server"
                "tag:ai"
              ];
              users = [
                "root"
                "skjold"
                "autogroup:nonroot"
              ];
            }
          ];
          autoApprovers = {
            routes = {
              "0.0.0.0/0" = [ "group:admin" ];
              "::/0" = [ "group:admin" ];
            };
            exitNode = [ "group:admin" ];
          };
        });
      };
    };
  };

  # Kernel IP forwarding for Tailscale exit nodes & subnet routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Open STUN (3478) and Tailscale WireGuard (41641) UDP ports for direct peer-to-peer connections
  networking.firewall.allowedUDPPorts = [ 3478 41641 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Tailscale client on the VPS (enables the VPS to act as an Exit Node on its own Headscale network)
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  # Automatically enroll the VPS into its own Headscale network as an exit node
  systemd.services.tailscale-autoconnect = {
    description = "Enroll VPS into local Headscale network as Exit Node";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "headscale.service"
      "caddy.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for i in $(seq 1 20); do
        if ${pkgs.curl}/bin/curl -s http://127.0.0.1:8080/health | grep -q "pass"; then
          break
        fi
        sleep 1
      done

      STATUS=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // empty' || true)
      if [ "$STATUS" != "Running" ]; then
        USER_ID=$(${pkgs.headscale}/bin/headscale users list --output json | ${pkgs.jq}/bin/jq -r '.[0].id // 1')
        KEY=$(${pkgs.headscale}/bin/headscale preauthkeys create -u "$USER_ID" -e 1h)
        ${pkgs.tailscale}/bin/tailscale up \
          --login-server https://headscale.private.cskjolden.com \
          --authkey "$KEY" \
          --advertise-exit-node \
          --hostname vps \
          --accept-routes \
          --reset

        VPS_NODE_ID=$(${pkgs.headscale}/bin/headscale nodes list --output json | ${pkgs.jq}/bin/jq -r 'map(select(.given_name == "vps"))[0].id // empty')
        if [ -n "$VPS_NODE_ID" ]; then
          ${pkgs.headscale}/bin/headscale nodes approve-routes --identifier "$VPS_NODE_ID" --routes "0.0.0.0/0,::/0" || true
        fi
      fi
    '';
  };
}
