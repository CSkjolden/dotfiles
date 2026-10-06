#!/bin/sh
# AeroSpace integration: workspace pills (with app icons for the active one), a layout pill and border colors.
#   aerospace.sh setup   builds the items (run from sketchybarrc)
#   aerospace.sh         restyles them (run by the ws.ctl item)
#   aerospace.sh toggle  shows or hides the app icons in the active pill
. "$(dirname "$0")/lib.sh"
AS=/run/current-system/sw/bin/aerospace
BORDERS=/run/current-system/sw/bin/borders
CONFIG="$HOME/dotfiles/features/aerospace/workspaces.toml"
WORKSPACES="$DIR/workspaces" # i<TAB>name<TAB>icon path prefix, one line per workspace
APPICONS_OFF="$DIR/appicons.off"
TAB="$(printf '\t')"

# One glyph, text and border color per layout; TILES matches active_color in features/jankyborders.nix.
LAYOUT_SYMBOLS="rectangle.split.2x1 rectangle.split.1x2 rectangle.stack rectangle.on.rectangle arrow.up.left.and.arrow.down.right"
TILES=0xff89b4fa ACCORDION=0xffcba6f7 FLOATING=0xfffab387 FULLSCREEN=0xffa6e3a1

setup() {
  rows="$(awk -F'"' '/^name = / { name = $2 } /^symbol = / { print name "\t" $2 }' "$CONFIG")"
  ensure_icons $(printf '%s\n' "$rows" | cut -f2 | sort -u) $LAYOUT_SYMBOLS
  : > "$WORKSPACES"
  reset_state aerospace
  reset_state borders

  sketchybar --add event aerospace_workspace_change

  i=0
  add_spacer left.lead left 4
  printf '%s\n' "$rows" | while IFS="$TAB" read -r name symbol; do
    i=$((i + 1))
    printf '%s\t%s\t%s\n' "$i" "$name" "$ICON_DIR/$symbol" >> "$WORKSPACES"
    add_workspace "$i" "$name" "$ICON_DIR/$symbol" "$AS workspace '$name'"
  done

  # Layout of the focused window; hidden while no window is focused.
  add_spacer layout.gap left 8
  add_spacer layout.pad left $INSET
  add_icon layout.icon left $SLOT ""
  sketchybar \
    --add item layout.label left \
    --set layout.label $BARE label.drawing=on label.padding_right=10
  add_spacer left.trail left 4

  members="left.lead layout.gap layout.pad layout.icon layout.label left.trail"
  count="$(wc -l < "$WORKSPACES" | tr -d ' ')"
  i=1
  while [ "$i" -le "$count" ]; do
    members="$members $(workspace_members "$i")"
    i=$((i + 1))
  done
  sketchybar --add bracket left.bg $members --set left.bg $CONTAINER

  i=1
  while [ "$i" -le "$count" ]; do
    add_workspace_pill "$i"
    i=$((i + 1))
  done
  sketchybar \
    --add bracket layout.bg layout.pad layout.icon layout.label \
    --set layout.bg $PILL

  # Zero-width host for the update script; the slow update_freq is only a safety net for missed events.
  add_spacer ws.ctl left 0 update_freq=10 script="sh $0"
  sketchybar --subscribe ws.ctl aerospace_workspace_change
}

update() {
  # $FOCUSED_WORKSPACE comes from the AeroSpace trigger; otherwise ask the CLI.
  current="${FOCUSED_WORKSPACE:-$($AS list-workspaces --focused 2>/dev/null)}"
  occupied="$($AS list-workspaces --monitor all --empty no 2>/dev/null)"

  fid="" flayout="" ffull=""
  IFS='|' read -r fid flayout ffull <<EOF
$($AS list-windows --focused --format '%{window-id}|%{window-layout}|%{window-is-fullscreen}' 2>/dev/null)
EOF

  wins=""
  [ -f "$APPICONS_OFF" ] || wins="$($AS list-windows --workspace "$current" --format '%{window-id}|%{app-bundle-id}' 2>/dev/null)"

  set --
  while IFS="$TAB" read -r i name icon; do
    if [ "$name" = "$current" ]; then
      variant=$ACTIVE state=on
    elif printf '%s\n' "$occupied" | grep -qx "$name"; then
      variant=$NORMAL state=off
    else
      variant=$EMPTY state=off
    fi
    set -- "$@" \
      --set "ws.$i" background.image="$icon.$variant.png" \
      --set "ws.$i.label" drawing=$state \
      --set "ws.$i.bg" background.drawing=$state

    # App icons for the windows of the active workspace, the focused one at full brightness.
    slot=1
    if [ "$state" = on ] && [ -n "$wins" ]; then
      while [ "$slot" -le "$APPSLOTS" ] && IFS='|' read -r wid app; do
        [ -f "$ICON_DIR/app.$app.100.png" ] || ensure_app_icons "$app"
        [ -f "$ICON_DIR/app.$app.100.png" ] || continue
        if [ "$wid" = "$fid" ]; then shade=100; else shade=$APPDIM; fi
        set -- "$@" --set "ws.$i.app.$slot" drawing=on \
          background.image="$ICON_DIR/app.$app.$shade.png" click_script="$AS focus --window-id $wid"
        slot=$((slot + 1))
      done <<EOF
$wins
EOF
    fi
    while [ "$slot" -le "$APPSLOTS" ]; do
      set -- "$@" --set "ws.$i.app.$slot" drawing=off
      slot=$((slot + 1))
    done
  done < "$WORKSPACES"

  glyph="" text="" color=""
  if [ -n "$fid" ]; then
    if [ "$ffull" = true ]; then
      glyph=arrow.up.left.and.arrow.down.right text=fullscreen color=$FULLSCREEN
    else
      case "$flayout" in
        h_tiles) glyph=rectangle.split.2x1 text="tiles ↔" color=$TILES ;;
        v_tiles) glyph=rectangle.split.1x2 text="tiles ↕" color=$TILES ;;
        h_accordion) glyph=rectangle.stack text="accordion ↔" color=$ACCORDION ;;
        v_accordion) glyph=rectangle.stack text="accordion ↕" color=$ACCORDION ;;
        floating) glyph=rectangle.on.rectangle text=floating color=$FLOATING ;;
      esac
    fi
  fi

  if [ -n "$glyph" ]; then
    set -- "$@" \
      --set layout.gap drawing=on --set layout.pad drawing=on \
      --set layout.icon drawing=on background.image="$ICON_DIR/$glyph.100.png" \
      --set layout.label drawing=on label="$text" \
      --set layout.bg background.drawing=on
    changed borders "$color" && "$BORDERS" active_color="$color"
  else
    set -- "$@" \
      --set layout.gap drawing=off --set layout.pad drawing=off \
      --set layout.icon drawing=off --set layout.label drawing=off \
      --set layout.bg background.drawing=off
  fi

  changed aerospace "$*" || return 0
  sketchybar "$@"
}

toggle() {
  PATH="/run/current-system/sw/bin:$PATH"
  if [ -f "$APPICONS_OFF" ]; then rm -f "$APPICONS_OFF"; else mkdir -p "$DIR" && : > "$APPICONS_OFF"; fi
  sketchybar --trigger aerospace_workspace_change
}

case "$1" in
  toggle) toggle ;;
  *) dispatch "$1" ;;
esac
