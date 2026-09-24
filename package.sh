#!/bin/sh
# Build a single-file, self-contained `freecell` executable.
#
# The result needs Erlang/OTP 26 or later on the machine that runs it, but not
# Gleam and not this repository. Ctrl-C handling is baked in; see
# scripts/package.escript.
set -eu

output="${1:-build/freecell}"

gleam export erlang-shipment
exec ./scripts/package.escript build/erlang-shipment "$output"
