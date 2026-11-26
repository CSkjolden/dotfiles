{ pkgs, ... }:
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers."paseo" = {
      image = "localhost/paseo:latest";
      autoStart = true;
      extraOptions = [
        "--network=host"
      ];
      volumes = [
        "/var/lib/paseo/data:/root/.paseo"
        "/var/lib/paseo/workspaces:/workspaces"
      ];
      cmd = [
        "paseo"
        "daemon"
        "run"
      ];
    };
  };

  # Automatically build the sandboxed Paseo container image if missing
  systemd.services.paseo-image-build = {
    description = "Build Paseo container image";
    wantedBy = [ "podman-paseo.service" ];
    before = [ "podman-paseo.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/paseo/data /var/lib/paseo/workspaces /var/lib/paseo/image

      cat << 'EOF' > /var/lib/paseo/image/Containerfile
      FROM node:22-bookworm

      RUN apt-get update && apt-get install -y --no-install-recommends \
          git \
          curl \
          ca-certificates \
          build-essential \
          python3 \
          python3-pip \
          ripgrep \
          jq \
          && rm -rf /var/lib/apt/lists/*

      RUN npm install -g @getpaseo/cli@0.15.4

      # Redirect any agent git clone/fetch requests for github.com to private Forgejo
      RUN git config --global url."https://git.private.cskjolden.com/".insteadOf "https://github.com/" \
          && git config --global url."ssh://git@git.private.cskjolden.com:2222/".insteadOf "git@github.com:"

      WORKDIR /workspaces
      EXPOSE 6768

      CMD ["paseo", "daemon", "run"]
      EOF

      ${pkgs.podman}/bin/podman build -t localhost/paseo:latest /var/lib/paseo/image
    '';
  };

  # Host CLI wrapper: running 'paseo' on the VPS executes inside the isolated sandbox
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "paseo" ''
      exec ${pkgs.podman}/bin/podman exec -it -w /workspaces paseo paseo "$@"
    '')
  ];
}
