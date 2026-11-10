#!/bin/sh
# AeroSpace integration: workspace pills, a separate app strip, a layout pill and border colors.
#   aerospace.sh setup   builds the items (run from sketchybarrc)
#   aerospace.sh         restyles them (run by the ws.ctl item)
#   aerospace.sh toggle  shows or hides the active workspace's app icons
. "$(dirname "$0")/lib.sh"
AS=/run/current-system/sw/bin/aerospace
BORDERS=/run/current-system/sw/bin/borders
CONFIG="$HOME/dotfiles/features/aerospace/workspaces.toml"
WORKSPACES="$DIR/workspaces" # i<TAB>name<TAB>icon path prefix, one line per workspace
APPICONS_OFF="$DIR/appicons.off"
REQUEST="$DIR/aerospace.request"
LOCK="$DIR/aerospace.lock"
TAB="$(printf '\t')"

# One glyph, text and border color per layout; TILES matches active_color in features/jankyborders.nix.
LAYOUT_SYMBOLS="rectangle.split.2x1 rectangle.split.1x2 rectangle.stack rectangle.on.rectangle arrow.up.left.and.arrow.down.right"
TILES=0xff89b4fa ACCORDION=0xffcba6f7 FLOATING=0xfffab387 FULLSCREEN=0xffa6e3a1

setup() {
  focus_workspace="$(awk -F'"' '/^focus-workspace = / { print $2 }' "$CONFIG")"
  rows="$(awk -F'"' '/^name = / { name = $2 } /^symbol = / { print name "\t" $2 }' "$CONFIG")"
  ensure_icons $(printf '%s\n' "$rows" | cut -f2 | sort -u) $LAYOUT_SYMBOLS app.dashed
  : > "$WORKSPACES"
  printf '%s\n' "$focus_workspace" > "$DIR/focus.workspace"
  reset_state aerospace
  reset_state borders
  reset_state aerospace.retry
  reset_state aerospace.focus

  sketchybar --add event aerospace_workspace_change
  sketchybar --add event aerospace_focus_change
  sketchybar --add event aerospace_details

  i=0
  add_spacer left.lead left 4
  printf '%s\n' "$rows" | while IFS="$TAB" read -r name symbol; do
    [ "$name" != "$focus_workspace" ] || continue
    i=$((i + 1))
    reset_state "aerospace.ws.$i"
    printf '%s\t%s\t%s\n' "$i" "$name" "$ICON_DIR/$symbol" >> "$WORKSPACES"
    add_workspace "$i" "$name" "$ICON_DIR/$symbol" "$AS workspace '$name'"
  done

  # Layout and active app sections occupy space only when populated.
  add_spacer layout.gap left 0
  add_spacer layout.pad left 0
  add_icon layout.icon left 0 "" background.drawing=off
  sketchybar --add item layout.direction left \
    --set layout.direction $BARE label.drawing=off width=0 label.padding_right=9

  focus_click="$AS workspace '$focus_workspace'"
  add_spacer focus.gap left 12
  add_spacer focus.pad left $INSET click_script="$focus_click"
  add_icon focus.icon left $SLOT "$ICON_DIR/scope.$NORMAL.png" click_script="$focus_click"
  focus_members="focus.pad focus.icon"
  slot=1
  while [ "$slot" -le "$APPSLOTS" ]; do
    add_icon "focus.$slot" left 0 "" background.drawing=off
    focus_members="$focus_members focus.$slot"
    slot=$((slot + 1))
  done

  add_spacer apps.gap left 0
  add_spacer apps.pad left 0
  app_members="apps.pad"
  slot=1
  while [ "$slot" -le "$APPSLOTS" ]; do
    add_icon "apps.$slot" left 0 "" background.drawing=off
    app_members="$app_members apps.$slot"
    slot=$((slot + 1))
  done
  rm -f "$DIR/aerospace.apps.workspace"

  add_spacer left.trail left 4

  members="left.lead layout.gap layout.pad layout.icon layout.direction focus.gap $focus_members apps.gap $app_members left.trail"
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
  sketchybar --add bracket apps.bg $app_members --set apps.bg $PILL background.drawing=off
  sketchybar --add bracket focus.bg $focus_members --set focus.bg $PILL
  sketchybar \
    --add bracket layout.bg layout.pad layout.icon layout.direction \
    --set layout.bg $PILL background.drawing=off

  # Zero-width host for the update script; the slow update_freq is only a safety net for missed events.
  add_spacer ws.ctl left 0 update_freq=10 script="sh $0"
  sketchybar --subscribe ws.ctl aerospace_workspace_change aerospace_focus_change display_change system_woke
  add_spacer ws.details left 0 script="sh $0 details"
  sketchybar --subscribe ws.details aerospace_details
  for state_file in "$DIR"/aerospace.item.*.state; do
    [ ! -f "$state_file" ] || rm -f "$state_file"
  done
  for missing_icon in "$ICON_DIR"/app.*.missing; do
    [ ! -f "$missing_icon" ] || rm -f "$missing_icon"
  done
}

