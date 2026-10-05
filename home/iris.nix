{ pkgs, ... }:
{
  home.packages = [ pkgs.iris ];

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
}
