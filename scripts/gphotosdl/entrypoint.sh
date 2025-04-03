#!/bin/bash

EXE=/usr/bin/gphotosdl

# If CMD passed is bash, run bash directly
if [[ -n "$1" && "$1" == *"bash"* ]]; then
  exec /bin/bash
fi

# If --addr passed, override default argument
for arg in "${@:2}"; do
  if [[ "$arg" == "-addr"* ]]; then
    exec "${EXE}" "$@"
  fi
done

# If no --addr was passed, run with default argument
exec "${EXE}" -addr "0.0.0.0:80" "$@"