highlight() {
  set --
  focus_workspace=""
  if [ -f "$DIR/focus.workspace" ]; then
    IFS= read -r focus_workspace < "$DIR/focus.workspace" || true
  fi
  if [ -n "$focus_workspace" ]; then
    if [ "$current" = "$focus_workspace" ]; then focus_variant=$ACTIVE
    else focus_variant=$NORMAL
    fi
    if changed aerospace.focus "$focus_variant"; then
      set -- "$@" --set focus.icon background.image="$ICON_DIR/scope.$focus_variant.png"
    fi
  fi
  while IFS="$TAB" read -r i name icon; do
    if [ "$name" = "$current" ]; then
      variant=$ACTIVE state=on name_width=42
    else
      case "
$occupied
" in
        *"
$name
"*) variant=$NORMAL ;;
        *) variant=$EMPTY ;;
      esac
      state=off name_width=0
    fi
    previous=""
    if [ -f "$DIR/aerospace.ws.$i.state" ]; then
      IFS= read -r previous < "$DIR/aerospace.ws.$i.state" || true
    fi
    [ "$previous" != "$variant $state $name_width" ] || continue
    printf '%s' "$variant $state $name_width" > "$DIR/aerospace.ws.$i.state"
    set -- "$@" --set "ws.$i" background.image="$icon.$variant.png" \
      --set "ws.$i.label" label.drawing=$state width=$name_width \
      --set "ws.$i.bg" background.drawing=$state
  done < "$WORKSPACES"
  rendered_workspace=""
  if [ -f "$DIR/aerospace.apps.workspace" ]; then
    IFS= read -r rendered_workspace < "$DIR/aerospace.apps.workspace" || true
  fi
  if [ "$rendered_workspace" != "$current" ]; then
    rm -f "$DIR"/aerospace.item.app.*.state
    reset_state aerospace.item.apps.visibility
    slot=1
    while [ "$slot" -le "$APPSLOTS" ]; do
      set -- "$@" --set "apps.$slot" background.drawing=off click_script="" width=0
      slot=$((slot + 1))
    done
    set -- "$@" --set apps.gap width=0 --set apps.pad width=0 \
      --set apps.bg background.drawing=off
    printf '%s\n' "$current" > "$DIR/aerospace.apps.workspace"
  fi
  [ "$#" -eq 0 ] || sketchybar "$@"
}

update() {
  current="${FOCUSED_WORKSPACE:-$($AS list-workspaces --focused 2>/dev/null || true)}"
  if [ -z "$current" ]; then
    attempts="$(cat "$DIR/aerospace.retry.state" 2>/dev/null || true)"
    attempts=$((${attempts:-0} + 1))
    printf '%s' "$attempts" > "$DIR/aerospace.retry.state"
    if [ "$attempts" -lt 10 ]; then
      sketchybar --set ws.ctl update_freq=1
    else
      sketchybar --set ws.ctl update_freq=10
    fi
    return 0
  fi
  if [ -f "$DIR/aerospace.retry.state" ]; then
    reset_state aerospace.retry
    sketchybar --set ws.ctl update_freq=10
  fi
  printf '%s\n%s\n%s\n' "$current" "$$" "${SENDER:-refresh}" > "$REQUEST.$$"
  mv -f "$REQUEST.$$" "$REQUEST"
  printf '%s\n' "$current" > "$DIR/aerospace.focused"
  occupied="$(cat "$DIR/aerospace.occupied" 2>/dev/null)"
  highlight
  sketchybar --trigger aerospace_details
}

item_changed() {
  _key="$1"; shift
  [ "$*" != "$(cat "$DIR/aerospace.item.$_key.state" 2>/dev/null)" ] || return 1
  printf '%s' "$*" > "$pending/aerospace.item.$_key.state"
}

