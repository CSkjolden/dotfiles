# Shared by the SketchyBar plugins; source it with `. "$(dirname "$0")/lib.sh"` from a script run by path.
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.cache/sketchybar"
ICON_DIR="$DIR/icons"

# Items with no visuals of their own.
BARE="icon.drawing=off label.drawing=off padding_left=0 padding_right=0"

# Rounded background shared by every pill.
PILL="background.drawing=on background.color=0x22ffffff background.height=24 background.corner_radius=12"

# Floating container behind each side of the bar; the bar itself is transparent.
CONTAINER="background.drawing=on background.color=0xd0181825 background.height=28 background.corner_radius=14 background.border_width=1 background.border_color=0x22ffffff"

# Pill geometry: inset before the first icon and the width of one icon slot.
INSET=9 SLOT=27

# Workspace icon variants are the symbol rendered at this opacity (see sfsymbol.swift).
ACTIVE=100 NORMAL=70 EMPTY=30

# App icons shown in the active workspace pill: how many fit, and the width of one (icon is 18pt plus a gap).
APPSLOTS=5 APPSLOT=26 APPDIM=55

# Invisible item that only takes up space; extra arguments are passed to --set.
# sh has no locals, so helpers use _-prefixed names to leave the caller's variables alone.
add_spacer() {
  _item="$1" _side="$2" _width="$3"; shift 3
  sketchybar --add item "$_item" "$_side" --set "$_item" $BARE width="$_width" "$@"
}

# Item that draws a PNG as its background. Images sit at the item's left edge, so width sets the right inset.
add_icon() {
  _item="$1" _side="$2" _width="$3" _image="$4"; shift 4
  sketchybar --add item "$_item" "$_side" \
    --set "$_item" $BARE width="$_width" background.drawing=on background.color=0x0 \
      background.image.scale=0.5 ${_image:+background.image="$_image"} "$@"
}

# Items of one workspace pill: inset, icon, a label shown only when active and slots for the active pill's app icons.
# Arguments: index, name, icon path prefix (without variant), click command.
add_workspace() {
  _i="$1" _name="$2" _icon="$3" _click="$4"

  add_spacer "ws.$_i.pad" left $INSET click_script="$_click"
  add_icon "ws.$_i" left $SLOT "$_icon.$NORMAL.png" click_script="$_click"
  sketchybar \
    --add item "ws.$_i.label" left \
    --set "ws.$_i.label" $BARE drawing=off click_script="$_click" \
      label="${_name#[0-9]-}" label.drawing=on label.padding_right=10

  _k=1
  while [ "$_k" -le "$APPSLOTS" ]; do
    add_icon "ws.$_i.app.$_k" left $APPSLOT "" drawing=off
    _k=$((_k + 1))
  done
}

# Names of the items of workspace pill $1.
workspace_members() {
  printf 'ws.%s.pad ws.%s ws.%s.label' "$1" "$1" "$1"
  _k=1
  while [ "$_k" -le "$APPSLOTS" ]; do
    printf ' ws.%s.app.%s' "$1" "$_k"
    _k=$((_k + 1))
  done
}

# The bracket draws the active pill. Brackets paint in creation order, so create these after the container.
add_workspace_pill() {
  sketchybar \
    --add bracket "ws.$1.bg" $(workspace_members "$1") \
    --set "ws.$1.bg" $PILL background.drawing=off background.color=0x33ffffff
}

# Skips no-op updates, because image reloads flash. Succeeds only when $2 differs from the last value saved under $1.
changed() {
  [ "$2" = "$(cat "$DIR/$1.state" 2>/dev/null)" ] && return 1
  printf '%s' "$2" > "$DIR/$1.state"
}

reset_state() {
  rm -f "$DIR/$1.state"
}

# Render PNGs for names not cached yet with a swift script; first run takes a few seconds to compile.
# Arguments: script, file name prefix, names.
ensure_images() {
  _script="$1" _prefix="$2"; shift 2
  mkdir -p "$ICON_DIR"
  _missing=""
  for _name in "$@"; do
    [ -f "$ICON_DIR/$_prefix$_name.100.png" ] || _missing="$_missing $_name"
  done
  [ -z "$_missing" ] || /usr/bin/swift "$PLUGIN_DIR/$_script" "$ICON_DIR" $_missing
}

ensure_icons() { ensure_images sfsymbol.swift "" "$@"; } # White SF Symbols
ensure_app_icons() { ensure_images appicon.swift app. "$@"; } # App icons by bundle id

# Plugins take `setup` from sketchybarrc and no argument from their item's update script.
dispatch() {
  if [ "$1" = setup ]; then setup; else update; fi
}
