{ config, pkgs, ... }:
{
  services.forgejo = {
    enable = true;

    database.type = "sqlite3";

    settings = {
      server = {
        DOMAIN = "git.private.cskjolden.com";
        ROOT_URL = "https://git.private.cskjolden.com/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3000;

        # Run built-in SSH server on port 2222 (keeps port 22 clean for host admin SSH)
        SSH_PORT = 2222;
        START_SSH_SERVER = true;
      };

      # Enable Forgejo Actions (CI/CD)
      actions = {
        ENABLED = true;
      };

      # Security & registration
      service = {
        DISABLE_REGISTRATION = true;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        ENABLE_NOTIFY_MAIL = false;
      };

      ui = {
        DEFAULT_THEME = "forgejo-dark";
      };
    };
  };

  # Idempotently register Authelia OAuth2 source in Forgejo on startup
  systemd.services.forgejo-authelia-oauth = {
    description = "Configure Forgejo Authelia OAuth2 source";
    wantedBy = [ "forgejo.service" ];
    after = [ "forgejo.service" "authelia-main.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "forgejo";
      Group = "forgejo";
      RemainAfterExit = true;
    };
    script = ''
      # Wait briefly for Forgejo web service to be responsive
      for i in $(seq 1 15); do
        if ${pkgs.curl}/bin/curl -s http://127.0.0.1:3000/ > /dev/null; then
          break
        fi
        sleep 1
      done

      # Check if Authelia auth source already exists
      if ! ${config.services.forgejo.package}/bin/forgejo admin auth list | grep -q "Authelia"; then
        if [ -f /var/lib/authelia-main/secrets/forgejo_secret ]; then
          SECRET=$(cat /var/lib/authelia-main/secrets/forgejo_secret)
          ${config.services.forgejo.package}/bin/forgejo admin auth add-oauth \
            --name Authelia \
            --provider openidConnect \
            --key forgejo \
            --secret "$SECRET" \
            --auto-discover-url https://auth.private.cskjolden.com/.well-known/openid-configuration
        fi
      fi
    '';
  };

  # Open Git SSH port
  networking.firewall.allowedTCPPorts = [ 2222 ];

  # Forgejo Actions Runner (CI/CD workflows executed via Podman)
  services.forgejo-runner = {
    instances."vps" = {
      enable = true;
      secrets = {
        server.connections.default.token_url = "/var/lib/forgejo-runner/token";
      };
      settings = {
        server.connections.default = {
          url = "http://127.0.0.1:3000";
          uuid = "91cea758-08e6-4203-9565-3a19b35180ce";
          labels = [
            "ubuntu-latest:docker://node:20-bookworm"
            "ubuntu-22.04:docker://node:20-bookworm"
            "docker:docker://node:20-bookworm"
            "native:host"
          ];
        };
        container = {
          docker_host = "unix:///run/podman/podman.sock";
        };
      };
    };
  };
}
