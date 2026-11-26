{ lib, pkgs, ... }:
let
  secretsDir = "/var/lib/authelia-main/secrets";
in
{
  environment.systemPackages = [ pkgs.authelia ];

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      manual = true;
      oidcHmacSecretFile = "${secretsDir}/oidc_hmac";
      oidcIssuerPrivateKeyFile = "${secretsDir}/oidc_issuer.pem";
    };

    settings = {
      theme = "dark";
      server.address = "tcp://127.0.0.1:9091";
      log.level = "info";

      identity_providers.oidc = {
        cors = {
          endpoints = [ "authorization" "token" "revocation" "introspection" "userinfo" ];
          allowed_origins_from_client_redirect_uris = true;
        };
        clients = [
          {
            client_id = "forgejo";
            client_name = "Forgejo";
            client_secret = "{{ secret \"${secretsDir}/forgejo_secret_hash\" }}";
            public = false;
            authorization_policy = "two_factor";
            redirect_uris = [
              "https://git.private.cskjolden.com/user/oauth2/Authelia/callback"
              "https://git.private.cskjolden.com/user/oauth2/authelia/callback"
            ];
            scopes = [ "openid" "profile" "email" "groups" ];
            response_types = [ "code" ];
            grant_types = [ "authorization_code" ];
          }
          {
            client_id = "headplane";
            client_name = "Headplane";
            client_secret = "{{ secret \"${secretsDir}/headplane_secret_hash\" }}";
            public = false;
            authorization_policy = "two_factor";
            redirect_uris = [
              "https://vpn.private.cskjolden.com/admin/oidc/callback"
              "https://vpn.private.cskjolden.com/admin/auth/oidc-callback"
              "https://vpn.private.cskjolden.com/oidc/callback"
            ];
            scopes = [ "openid" "profile" "email" ];
            response_types = [ "code" ];
            grant_types = [ "authorization_code" ];
          }
        ];
      };

      identity_validation = {
        reset_password.jwt_secret = "{{ secret \"${secretsDir}/jwt\" }}";
      };

      session = {
        name = "authelia_session";
        same_site = "lax";
        expiration = "1h";
        inactivity = "15m";
        remember_me = "1M";
        secret = "{{ secret \"${secretsDir}/session\" }}";
        cookies = [
          {
            domain = "private.cskjolden.com";
            authelia_url = "https://auth.private.cskjolden.com";
            default_redirection_url = "https://private.cskjolden.com";
          }
        ];
      };

      storage = {
        encryption_key = "{{ secret \"${secretsDir}/storage\" }}";
        local.path = "/var/lib/authelia-main/db.sqlite3";
      };

      notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

      authentication_backend = {
        password_reset.disable = true;
        file = {
          path = "/var/lib/authelia-main/users_database.yml";
          watch = true;
        };
      };

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = [ "*.private.cskjolden.com" ];
            policy = "two_factor";
          }
        ];
      };
    };
  };

  # Bootstrap secrets and starter user file during activation
  system.activationScripts.autheliaBootstrap = lib.stringAfter [ "users" ] ''
    mkdir -p "${secretsDir}"
    chmod 700 "${secretsDir}"

    [ -s "${secretsDir}/jwt" ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > "${secretsDir}/jwt"
    [ -s "${secretsDir}/session" ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > "${secretsDir}/session"
    [ -s "${secretsDir}/storage" ] || ${pkgs.openssl}/bin/openssl rand -hex 32 > "${secretsDir}/storage"

    chmod 600 ${secretsDir}/*
    chown -R authelia-main:authelia-main /var/lib/authelia-main

    if [ ! -f /var/lib/authelia-main/users_database.yml ]; then
      cat << 'EOF' > /var/lib/authelia-main/users_database.yml
users:
  skjold:
    displayname: "Skjold"
    email: "skjold@private.cskjolden.com"
    groups:
      - admins
      - dev
EOF
      chmod 600 /var/lib/authelia-main/users_database.yml
      chown authelia-main:authelia-main /var/lib/authelia-main/users_database.yml
    fi
  '';
}
