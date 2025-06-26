#!/sbin/tini /bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2021 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2023 Cisco Systems, Inc. and/or its affiliates. All rights reserved.
#
# A beginning user should be able to `docker run IMAGE bash` (or sh) without
# needing to learn about --entrypoint
# https://github.com/docker-library/official-images#consistency

set -eu

if [ ! -d "/run/clamav" ]; then
	install -d -g "clamav" -m 775 -o "clamav" "/run/clamav"
fi

# Assign ownership to the database directory, just in case it is a mounted volume
chown -R clamav:clamav /var/lib/clamav

# configure freshclam.conf and clamd.conf from env variables if present
env | grep "^CLAMD_CONF_" | while IFS="=" read -r KEY VALUE; do
    TRIMMED="${KEY#CLAMD_CONF_}"

    grep -q "^#$TRIMMED " /etc/clamav/clamd.conf && \
        sed -i "s/^#$TRIMMED .*/$TRIMMED $VALUE/" /etc/clamav/clamd.conf || \
        sed -i "\$ a\\$TRIMMED $VALUE" /etc/clamav/clamd.conf
done

env | grep "^FRESHCLAM_CONF_" | while IFS="=" read -r KEY VALUE; do
    TRIMMED="${KEY#FRESHCLAM_CONF_}"

    grep -q "^#$TRIMMED " /etc/clamav/freshclam.conf && \
        sed -i "s/^#$TRIMMED .*/$TRIMMED $VALUE/" /etc/clamav/freshclam.conf || \
        sed -i "\$ a\\$TRIMMED $VALUE" /etc/clamav/freshclam.conf
done

SCRIPT_FILE="$(basename "$0")"
CLAMD_STARTUP_TIMEOUT="${CLAMD_STARTUP_TIMEOUT:-1800}"

# ---------------------------------------------------------------------------
# signal handling – make sure all background daemons die cleanly
# ---------------------------------------------------------------------------
child_pids=""

terminate_children() {
    if [ -n "${child_pids}" ]; then
        echo "[${SCRIPT_FILE}] Caught termination signal, stopping children: ${child_pids}"
        # Send SIGTERM first, then SIGKILL after a grace period if still running
        echo "[${SCRIPT_FILE}] Sending SIGTERM"
        kill -TERM ${child_pids} 2>/dev/null || true
        sleep 5
        # Check if any children are still running
        for pid in ${child_pids}; do
            if kill -0 "${pid}" 2>/dev/null; then
                echo "[${SCRIPT_FILE}] Child ${pid} is still running, sending SIGKILL"
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        done
    fi
    echo "[${SCRIPT_FILE}] All children terminated, exiting."
    exit 0
}
trap terminate_children INT TERM

# ---------------------------------------------------------------------------
# fast-path: run arbitrary executable
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ] && [ "${1#-}" = "${1}" ] && command -v "$1" >/dev/null 2>&1; then
    # exec replaces the shell (and tini) with the given command, so we exit the script here.
    # As this will be the new PID 1, it will also receive the signals directly
    exec "$@"
fi

# ---------------------------------------------------------------------------
# alternative path: flags → clamd
# ---------------------------------------------------------------------------
if [ "$#" -ge 1 ] && [ "${1#-}" != "${1}" ]; then
    # same as above, but we treat the arguments (starting with "-") as flags to clamd
    exec clamd "$@"
fi

# ---------------------------------------------------------------------------
# default path: launch daemons
# ---------------------------------------------------------------------------

# Create symlink of the lock directory to standard location
mkdir -p "/run/lock"
ln -f -s "/run/lock" "/var/lock"

# Ensure initial virus database exists, otherwise clamd refuses to start
echo "[${SCRIPT_FILE}] Updating initial database"
# Set "TestDatabases no" and remove "NotifyClamd" for initial download
sed -e 's|^\(TestDatabases \)|\#\1|' \
    -e '$a TestDatabases no' \
    -e 's|^\(NotifyClamd \)|\#\1|' \
    /etc/clamav/freshclam.conf > /tmp/freshclam_initial.conf
freshclam --foreground --stdout --config-file=/tmp/freshclam_initial.conf
rm /tmp/freshclam_initial.conf

# Start clamd (optional, enabled by default)
if [ "${CLAMAV_NO_CLAMD:-false}" != "true" ]; then
    echo "[${SCRIPT_FILE}] Starting clamd"
    [ -S /run/clamav/clamd.sock ] && unlink /run/clamav/clamd.sock
    [ -S /tmp/clamd.sock ] && unlink /tmp/clamd.sock

    clamd --foreground &
    clamd_pid="$!"
    child_pids="${child_pids} $!"

    # Wait for socket
    elapsed=0
    until [ -S "/run/clamav/clamd.sock" ] || [ -S "/tmp/clamd.sock" ]; do
        if [ "${elapsed}" -ge "${CLAMD_STARTUP_TIMEOUT}" ]; then
            echo >&2 "[${SCRIPT_FILE}] Failed to start clamd (socket not found)"
            kill -TERM "${clamd_pid}" 2>/dev/null || true
            exit 1
        fi
        [ $((elapsed % 5)) -eq 0 ] && \
            printf "[%s] Waiting for clamd socket... (%s/%s)s\n" "${SCRIPT_FILE}" "${elapsed}" "${CLAMD_STARTUP_TIMEOUT}"
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "[${SCRIPT_FILE}] Socket found after ${elapsed}s, clamd started."
fi

# Start freshclam daemon (optional, enabled by default)
if [ "${CLAMAV_NO_FRESHCLAMD:-false}" != "true" ]; then
	echo "[${SCRIPT_FILE}] Starting freshclamd"
    freshclam \
        --checks="${FRESHCLAM_CHECKS:-1}" \
        --daemon \
        --foreground \
        --stdout \
        --user="clamav" &
    child_pids="${child_pids} $!"
fi

# Start milter (optional, disabled by default)
if [ "${CLAMAV_NO_MILTERD:-true}" != "true" ]; then
  echo "[${SCRIPT_FILE}] Starting clamav-milterd"
  clamav-milter &
  child_pids="${child_pids} $!"
fi

# ---------------------------------------------------------------------------
# keep container alive while daemons run
# ---------------------------------------------------------------------------
if [ -n "${child_pids// }" ]; then
    # Wait for *any* child to exit; propagate exit status
    wait -n ${child_pids}
    exit $?
else
    # If nothing started, just exit cleanly
    exit 0
fi
