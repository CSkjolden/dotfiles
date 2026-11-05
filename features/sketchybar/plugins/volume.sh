#!/bin/sh
. "$(dirname "$0")/lib.sh"

setup() {
  reset_state volume
  ensure_icons speaker.wave.2.fill speaker.slash.fill

  add_icon volume right 18 "$ICON_DIR/speaker.wave.2.fill.100.png" update_freq=2 script="sh $0"
  sketchybar --subscribe volume volume_change system_woke
}

update() {
  muted="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)" || return
  if [ "$muted" = true ]; then symbol=speaker.slash.fill
  else symbol=speaker.wave.2.fill
  fi

  changed volume "$symbol" || return
  sketchybar --set volume background.image="$ICON_DIR/$symbol.100.png"
}

dispatch "$1"