#!/bin/sh
# Bluetooth power state and connected devices.
#   bluetooth.sh setup  builds the items (run from status.sh)
#   bluetooth.sh        refreshes them (run by the bluetooth item)
. "$(dirname "$0")/lib.sh"

SYMBOL_ON=dot.radiowaves.left.and.right SYMBOL_OFF=antenna.radiowaves.left.and.right.slash

setup() {
  reset_state bluetooth
  ensure_icons $SYMBOL_ON $SYMBOL_OFF

  # Added right to left, so the label ends up after the icon.
  sketchybar --add item bluetooth right \
    --set bluetooth $BARE label.drawing=on update_freq=10 script="sh $0" \
    --subscribe bluetooth system_woke
  add_icon bluetooth.icon right 18 "$ICON_DIR/$SYMBOL_ON.70.png"
}

# Prints "on" or "off", then up to two connected device names (+N for the rest).
bluetooth_info() {
  system_profiler SPBluetoothDataType -json 2> /dev/null | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)["SPBluetoothDataType"][0]
print("on" if data["controller_properties"]["controller_state"] == "attrib_on" else "off")
names = [next(iter(device)) for device in data.get("device_connected", [])]
print(", ".join(names[:2]) + (" +%d" % (len(names) - 2) if len(names) > 2 else ""))
'
}

update() {
  info="$(bluetooth_info)"
  power="$(printf '%s\n' "$info" | sed -n 1p)"
  label="$(printf '%s\n' "$info" | sed -n 2p)"

  # Dimmed when off, dim-ish when on with nothing connected; a connected device adds room for the label.
  if [ "$power" != on ]; then symbol=$SYMBOL_OFF variant=30 width=18
  elif [ -z "$label" ]; then symbol=$SYMBOL_ON variant=70 width=18
  else symbol=$SYMBOL_ON variant=100 width=26
  fi

  changed bluetooth "$symbol.$variant $label" || return
  sketchybar --set bluetooth.icon background.image="$ICON_DIR/$symbol.$variant.png" width=$width \
    --set bluetooth label="$label"
}

dispatch "$1"
