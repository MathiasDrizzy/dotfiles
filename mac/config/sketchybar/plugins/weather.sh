#!/usr/bin/env bash
# The weather box (neutonfoo/dotfiles's item, shorter): the commune you are in and its temperature, "La Florida 13°C".
# Where you are comes from Location Services through CoreLocationCLI when it is installed and allowed; otherwise from the
# network's address, which names the provider's commune, not yours (OpenStreetMap's Nominatim names it, in Spanish). The
# temperature is Apple Weather's, the one the Mac and the iPhone show, read through the Shortcuts shortcut SHORTCUT (Get
# Current Weather, then its Temperature); without it, Open-Meteo's, a different source that can be a degree off. None of
# them needs a key. Offline it keeps the last text.

LOCATE_SECONDS=15                        # CoreLocationCLI waits for a fix (or for the permission dialog) at most this long
USER_AGENT="dotfiles-sketchybar-weather" # Nominatim's usage policy asks every client to name itself
SHORTCUT="Temperatura barra"
SHORTCUT_SECONDS=20 # a shortcut that hangs (a permission dialog) is given up after this long
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
APPLE_OUT="$CACHE/weather_apple" # Shortcuts writes nothing into the system temporary folder: a file there came back empty

here() { # "latitude<TAB>longitude<TAB>commune" (the commune only from Location Services)
  local found
  if command -v CoreLocationCLI >/dev/null 2>&1; then
    found="$(perl -e 'alarm shift; exec @ARGV' "$LOCATE_SECONDS" CoreLocationCLI --format $'%latitude\t%longitude\t%locality' 2>/dev/null)"
    if [[ "$found" =~ ^-?[0-9.]+$'\t'-?[0-9.]+$'\t' ]]; then
      echo "$found"
      return
    fi
  fi
  curl -fsS --max-time 10 'https://wttr.in/?format=j1' 2>/dev/null |
    jq -r '.nearest_area[0] | "\(.latitude)\t\(.longitude)\t"' 2>/dev/null
}

IFS=$'\t' read -r lat lon commune <<<"$(here)"
[ -n "$lat" ] && [ -n "$lon" ] || exit 0
# The network's address has no commune of its own: OpenStreetMap names the one around it.
[ -n "$commune" ] || commune="$(curl -fsS --max-time 10 -A "$USER_AGENT" \
  "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon&zoom=10&accept-language=es" 2>/dev/null |
  jq -r '.address | .city // .town // .village // .county // empty' 2>/dev/null)"
apple_temperature() { # the first number the shortcut outputs ("12 °C", "12,4°"), rounded
  mkdir -p "$CACHE" && rm -f "$APPLE_OUT" || return
  perl -e 'alarm shift; exec @ARGV' "$SHORTCUT_SECONDS" shortcuts run "$SHORTCUT" --output-path "$APPLE_OUT" >/dev/null 2>&1 &&
    grep -Eo -- '-?[0-9]+([.,][0-9]+)?' "$APPLE_OUT" | head -1 | tr , . | awk '{ printf "%d", ($1 < 0 ? $1 - 0.5 : $1 + 0.5) }'
}
temperature="$(apple_temperature)"
[ -n "$temperature" ] || temperature="$(curl -fsS --max-time 10 \
  "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m" 2>/dev/null |
  jq -r '.current.temperature_2m // empty | round' 2>/dev/null)"
[ -n "$temperature" ] || exit 0

sketchybar --set "$NAME" label="${commune:+$commune }${temperature}°C"
