#!/bin/sh
set -eu

plugin_dir="$(cd "$(dirname "$0")/../plugins" && pwd)"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
HOME="$test_home"
export HOME
. "$plugin_dir/lib.sh"
eval "$(sed '/^\. /d; /^case "\$1" in/,$d' "$plugin_dir/aerospace.sh")"
PLUGIN_DIR="$plugin_dir"
mkdir -p "$DIR" "$ICON_DIR"
printf '1\t1-code\t/icon/code\n2\t2-web\t/icon/web\n' > "$WORKSPACES"
printf '1-code\n2-web\n' > "$DIR/aerospace.occupied"
log="$DIR/calls"
mock_mode=normal
mock_layout=h_tiles
mock_current=1-code
mock_focus_windows=visible

sketchybar() { printf 'bar %s\n' "$*" >> "$log"; }
mock_borders() { printf 'borders %s\n' "$*" >> "$log"; }
mock_as() {
  printf 'query %s\n' "$*" >> "$log"
  case "$mock_mode:$*" in
    unavailable:*) return 1 ;;
    no_window:list-windows*) return 0 ;;
    stale:*--focused*--format*)
      printf '2-web\nnew-request\nrefresh\n' > "$REQUEST"
      printf '11|floating|false\n'
      ;;
    *:list-workspaces*--focused*) printf '%s\n' "$mock_current" ;;
    *:list-workspaces*--empty*) printf '1-code\n2-web\n' ;;
    *:list-windows*--focused*) printf '11|%s|false\n' "$mock_layout" ;;
    *:list-windows*--workspace*)
      if [ "$current" != 6-Focus ]; then
        printf '%s|11|com.example.Editor\n' "$current"
      fi
      if [ "$mock_focus_windows" = visible ]; then
        printf '6-Focus|21|com.example.FocusApp\n'
      fi
      ;;
  esac
}
AS=mock_as
BORDERS=mock_borders
touch "$ICON_DIR/app.com.example.Editor.100.png" "$ICON_DIR/app.com.example.Editor.55.png"
touch "$ICON_DIR/app.com.example.FocusApp.100.png" "$ICON_DIR/app.com.example.FocusApp.55.png"

(
  log="$DIR/setup-calls"
  CONFIG="$plugin_dir/../../aerospace/workspaces.toml"
  ensure_icons() { :; }
  setup
  grep -q 'ws.1.label.*width=0.*label=Code.*label.width=32' "$log"
  grep -q 'ws.2.label.*width=0.*label=Web.*label.width=32' "$log"
  grep -q 'ws.5.label.*label=Misc.*label.width=32' "$log"
  ! grep -q -- '--add item ws.6' "$log"
  [ "$(grep -c -- '--add item apps.[1-5] left' "$log")" -eq "$APPSLOTS" ]
  spaces_line="$(grep -n -- '--add item ws.5.label left' "$log" | cut -d: -f1)"
  layout_line="$(grep -n -- '--add item layout.icon left' "$log" | cut -d: -f1)"
  apps_line="$(grep -n -- '--add item apps.1 left' "$log" | cut -d: -f1)"
  focus_line="$(grep -n -- '--add item focus.1 left' "$log" | cut -d: -f1)"
  [ "$spaces_line" -lt "$layout_line" ] && [ "$layout_line" -lt "$focus_line" ]
  [ "$focus_line" -lt "$apps_line" ]
  grep -q -- '--set focus.icon .*width=27 .*scope.70.png.*workspace.*6-Focus' "$log"
  grep -q -- '--set apps.1 .*width=0' "$log"
  ! grep -q 'ws.[0-9].app.' "$log"
  ! grep -q -- ' drawing=off' "$log"
)
printf '1\t1-code\t/icon/code\n2\t2-web\t/icon/web\n' > "$WORKSPACES"
printf 'PASS setup gives Focus only its own clickable section after Layout and before Active\n'

