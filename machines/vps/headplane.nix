{ pkgs, ... }:
{
  services.headplane = {
    enable = true;

    settings = {
      server = {
        host = "127.0.0.1";
        port = 3001;
        base_url = "https://vpn.private.cskjolden.com";
        cookie_secret_path = "/var/lib/headplane/cookie_secret";
      };

      headscale = {
        url = "http://127.0.0.1:8080";
        public_url = "https://headscale.private.cskjolden.com";
        api_key_path = "/var/lib/headplane/api_key";
        config_path = "/etc/headscale/config.yaml";
        config_strict = false;
      };

      oidc = {
        enabled = true;
        issuer = "https://auth.private.cskjolden.com";
        client_id = "headplane";
        client_secret_path = "/var/lib/headplane/oidc_secret";
      };
    };
  };

  # Automatically bootstrap Headplane secrets and Headscale API key on startup
  systemd.services.headplane-bootstrap = {
    description = "Bootstrap Headplane secrets and API key";
    wantedBy = [ "headplane.service" ];
    before = [ "headplane.service" ];
    after = [ "headscale.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "headscale";
      Group = "headscale";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/headplane
      chmod 700 /var/lib/headplane

      if [ ! -s /var/lib/headplane/cookie_secret ]; then
        head -c 16 /dev/urandom | od -A n -v -t x1 | tr -d ' \n' > /var/lib/headplane/cookie_secret
        chmod 600 /var/lib/headplane/cookie_secret
      fi

      if [ ! -s /var/lib/headplane/api_key ]; then
        ${pkgs.headscale}/bin/headscale apikeys create --expiration 9999d > /var/lib/headplane/api_key
        chmod 600 /var/lib/headplane/api_key
      fi

      if [ -f /var/lib/authelia-main/secrets/headplane_secret ]; then
        cp /var/lib/authelia-main/secrets/headplane_secret /var/lib/headplane/oidc_secret
        chmod 600 /var/lib/headplane/oidc_secret
      fi
    '';
  };
}
