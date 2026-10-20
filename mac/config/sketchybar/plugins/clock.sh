#!/usr/bin/env bash
# Date and time in Spanish, short: "mar 20 oct · 12:16". Mouse events are handled by hover.sh.
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac

DAYS=(dom lun mar mié jue vie sáb)
MONTHS=(ene feb mar abr may jun jul ago sep oct nov dic)
read -r wd day month hm <<<"$(date '+%w %-d %-m %H:%M')"

sketchybar --set "$NAME" label="${DAYS[wd]} $day ${MONTHS[month - 1]} · $hm"
