#!/bin/sh
# FlashSpace integration: workspace pills, floating-app icons and an unassigned-app count.
#   flashspace.sh setup  builds the items for the active profile (run from sketchybarrc)
#   flashspace.sh        restyles them (run by the ws.ctl item)
. "$(dirname "$0")/lib.sh"
FS=/opt/homebrew/bin/flashspace
WORKSPACES="$DIR/workspaces" # i<TAB>name<TAB>icon path prefix, one line per workspace
TAB="$(printf '\t')"

# Workspace icon variants are the symbol rendered at this opacity (see sfsymbol.swift).
ACTIVE=100 NORMAL=70 EMPTY=30

FLOAT_SLOTS=4
UNASSIGNED_SYMBOL=square.dashed

# --- setup ---

# Active profile's workspaces as name<TAB>symbol. The CLI doesn't expose symbols, so read profiles.toml.
workspace_rows() {
  symbols="$(awk -F"'" -v profile="$($FS get-profile)" '
    /^\[\[profiles\]\]/ { section = "p"; next }
    /^\[\[profiles\.workspaces\]\]/ { section = "w"; next }
    /^\[\[/ { section = "" }
    section == "p" && /^name = / { current = $2 }
    section == "w" && /^name = / { name = $2 }
    section == "w" && /^symbolIconName = / && current == profile { print name "\t" $2 }
  ' "$HOME/.config/flashspace/profiles.toml")"

  $FS list-workspaces | while IFS= read -r name; do
    symbol="$(printf '%s\n' "$symbols" | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')"
    printf '%s\t%s\n' "$name" "${symbol:-circle.fill}"
  done
}

# Inset, icon and a label shown only when active; the bracket draws the active pill.
add_workspace() {
  i="$1" name="$2" icon="$3"
  click="$FS workspace --name '$name'"

  add_spacer "ws.$i.pad" left $INSET click_script="$click"
  add_icon "ws.$i" left $SLOT "$icon.$NORMAL.png" click_script="$click"
  sketchybar \
    --add item "ws.$i.label" left \
    --set "ws.$i.label" $BARE drawing=off click_script="$click" \
      label="$name" label.drawing=on label.padding_right=10 \
    --add bracket "ws.$i.bg" "ws.$i.pad" "ws.$i" "ws.$i.label" \
    --set "ws.$i.bg" $PILL background.drawing=off background.color=0x33ffffff
}

# One icon slot per floating app; update fills and shows them.
add_floating() {
  add_spacer float.gap left $GAP drawing=off
  add_spacer float.pad left $INSET drawing=off

  slots=""
  for n in $(seq "$FLOAT_SLOTS"); do
    add_icon "float.$n" left $SLOT "" drawing=off
    slots="$slots float.$n"
  done

  sketchybar --add bracket float.bg float.pad $slots --set float.bg $PILL background.drawing=off
}

# A count pill for apps that no workspace owns.
add_unassigned() {
  add_spacer unassigned.gap left $GAP drawing=off
  add_spacer unassigned.pad left $INSET drawing=off
  add_icon unassigned left $SLOT "$ICON_DIR/$UNASSIGNED_SYMBOL.$NORMAL.png" drawing=off
  sketchybar \
    --add item unassigned.label left \
    --set unassigned.label $BARE drawing=off label.drawing=on label.padding_right=10 \
    --add bracket unassigned.bg unassigned.pad unassigned unassigned.label \
    --set unassigned.bg $PILL background.drawing=off
}

setup() {
  rows="$(workspace_rows)"
  ensure_icons $(printf '%s\n' "$rows" | cut -f2 | sort -u) "$UNASSIGNED_SYMBOL"
  : > "$WORKSPACES"
  reset_state flashspace

  sketchybar --add event flashspace_workspace_change

  i=0
  printf '%s\n' "$rows" | while IFS="$TAB" read -r name symbol; do
    i=$((i + 1))
    printf '%s\t%s\t%s\n' "$i" "$name" "$ICON_DIR/$symbol" >> "$WORKSPACES"
    add_workspace "$i" "$name" "$ICON_DIR/$symbol"
  done
  add_floating
  add_unassigned

  # Zero-width host for the update script; update_freq catches apps opening and closing.
  add_spacer ws.ctl left 0 update_freq=3 script="sh $0"
  sketchybar --subscribe ws.ctl flashspace_workspace_change
}

# --- update ---
# Everything runs against a scratch dir ($tmp). Styling is collected as one argument per line in
# $tmp/args, then applied in a single batched call, so unchanged state never redraws.

emit() {
  printf '%s\n' "$@" >> "$tmp/args"
}

visibility() {
  if [ "$1" -gt 0 ]; then echo on; else echo off; fi
}

# Shows or hides a pill: its items by drawing, the bracket by its background.
emit_pill() {
  state="$1" name="$2"; shift 2
  for item in "$@"; do
    emit --set "$item" drawing="$state"
  done
  emit --set "$name.bg" background.drawing="$state"
}

# Queries the CLI in parallel: per-workspace apps, floating apps (name,bundle id) and running apps.
fetch() {
  while IFS="$TAB" read -r i name icon; do
    $FS list-apps "$name" > "$tmp/assigned.$i" 2>/dev/null &
    if [ "$name" != "$current" ]; then
      { [ -n "$($FS list-apps "$name" --only-running 2>/dev/null)" ] && echo $NORMAL || echo $EMPTY; } \
        > "$tmp/variant.$i" &
    fi
  done < "$WORKSPACES"
  $FS list-floating-apps --with-bundle-id > "$tmp/floating_ids" 2>/dev/null &
  $FS list-running-apps > "$tmp/running" 2>/dev/null &
  wait

  # Names may contain commas, so split off the bundle id from the right.
  sed 's/,[^,]*$//' "$tmp/floating_ids" > "$tmp/floating"
  sed 's/^.*,//' "$tmp/floating_ids" > "$tmp/floating_bundles"

  # Finder is always running, so it never counts as unassigned.
  { cat "$tmp"/assigned.* "$tmp/floating"; echo Finder; } | sort -u > "$tmp/known"
  grep -vxFf "$tmp/known" "$tmp/running" > "$tmp/unassigned"
}

# Moves unassigned apps into the profile's catch-all workspace (Misc, Miscellaneous), if it has one.
adopt_unassigned() {
  catch_all="$(cut -f2 "$WORKSPACES" | grep -m1 '^Misc')"
  [ -n "$catch_all" ] || return 0

  while IFS= read -r app; do
    $FS assign-app --name "$app" --workspace "$catch_all" --activate false > /dev/null 2>&1
  done < "$tmp/unassigned"
  : > "$tmp/unassigned"
}

emit_workspaces() {
  while IFS="$TAB" read -r i name icon; do
    if [ "$name" = "$current" ]; then
      variant=$ACTIVE state=on
    else
      variant="$(cat "$tmp/variant.$i")" state=off
    fi
    emit --set "ws.$i" background.image="$icon.$variant.png" \
      --set "ws.$i.label" drawing=$state \
      --set "ws.$i.bg" background.drawing=$state
  done < "$WORKSPACES"
}

emit_floating() {
  ensure_app_icons $(cat "$tmp/floating_bundles")
  emit_pill "$(visibility "$(grep -c . "$tmp/floating_bundles")")" float float.gap float.pad

  for n in $(seq "$FLOAT_SLOTS"); do
    id="$(sed -n "${n}p" "$tmp/floating_bundles")"
    if [ -n "$id" ]; then
      emit --set "float.$n" drawing=on background.image="$ICON_DIR/app.$id.png"
    else
      emit --set "float.$n" drawing=off
    fi
  done
}

emit_unassigned() {
  count="$(grep -c . "$tmp/unassigned")"
  emit_pill "$(visibility "$count")" unassigned unassigned.gap unassigned.pad unassigned unassigned.label
  emit --set unassigned.label label="$count"
}

update() {
  # $WORKSPACE comes from the FlashSpace trigger; otherwise ask the CLI.
  current="${WORKSPACE:-$($FS get-workspace 2>/dev/null)}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  fetch
  adopt_unassigned
  : > "$tmp/args"
  emit_workspaces
  emit_floating
  emit_unassigned

  changed flashspace "$(cat "$tmp/args")" || return 0
  set --
  while IFS= read -r arg; do
    set -- "$@" "$arg"
  done < "$tmp/args"
  sketchybar "$@"
}

dispatch "$1"
