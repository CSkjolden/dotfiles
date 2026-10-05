# Shared by the SketchyBar plugins; source it with `. "$(dirname "$0")/lib.sh"` from a script run by path.
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.cache/sketchybar"
ICON_DIR="$DIR/icons"

# Items with no visuals of their own.
BARE="icon.drawing=off label.drawing=off padding_left=0 padding_right=0"

# Rounded background shared by every pill.
PILL="background.drawing=on background.color=0x22ffffff background.height=24 background.corner_radius=12"

# Pill geometry: space between pills, inset before the first icon, and the width of one icon slot.
GAP=6 INSET=9 SLOT=27

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

# Skips no-op updates, because image reloads flash. Succeeds only when $2 differs from the last value saved under $1.
changed() {
  [ "$2" = "$(cat "$DIR/$1.state" 2>/dev/null)" ] && return 1
  printf '%s' "$2" > "$DIR/$1.state"
}

reset_state() {
  rm -f "$DIR/$1.state"
}

# Render white PNGs for SF Symbols not cached yet; first run takes a few seconds for swift to compile.
ensure_icons() {
  mkdir -p "$ICON_DIR"
  missing=""
  for symbol in "$@"; do
    [ -f "$ICON_DIR/$symbol.100.png" ] || missing="$missing $symbol"
  done
  [ -z "$missing" ] || /usr/bin/swift "$PLUGIN_DIR/sfsymbol.swift" "$ICON_DIR" $missing
}

# Extract app icons for bundle ids not cached yet.
ensure_app_icons() {
  mkdir -p "$ICON_DIR"
  missing=""
  for id in "$@"; do
    [ -f "$ICON_DIR/app.$id.png" ] || missing="$missing $id"
  done
  [ -z "$missing" ] || /usr/bin/swift "$PLUGIN_DIR/appicon.swift" "$ICON_DIR" $missing
}

# Plugins take `setup` from sketchybarrc and no argument from their item's update script.
dispatch() {
  if [ "$1" = setup ]; then setup; else update; fi
}
