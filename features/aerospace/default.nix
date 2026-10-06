{ config, lib, pkgs, ... }:
let
  cfg = builtins.fromTOML (builtins.readFile ./workspaces.toml);
  workspaces = cfg.workspace;
  inherit (cfg) floating;
  names = map (w: w.name) workspaces;
  catchAll = lib.last workspaces;
  # Windows land in their workspace, then set its layout if it has one (a container-wide setting).
  placeIn = w: [ "move-node-to-workspace ${w.name}" ] ++ lib.optional (w ? layout) "layout ${w.layout}";
  layoutOf = w: w.layout or "";
  sketchybar = "${config.services.sketchybar.package}/bin/sketchybar";
  aerospace = "${config.services.aerospace.package}/bin/aerospace";

  hyper = "cmd-alt-ctrl";
  prefixed = prefix: lib.mapAttrs' (key: cmd: lib.nameValuePair "${prefix}-${key}" cmd);

  # Wrap mode
  wrap = "--boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors";

  # Bar updates
  refreshBar = "exec-and-forget ${sketchybar} --trigger aerospace_workspace_change";
  barScript = "$HOME/dotfiles/features/sketchybar/plugins/aerospace.sh";

  # Re-apply standard rules
  resetWindows = pkgs.writeShellScript "aerospace-reset-windows" ''
    ${aerospace} list-windows --all --format '%{window-id}|%{app-bundle-id}' | while IFS='|' read -r id app; do
      case "$app" in
        ${lib.concatStringsSep "|" floating}) ${aerospace} layout --window-id "$id" floating; continue ;;
      esac
      case "$app" in
        ${lib.concatMapStrings (w: "${lib.concatStringsSep "|" w.apps}) ws=${w.name} lay=${layoutOf w} ;;\n        ") workspaces}*) ws=${catchAll.name} lay=${layoutOf catchAll} ;;
      esac
      ${aerospace} move-node-to-workspace --window-id "$id" "$ws"
      ${aerospace} layout --window-id "$id" tiling
      [ -z "$lay" ] || ${aerospace} layout --window-id "$id" "$lay"
    done
  '';

  # Next window in top bar order
  cycleWindows = pkgs.writeShellScript "aerospace-cycle-windows" ''
    ids="$(${aerospace} list-windows --workspace focused --format '%{window-id}')"
    focused="$(${aerospace} list-windows --focused --format '%{window-id}')"
    next="$(printf '%s\n' "$ids" | grep -x -A1 "$focused" | tail -n1)"
    [ "$next" != "$focused" ] || next="$(printf '%s\n' "$ids" | head -n1)"
    [ -z "$next" ] || ${aerospace} focus --window-id "$next"
  '';
in
{
  services.aerospace = {
    enable = true;

    settings = {
      config-version = 2; # Needed for persistent-workspaces.
      automatically-unhide-macos-hidden-apps = true;
      persistent-workspaces = names;

      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      accordion-padding = 16;

      gaps = {
        inner = { horizontal = 4; vertical = 4; };
        outer = { left = 4; right = 4; bottom = 4; top = 4; };
      };

      exec-on-workspace-change = [
        "/bin/bash" "-c"
        "${sketchybar} --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
      ];

      on-focus-changed = [ refreshBar ];

      # Check if rules applies or sends to the catch-all workspace
      on-window-detected =
        map
          (app: {
            "if".app-id = app;
            run = "layout floating";
          })
          floating
        ++ lib.concatMap
          (w: map
            (app: {
              "if".app-id = app;
              run = placeIn w;
            })
            w.apps)
          workspaces
        ++ [{ run = placeIn catchAll; }];

      mode.main.binding =
        prefixed hyper {
          # Focus, layout and windows
          h = "focus ${wrap} left";
          j = "focus ${wrap} down";
          k = "focus ${wrap} up";
          l = "focus ${wrap} right";
          f = [ "fullscreen" refreshBar ];
          s = [ "layout tiles horizontal vertical" refreshBar ];
          a = [ "layout accordion horizontal vertical" refreshBar ];
          w = [ "layout floating tiling" refreshBar ];
          i = "exec-and-forget sh ${barScript} toggle"; # App icons in the bar's active workspace pill
          n = "exec-and-forget ${cycleWindows}";
          comma = "resize smart -50";
          period = "resize smart +50";
          r = "exec-and-forget ${resetWindows}"; # Windows back to their workspaces
          b = "balance-sizes";
          m = "reload-config";

          # Workspaces
          left = "workspace --wrap-around prev";
          right = "workspace --wrap-around next";
          tab = "workspace-back-and-forth";
        }
        // prefixed "${hyper}-shift" {
          h = "move left";
          j = "move down";
          k = "move up";
          l = "move right";
          r = [ "flatten-workspace-tree" refreshBar ]; # Also undoes join
          tab = "move-workspace-to-monitor --wrap-around next";
          comma = [ "join-with left" refreshBar ];
          period = [ "join-with right" refreshBar ];
        }
        // prefixed hyper (lib.listToAttrs (lib.imap1
          (i: name: lib.nameValuePair (toString i) "workspace ${name}")
          names))
        // prefixed "${hyper}-shift" (lib.listToAttrs (lib.imap1
          (i: name: lib.nameValuePair (toString i) "move-node-to-workspace ${name}")
          names));
    };
  };
}
