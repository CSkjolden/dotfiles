#!/bin/sh
# Date and time.
#   clock.sh setup  builds the item (run from status.sh)
#   clock.sh        refreshes it (run by the clock item)
. "$(dirname "$0")/lib.sh"

setup() {
  sketchybar --add item clock right \
    --set clock $BARE label.drawing=on label.padding_right=12 update_freq=10 script="sh $0"
}

update() {
  sketchybar --set clock label="$(date '+%a %d %b %H:%M')"
}

dispatch "$1"