FOCUSED_WORKSPACE=1-code
update
! grep -q '^query ' "$log"
grep -q -- '--set ws.1.bg background.drawing=on' "$log"
grep -q -- '--set ws.1.label label.drawing=on width=42' "$log"
grep -q -- '--set ws.2.label label.drawing=off width=0' "$log"
printf 'PASS query-free immediate highlight\n'

details
trap 'rm -rf "$test_home"' EXIT
grep -q 'background.image=.*/app.com.example.Editor.100.png' "$log"
grep -q -- '--set apps.1 background.drawing=on width=26' "$log"
grep -q -- '--set apps.2 background.drawing=off click_script= width=0' "$log"
grep -q -- '--set apps.gap width=12 --set apps.pad width=9' "$log"
grep -q -- '--set focus.1 background.drawing=on width=26' "$log"
grep -q 'focus.1 .*app.com.example.FocusApp.55.png.*focus --window-id 21' "$log"
grep -q -- '--set layout.icon background.drawing=on' "$log"
! grep -q 'layout.label' "$log"
grep -q -- "--set layout.direction label.drawing=on label=$(printf '\342\206\224')" "$log"
printf 'PASS layout indicator has an arrow without a layout name\n'
: > "$log"
details
trap 'rm -rf "$test_home"' EXIT
! grep -q '^bar ' "$log"
printf 'PASS per-item caching skips unchanged redraws\n'

for mock_layout in h_accordion v_accordion v_tiles floating; do
  : > "$log"
  details
  trap 'rm -rf "$test_home"' EXIT
  case "$mock_layout" in
    h_*) arrow="$(printf '\342\206\224')" ;;
    v_*) arrow="$(printf '\342\206\225')" ;;
    floating) arrow="" ;;
  esac
  if [ -n "$arrow" ]; then
    grep -q -- "--set layout.direction label.drawing=on label=$arrow" "$log"
  else
    grep -q -- '--set layout.direction label.drawing=off' "$log"
  fi
done
mock_layout=h_tiles
printf 'PASS direction follows horizontal and vertical layouts and hides for floating\n'

mock_mode=no_window
: > "$log"
details
trap 'rm -rf "$test_home"' EXIT
grep -q -- '--set layout.gap width=0 --set layout.pad width=0' "$log"
grep -q -- '--set layout.icon background.drawing=off width=0' "$log"
grep -q -- '--set layout.direction label.drawing=off width=0' "$log"
mock_mode=normal
: > "$log"
details
trap 'rm -rf "$test_home"' EXIT
grep -q -- '--set layout.gap width=8 --set layout.pad width=9' "$log"
grep -q -- '--set layout.icon background.drawing=on width=27' "$log"
printf 'PASS absent layouts collapse completely and restore when a window is focused\n'

touch "$APPICONS_OFF"
: > "$log"
details
trap 'rm -rf "$test_home"' EXIT
grep -q -- '--set apps.1 background.drawing=off click_script=' "$log"
grep -q -- '--set apps.1 .*width=0' "$log"
grep -q -- '--set apps.gap width=0 --set apps.pad width=0' "$log"
! grep -q -- ' drawing=off' "$log"
rm "$APPICONS_OFF"
printf 'PASS hiding app icons collapses the active strip and its padding\n'
[ "$(cat "$DIR/aerospace.item.focus.app.1.state")" = "$ICON_DIR/app.com.example.FocusApp.55.png 21" ]
printf 'PASS Focus icons stay visible independently of the active workspace and icon toggle\n'

: > "$log"
SENDER=aerospace_focus_change
unset FOCUSED_WORKSPACE
update
details
trap 'rm -rf "$test_home"' EXIT
! grep -q -- '--empty no' "$log"
printf 'PASS focus events avoid workspace inventory queries\n'

printf '2-web\n' > "$DIR/aerospace.focused"
unset FOCUSED_WORKSPACE
: > "$log"
update
IFS= read -r requested_workspace < "$REQUEST"
[ "$requested_workspace" = "$mock_current" ]
printf 'PASS focus events cannot restore a stale cached workspace\n'

