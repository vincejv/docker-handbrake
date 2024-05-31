#!/bin/sh

export GTK_A11Y=none
export LIBGL_ALWAYS_SOFTWARE=true

COMMON_ARGS="--config /config"

cd /storage
if [ "${HANDBRAKE_DEBUG:-0}" -eq 1 ]; then
  exec /usr/bin/ghb $COMMON_ARGS --debug >> /config/log/hb/handbrake.debug.log
else
  exec /usr/bin/ghb $COMMON_ARGS
fi
