#!/bin/sh
# Bluetooth | Wi-Fi | battery | clock in one pill on the right.
#   status.sh setup  builds the items (run from sketchybarrc)
. "$(dirname "$0")/lib.sh"

add_separator() {
  sketchybar --add item "$1" right \
    --set "$1" $BARE label.drawing=on label="|" label.color=0x55cdd6f4 \
      label.padding_left=10 label.padding_right=10
}

# Right-side items stack leftwards, so they're added in reverse visual order.
setup() {
  # The edge spacer keeps the pill clear of the macOS screen-recording indicator dot.
  add_spacer status.edge right 24
  sh "$PLUGIN_DIR/clock.sh" setup
  add_separator status.sep.clock
  sh "$PLUGIN_DIR/battery.sh" setup
  add_separator status.sep.network
  sh "$PLUGIN_DIR/network.sh" setup
  add_separator status.sep.bluetooth
  sh "$PLUGIN_DIR/bluetooth.sh" setup
  add_spacer status.pad right 12

  sketchybar --add bracket status.bg status.pad bluetooth.icon bluetooth status.sep.bluetooth \
      network status.sep.network battery.icon battery status.sep.clock clock \
    --set status.bg $PILL
}

dispatch "$1"