refresh() {
  IFS= read -r current < "$REQUEST"
  reason="$(printf '%s\n' "$request" | sed -n 3p)"
  occupied="$(cat "$DIR/aerospace.occupied" 2>/dev/null)"
  if [ "$reason" != aerospace_focus_change ]; then
    occupied="$($AS list-workspaces --monitor all --empty no 2>/dev/null)" || return 0
  fi

  fid="" flayout="" ffull=""
  IFS='|' read -r fid flayout ffull <<EOF
$($AS list-windows --focused --format '%{window-id}|%{window-layout}|%{window-is-fullscreen}' 2>/dev/null)
EOF

  focus_workspace=""
  if [ -f "$DIR/focus.workspace" ]; then
    IFS= read -r focus_workspace < "$DIR/focus.workspace" || true
  fi
  if [ -n "$focus_workspace" ]; then
    windows="$($AS list-windows --workspace "$current" "$focus_workspace" --format '%{workspace}|%{window-id}|%{app-bundle-id}' 2>/dev/null)" || return 0
  else
    windows="$($AS list-windows --workspace "$current" --format '%{workspace}|%{window-id}|%{app-bundle-id}' 2>/dev/null)" || return 0
  fi
  wins="" focus_wins=""
  while IFS='|' read -r workspace wid app; do
    [ -n "$wid" ] || continue
    if [ "$workspace" = "$focus_workspace" ]; then
      focus_wins="$focus_wins$wid|$app
"
    elif [ "$workspace" = "$current" ] && [ ! -f "$APPICONS_OFF" ]; then
      wins="$wins$wid|$app
"
    fi
  done <<EOF
$windows
EOF
  [ "$request" = "$(cat "$REQUEST" 2>/dev/null)" ] || return 0
  highlight
  pending="$DIR/aerospace.pending.$$"
  mkdir -p "$pending"

  set --
  for section in apps focus; do
    if [ "$section" = apps ]; then
      section_wins="$wins" cache_prefix=app
    else
      section_wins="$focus_wins" cache_prefix=focus.app
    fi
    slot=1
    if [ -n "$section_wins" ]; then
      while [ "$slot" -le "$APPSLOTS" ] && IFS='|' read -r wid app; do
        [ -n "$wid" ] || continue
        [ -f "$ICON_DIR/app.$app.100.png" ] || queue_icon "$app"
        if [ "$wid" = "$fid" ]; then shade=100; else shade=$APPDIM; fi
        if [ "$section" = focus ]; then
          if [ "$current" = "$focus_workspace" ]; then shade=$ACTIVE
          else shade=$APPDIM
          fi
        fi
        if [ -f "$ICON_DIR/app.$app.100.png" ]; then
          image="$ICON_DIR/app.$app.$shade.png"
        else
          image="$ICON_DIR/app.dashed.70.png"
        fi
        if item_changed "$cache_prefix.$slot" "$image $wid"; then
          set -- "$@" --set "$section.$slot" background.drawing=on width=$APPSLOT \
            background.image="$image" click_script="$AS focus --window-id $wid"
        fi
        slot=$((slot + 1))
      done <<EOF
$section_wins
EOF
    fi
    visible_slots=$((slot - 1))
    while [ "$slot" -le "$APPSLOTS" ]; do
      if item_changed "$cache_prefix.$slot" off; then
        set -- "$@" --set "$section.$slot" background.drawing=off click_script="" width=0
      fi
      slot=$((slot + 1))
    done
  if [ "$section" = apps ] && item_changed "$section.visibility" "$visible_slots"; then
    if [ "$visible_slots" -gt 0 ]; then
      set -- "$@" --set "$section.gap" width=12 --set "$section.pad" width=$INSET \
        --set "$section.bg" background.drawing=on
    else
      set -- "$@" --set "$section.gap" width=0 --set "$section.pad" width=0 \
        --set "$section.bg" background.drawing=off
    fi
  fi
  done

  glyph="" direction="" color=""
  if [ -n "$fid" ]; then
    if [ "$ffull" = true ]; then
      glyph=arrow.up.left.and.arrow.down.right color=$FULLSCREEN
    else
      case "$flayout" in
        h_tiles) glyph=rectangle.split.2x1 color=$TILES ;;
        v_tiles) glyph=rectangle.split.1x2 color=$TILES ;;
        h_accordion) glyph=rectangle.stack color=$ACCORDION ;;
        v_accordion) glyph=rectangle.stack color=$ACCORDION ;;
        floating) glyph=rectangle.on.rectangle color=$FLOATING ;;
      esac
      case "$flayout" in
        h_tiles|h_accordion) direction="$(printf '\342\206\224')" ;;
        v_tiles|v_accordion) direction="$(printf '\342\206\225')" ;;
      esac
    fi
  fi

  layout_width=0
  [ -z "$glyph" ] || layout_width=$((8 + INSET + SLOT + 24))
  if item_changed layout "$glyph $direction $color $layout_width"; then
    if [ -n "$glyph" ]; then
      set -- "$@" \
        --set layout.gap width=8 --set layout.pad width=$INSET \
        --set layout.icon background.drawing=on width=$SLOT background.image="$ICON_DIR/$glyph.100.png" \
        --set layout.bg background.drawing=on
      if [ -n "$direction" ]; then
        set -- "$@" --set layout.direction label.drawing=on label="$direction" width=24
      else
        set -- "$@" --set layout.direction label.drawing=off width=24
      fi
    else
      set -- "$@" \
        --set layout.gap width=0 --set layout.pad width=0 \
        --set layout.icon background.drawing=off width=0 \
        --set layout.direction label.drawing=off width=0 \
        --set layout.bg background.drawing=off
    fi
  fi

  if [ "$request" != "$(cat "$REQUEST" 2>/dev/null)" ]; then
    rm -rf "$pending"
    return 0
  fi
  if [ "$#" -gt 0 ] && ! sketchybar "$@"; then
    rm -rf "$pending"
    return 0
  fi
  if [ "$request" != "$(cat "$REQUEST" 2>/dev/null)" ]; then
    rm -rf "$pending"
    return 0
  fi
  for state_file in "$pending"/*.state; do
    [ ! -f "$state_file" ] || mv -f "$state_file" "$DIR/"
  done
  rmdir "$pending"
  printf '%s\n' "$occupied" > "$DIR/aerospace.occupied"
  if [ -n "$color" ] && changed borders "$color"; then
    "$BORDERS" active_color="$color"
  fi
}

details() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    owner="$(cat "$LOCK/pid" 2>/dev/null)"
    [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null || return 0
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null || return 0
  fi
  printf '%s' "$$" > "$LOCK/pid"
  trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; rm -rf "$DIR/aerospace.pending.$$"' EXIT
  trap 'exit 0' HUP INT TERM
  while :; do
    request="$(cat "$REQUEST" 2>/dev/null)"
    [ -z "$request" ] || refresh
    [ "$request" = "$(cat "$REQUEST" 2>/dev/null)" ] && break
  done
  rm -f "$LOCK/pid"
  rmdir "$LOCK"
  trap - EXIT HUP INT TERM
  [ "$request" = "$(cat "$REQUEST" 2>/dev/null)" ] || details
}

queue_icon() {
  [ -n "$1" ] || return 0
  [ ! -f "$ICON_DIR/app.$1.missing" ] || return 0
  if ! mkdir "$ICON_DIR/app.$1.lock" 2>/dev/null; then
    icon_owner="$(cat "$ICON_DIR/app.$1.lock/pid" 2>/dev/null)"
    [ -n "$icon_owner" ] && ! kill -0 "$icon_owner" 2>/dev/null || return 0
    rm -f "$ICON_DIR/app.$1.lock/pid"
    rmdir "$ICON_DIR/app.$1.lock" 2>/dev/null && mkdir "$ICON_DIR/app.$1.lock" 2>/dev/null || return 0
  fi
  sh "$0" icon "$1" >/dev/null 2>&1 &
  printf '%s' "$!" > "$ICON_DIR/app.$1.lock/pid"
}

render_icon() {
  trap 'rm -f "$ICON_DIR/app.$app.lock/pid"; rmdir "$ICON_DIR/app.$app.lock" 2>/dev/null' EXIT
  trap 'exit 0' HUP INT TERM
  ensure_app_icons "$app"
  if [ -f "$ICON_DIR/app.$app.100.png" ]; then
    sketchybar --trigger aerospace_focus_change
  else
    touch "$ICON_DIR/app.$app.missing"
  fi
}

toggle() {
  PATH="/run/current-system/sw/bin:$PATH"
  if [ -f "$APPICONS_OFF" ]; then rm -f "$APPICONS_OFF"; else mkdir -p "$DIR" && : > "$APPICONS_OFF"; fi
  sketchybar --trigger aerospace_workspace_change
}

case "$1" in
  toggle) toggle ;;
  details) details ;;
  icon) app="$2"; render_icon ;;
  *) dispatch "$1" ;;
esac
