#!/usr/bin/env bash
# Drives two items: "date" (dim, "mar 20 oct", in Spanish) and "clock" (bold, "12:29"). Mouse events go to hover.sh.
case "$SENDER" in mouse.*) exec "$CONFIG_DIR/plugins/hover.sh" ;; esac

DAYS=(dom lun mar mié jue vie sáb)
MONTHS=(ene feb mar abr may jun jul ago sep oct nov dic)
read -r wd day month hm <<<"$(date '+%w %-d %-m %H:%M')"

case "$NAME" in
date) sketchybar --set "$NAME" label="${DAYS[wd]} $day ${MONTHS[month - 1]}" ;;
*) sketchybar --set "$NAME" label="$hm" ;;
esac
