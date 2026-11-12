#!/bin/bash
# Health check: both the Master and the Caves shard must be RUNNING
set -uo pipefail
export LC_ALL=C.UTF-8

status_out="$(supervisorctl status 2>&1)" || { echo "$status_out"; exit 1; }
printf '%s\n' "$status_out"

printf '%s\n' "$status_out" | grep -qE 'dst-server-master[[:space:]]+RUNNING' || exit 1
printf '%s\n' "$status_out" | grep -qE 'dst-server-cave[[:space:]]+RUNNING'   || exit 1
exit 0
