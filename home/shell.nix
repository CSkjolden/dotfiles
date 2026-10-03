{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = true;
    };

    shellAliases.cat = "bat --paging=never";

    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)" # Set up Homebrew environment
    '';

    initContent = ''
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive
      zstyle ':completion:*' menu select # Menu selection
    '';
  };

  programs.starship.enable = true;
  programs.zoxide.enable = true;
  programs.fzf.enable = true;
  programs.eza.enable = true;
  programs.bat.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    nix-zsh-completions
  ];
}
