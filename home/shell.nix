{ lib, pkgs, ... }:
{
  imports = [ ./iris.nix ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = false;     # Conflicts with Iris ghost text
    syntaxHighlighting.enable = true;
    autocd = true;

    # Full compinit (with audit) at most once a day
    completionInit = ''
      autoload -Uz compinit
      if [[ -n ~/.zcompdump(#qNmh-24) ]]; then
        compinit -C
      else
        compinit
      fi
    '';

    # Type part of a command and press Up/Down to search matching history
    historySubstringSearch = {
      enable = true;
    };

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = true;
    };

    shellAliases = {
      cat = "bat --paging=never";
      tree = "eza --tree";
    };

    plugins = [
      {
        name = "you-should-use";
        src = "${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use";
      }
    ];

    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    initContent = lib.mkMerge [
      ''
      # Case-insensitive tab completion & arrow menu navigation
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' menu select

      # Push directory stack (quick navigation with `cd -<TAB>`)
      setopt AUTO_PUSHD
      setopt PUSHD_IGNORE_DUPS
      setopt PUSHD_SILENT

      autoload -U select-word-style && select-word-style bash # Better word recognition
      

      # Option + Arrow and Option + Backspace keybindings
      bindkey '^[^?' backward-kill-word
      bindkey '^[b' backward-word
      bindkey '^[f' forward-word
      bindkey '^[[1;3D' backward-word
      bindkey '^[[1;3C' forward-word
      bindkey '^[d' kill-word
      ''
      # Must come last: it re-execs the shell inside Iris
      (lib.mkAfter ''
        eval "$(iris init zsh)"
      '')
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --exclude .git";
    fileWidget.command = "fd --type f --hidden --exclude .git";
    changeDirWidget.command = "fd --type d --hidden --exclude .git";
  };

  programs.eza = {
    enable = true;
    git = true;
    icons = "auto";
  };

  programs.bat.enable = true;

  programs.starship.enable = true;
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

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
