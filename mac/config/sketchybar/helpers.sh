#!/usr/bin/env bash
# Sourced by the plugins. They run on timers and on events, so a command that hangs (a loaded machine, a stuck system
# service) is started again by the next tick while the first one waits: they piled up by the dozens and took the Mac down.
# Every outside command a plugin waits for goes through bounded, which ends it once its time is up (exit 142, SIGALRM).
#   bounded SECONDS command [args...]
#   ctl QUERY [args...]   a ctlcenter query (top, visible, shown) with its own limit
bounded() { /usr/bin/perl -e 'alarm shift; exec @ARGV' "$@"; }
ctl() { bounded 3 "$HOME/.local/bin/ctlcenter" "$@"; }
