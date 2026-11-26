{ lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./vps-disk.nix
    ./vps/podman.nix
    ./vps/caddy.nix
    ./vps/authelia.nix
    ./vps/headscale.nix
    ./vps/forgejo.nix
    ./vps/headplane.nix
    ./vps/paseo.nix
  ];

  networking.hostName = "vps";

  # Bootloader: Dual BIOS + UEFI support for OVH KVM
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = [ "/dev/sda" ];
  };

  # Network
  networking.useDHCP = lib.mkDefault true;

  # SSH Access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Paste your SSH public key(s) here before running nixos-anywhere
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHAL62OaXCzLw3xxtY4t+Cjf96DXovGnB8vykAQrcV/E skjold@dotfiles"
  ];

  # Basic system packages for a minimal server
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    nano
    vim
  ];

  # Intrusion prevention: ban repeated SSH brute-force attempts
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "24h";
  };

  # Automatic Nix store cleanup & optimization (prevents disk fill)
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # State version for initial install
  system.stateVersion = "24.11";
}
