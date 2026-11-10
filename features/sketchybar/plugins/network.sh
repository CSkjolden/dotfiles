#!/bin/sh
# Wi-Fi / Ethernet indicator.
#   network.sh setup  builds the item (run from status.sh)
#   network.sh        refreshes it (run by the network item)
. "$(dirname "$0")/lib.sh"

setup() {
  reset_state network
  ensure_icons wifi wifi.slash cable.connector

  add_icon network right 18 "$ICON_DIR/wifi.100.png" update_freq=10 script="sh $0"
  sketchybar --subscribe network wifi_change system_woke
}

update() {
  interface="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
  wifi_interface="$(networksetup -listallhardwareports | awk '/Wi-Fi/ { getline; print $2 }')"

  if [ -z "$interface" ]; then symbol=wifi.slash
  elif [ "$interface" = "$wifi_interface" ]; then symbol=wifi
  else symbol=cable.connector
  fi

  changed network "$symbol" || return
  sketchybar --set network background.image="$ICON_DIR/$symbol.100.png"
}

dispatch "$1"
