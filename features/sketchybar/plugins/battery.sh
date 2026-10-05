#!/bin/sh
# Battery percentage and time remaining.
#   battery.sh setup  builds the items (run from status.sh)
#   battery.sh        refreshes them (run by the battery item)
. "$(dirname "$0")/lib.sh"

setup() {
  reset_state battery
  ensure_icons battery.100percent battery.75percent battery.50percent battery.25percent \
    battery.0percent battery.100percent.bolt

  # Added right to left, so the label ends up after the icon.
  sketchybar --add item battery right \
    --set battery $BARE label.drawing=on update_freq=60 script="sh $0" \
    --subscribe battery power_source_change system_woke
  add_icon battery.icon right 28 "$ICON_DIR/battery.100percent.100.png"
}

update() {
  info="$(pmset -g batt)"
  percent="$(printf '%s' "$info" | grep -o '[0-9]*%' | head -1)"
  remaining="$(printf '%s' "$info" | grep -o '[0-9]*:[0-9][0-9] remaining' | cut -d' ' -f1)"
  level="${percent%\%}"

  if printf '%s' "$info" | grep -q 'AC Power'; then
    symbol=battery.100percent.bolt
  elif [ "$level" -ge 88 ]; then symbol=battery.100percent
  elif [ "$level" -ge 63 ]; then symbol=battery.75percent
  elif [ "$level" -ge 38 ]; then symbol=battery.50percent
  elif [ "$level" -ge 13 ]; then symbol=battery.25percent
  else symbol=battery.0percent
  fi

  label="$percent${remaining:+ · $remaining}"

  changed battery "$symbol $label" || return
  sketchybar --set battery.icon background.image="$ICON_DIR/$symbol.100.png" \
    --set battery label="$label"
}

dispatch "$1"