: > "$log"
SENDER=aerospace_workspace_change
FOCUSED_WORKSPACE=2-web
update
grep -q -- '--set ws.1.bg background.drawing=off' "$log"
grep -q -- '--set apps.1 background.drawing=off click_script=' "$log"
grep -q -- '--set ws.2.bg background.drawing=on' "$log"
grep -q -- '--set ws.1.label label.drawing=off width=0' "$log"
grep -q -- '--set ws.2.label label.drawing=on width=42' "$log"
! grep -q -- ' drawing=off' "$log"
grep -q -- '--set apps.1 .*width=0' "$log"
printf 'PASS switching clears and collapses the active strip\n'

FOCUSED_WORKSPACE=1-code
update
request="$(cat "$REQUEST")"
mock_mode=stale
: > "$log"
refresh
! grep -q '^bar ' "$log"
printf 'PASS superseded detail results are discarded\n'
mock_mode=normal
details
trap 'rm -rf "$test_home"' EXIT
[ "$(cat "$DIR/aerospace.item.app.1.state")" = "$ICON_DIR/app.com.example.Editor.100.png 11" ]
printf 'PASS worker processes the latest pending workspace\n'

mkdir "$LOCK"
printf '%s' "$$" > "$LOCK/pid"
: > "$log"
details
[ ! -s "$log" ]
rm "$LOCK/pid"
rmdir "$LOCK"
printf 'PASS overlapping detail workers do not run\n'

queued=0
queue_icon() { queued=$((queued + 1)); }
rm "$ICON_DIR/app.com.example.Editor.100.png"
reset_state aerospace.item.app.1
request="$(cat "$REQUEST")"
: > "$log"
refresh
[ "$queued" -eq 1 ]
grep -q 'background.image=.*/app.dashed.70.png' "$log"
printf 'PASS missing icons use a placeholder and queue background work\n'

mock_mode=unavailable
unset FOCUSED_WORKSPACE
SENDER=system_woke
: > "$log"
update
grep -q 'ws.ctl update_freq=1' "$log"
printf '9' > "$DIR/aerospace.retry.state"
: > "$log"
update
grep -q 'ws.ctl update_freq=10' "$log"
mock_mode=normal
: > "$log"
update
[ ! -f "$DIR/aerospace.retry.state" ]
grep -q 'ws.ctl update_freq=10' "$log"
printf 'PASS startup retries are bounded and recover\n'

(
  FOCUSED_WORKSPACE=6-Focus
  : > "$log"
  update
  grep -q -- '--set focus.icon .*scope.100.png' "$log"
  : > "$log"
  details
  trap 'rm -rf "$test_home"' EXIT
  grep -q -- '--set apps.gap width=0 --set apps.pad width=0' "$log"
  ! grep -q -- '--set apps.1 background.drawing=on' "$log"
  [ "$(cat "$DIR/aerospace.item.focus.app.1.state")" = "$ICON_DIR/app.com.example.FocusApp.100.png 21" ]
  printf 'PASS active Focus windows are not duplicated in the Active strip\n'
  FOCUSED_WORKSPACE=1-code
  : > "$log"
  update
  grep -q -- '--set focus.icon .*scope.70.png' "$log"
  details
  trap 'rm -rf "$test_home"' EXIT
  [ "$(cat "$DIR/aerospace.item.focus.app.1.state")" = "$ICON_DIR/app.com.example.FocusApp.55.png 21" ]
  printf 'PASS Focus section and window icons dim when Focus is not selected\n'
  mock_focus_windows=empty
  : > "$log"
  details
  trap 'rm -rf "$test_home"' EXIT
  grep -q -- '--set focus.1 background.drawing=off click_script= width=0' "$log"
  ! grep -q -- '--set focus.bg background.drawing=off' "$log"
  ! grep -q -- '--set focus.icon width=0' "$log"
  printf 'PASS empty Focus keeps its dedicated workspace button visible\n'
)