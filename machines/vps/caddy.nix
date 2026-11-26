{ ... }:
{
  services.caddy = {
    enable = true;

    extraConfig = ''
      (security_headers) {
        header {
          ?Strict-Transport-Security "max-age=31536000; includeSubDomains"
          ?X-Content-Type-Options "nosniff"
          ?Referrer-Policy "strict-origin-when-cross-origin"
        }
      }
    '';

    virtualHosts."auth.private.cskjolden.com".extraConfig = ''
      import security_headers
      reverse_proxy 127.0.0.1:9091
    '';

    virtualHosts."headscale.private.cskjolden.com".extraConfig = ''
      import security_headers
      reverse_proxy 127.0.0.1:8080
    '';

    virtualHosts."git.private.cskjolden.com".extraConfig = ''
      import security_headers
      reverse_proxy 127.0.0.1:3000
    '';

    virtualHosts."vpn.private.cskjolden.com".extraConfig = ''
      import security_headers
      redir / /admin/ 302
      reverse_proxy 127.0.0.1:3001
    '';
  };

  # Open HTTP and HTTPS ports for reverse proxy and Let's Encrypt certificates
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
