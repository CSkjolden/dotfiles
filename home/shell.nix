{ lib, pkgs, ... }:
{
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

  xdg.configFile."iris/config.toml".source = (pkgs.formats.toml { }).generate "iris-config.toml" {
    core.version = 1;
    core.shell = "zsh";
    ui.style = "modern";
    ui.hidden-files = true;
    zoxide.extend-cd = true;
    core.expand-alias = false;
    keybindings.toggle-mode = "shift+tab";
    keybindings.toggle-menu = "none";
    updater = {
      check-on-startup = false;
      auto-update = 0;
    };
  };

  xdg.configFile."iris/theme.toml".source = (pkgs.formats.toml { }).generate "iris-theme.toml" {
    border = "#296dff";
    accent = "#004b77";
    muted = "#565f89";
    text = "#c0caf5";
    text_sel = "#ffffff";
    key = "#bb9af7";
    match = "#73daca";
    desc = "#9aa5ce";
    desc_sel = "#c0caf5";
    sel_bg = "#283451";
    sel_text = "#1a1b26";
    scroll_info = "#7aa2f7";
    ghost_text = "#414868";
    sys = "#24283b";
    sys_sel = "#f7768e";
    hist = "#1f2335";
    hist_sel = "#7dcfff";
    alias = "#24283b";
    alias_sel = "#bb9af7";
  };

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
    iris
    nix-zsh-completions
  ];
}
