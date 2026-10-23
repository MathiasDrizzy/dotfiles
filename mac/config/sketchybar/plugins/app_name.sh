#!/usr/bin/env bash
# shellcheck disable=SC1091
# The front app's name in a box of fixed width (APP_NAME_WIDTH), so a new name never moves the pills after it. A name that
# fits sits centered; a longer one waits, slides left until its end shows, waits again and slides back, like the old
# now-playing title. SketchyBar animates the slide itself (no loop here); a newer call cancels an older one mid-slide.
source "$CONFIG_DIR/colors.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
OWNER="$CACHE/app_name_owner"
PAD_LEFT=4
PAD_RIGHT=8
FRAMES_PER_POINT=3 # 20 points a second at 60 frames a second
FRAME_RATE=60
HOLD_SECONDS=1.2
END_MARGIN=6 # the slide goes this much further, or the last letter stayed half cut
mkdir -p "$CACHE"
# The box is APP_NAME_WIDTH wide, narrower when fit.sh needs the room.
NAME_WIDTH="$(cat "$CACHE/fit_name_w" 2>/dev/null)"
[ -n "$NAME_WIDTH" ] || NAME_WIDTH="$APP_NAME_WIDTH"

name="$1"
echo $$ >"$OWNER"
mine() { [ "$(cat "$OWNER" 2>/dev/null)" = $$ ]; }

# front_app.measure is an invisible item of width 0 with the same font: it reports the name's own width without moving
# anything on the bar.
sketchybar --set front_app.measure label="$name"
width="$(sketchybar --query front_app.measure | jq -r '.bounding_rects | to_entries[0].value.size[0] | floor')"
span=$((${width:-0} - NAME_WIDTH))

if [ "$span" -le 0 ]; then
  sketchybar --set front_app.name label="$name" label.align=center label.padding_left="$PAD_LEFT" label.padding_right="$PAD_RIGHT"
  exit 0
fi

span=$((span + END_MARGIN))
# The text moves by label.padding_left while label.padding_right grows by the same amount: the box keeps its width.
frames=$((span * FRAMES_PER_POINT))
slide_seconds="$(awk -v f="$frames" -v r="$FRAME_RATE" 'BEGIN { printf "%.2f", f / r }')"
sketchybar --set front_app.name label="$name" label.align=left label.padding_left="$PAD_LEFT" label.padding_right="$PAD_RIGHT"
sleep "$HOLD_SECONDS"
mine || exit 0
sketchybar --animate sin "$frames" --set front_app.name \
  label.padding_left="$((PAD_LEFT - span))" label.padding_right="$((PAD_RIGHT + span))"
sleep "$slide_seconds"
sleep "$HOLD_SECONDS"
mine || exit 0
sketchybar --animate sin "$frames" --set front_app.name label.padding_left="$PAD_LEFT" label.padding_right="$PAD_RIGHT"
