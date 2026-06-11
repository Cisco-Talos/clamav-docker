#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2021 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2023 Cisco Systems, Inc. and/or its affiliates. All rights reserved.
#
# A beginning user should be able to docker run image bash (or sh) without
# needing to learn about --entrypoint
# https://github.com/docker-library/official-images#consistency

set -eu

#
# Create runtime configs in /tmp
# We never modify /etc/clamav
#
CLAMD_RUNTIME_CONF="/tmp/clamd.conf"
FRESHCLAM_RUNTIME_CONF="/tmp/freshclam.conf"

cp /etc/clamav/clamd.conf "${CLAMD_RUNTIME_CONF}"
cp /etc/clamav/freshclam.conf "${FRESHCLAM_RUNTIME_CONF}"

#
# Apply CLAMD_CONF_* environment overrides
#
env | grep "^CLAMD_CONF_" | while IFS="=" read -r KEY VALUE; do
    TRIMMED="${KEY#CLAMD_CONF_}"

    grep -q "^#${TRIMMED} " "${CLAMD_RUNTIME_CONF}" && \
        sed -i "s|^#${TRIMMED} .*|${TRIMMED} ${VALUE}|" "${CLAMD_RUNTIME_CONF}" || \
        sed -i "\$a\\${TRIMMED} ${VALUE}" "${CLAMD_RUNTIME_CONF}"
done

#
# Apply FRESHCLAM_CONF_* environment overrides
#
env | grep "^FRESHCLAM_CONF_" | while IFS="=" read -r KEY VALUE; do
    TRIMMED="${KEY#FRESHCLAM_CONF_}"

    grep -q "^#${TRIMMED} " "${FRESHCLAM_RUNTIME_CONF}" && \
        sed -i "s|^#${TRIMMED} .*|${TRIMMED} ${VALUE}|" "${FRESHCLAM_RUNTIME_CONF}" || \
        sed -i "\$a\\${TRIMMED} ${VALUE}" "${FRESHCLAM_RUNTIME_CONF}"
done


# run command if it is not starting with a "-" and is an executable in PATH
if [ "${#}" -gt 0 ] && \
   [ "${1#-}" = "${1}" ] && \
   command -v "${1}" > "/dev/null" 2>&1; then
	# Ensure healthcheck always passes
	CLAMAV_NO_CLAMD="true" exec "${@}"
else
	if [ "${#}" -ge 1 ] && \
	   [ "${1#-}" != "${1}" ]; then
		# If an argument starts with "-" pass it to clamd specifically
		exec clamd --config-file="${CLAMD_RUNTIME_CONF}" "${@}"
	fi
	# else default to running clamav's servers

	# Ensure we have some virus data, otherwise clamd refuses to start
	if [ ! -f "/var/lib/clamav/main.cvd" ]; then
		echo "Updating initial database"
		# Set "TestDatabases no" and remove "NotifyClamd" for initial download
		sed -e 's|^\(TestDatabases \)|\#\1|' \
			-e '$a TestDatabases no' \
			-e 's|^\(NotifyClamd \)|\#\1|' \
			"${FRESHCLAM_RUNTIME_CONF}" > /tmp/freshclam_initial.conf
		if ! freshclam --foreground --stdout \
               --config-file=/tmp/freshclam_initial.conf; then
      echo "Initial database download failed"
      exit 1
    fi
		rm /tmp/freshclam_initial.conf
	fi

	if [ "${CLAMAV_NO_FRESHCLAMD:-false}" != "true" ]; then
	  echo "Performing startup database update check"
    if ! freshclam \
        --foreground \
        --stdout \
        --config-file="${FRESHCLAM_RUNTIME_CONF}"; then
      echo "freshclam update  failed"
      exit 1
    fi

    echo "Database update check completed"

		echo "Starting Freshclamd"
		freshclam \
		          --checks="${FRESHCLAM_CHECKS:-1}" \
		          --daemon \
		          --foreground \
		          --stdout \
		          --config-file="${FRESHCLAM_RUNTIME_CONF}" \
			  &
	fi

	if [ "${CLAMAV_NO_CLAMD:-false}" != "true" ]; then
		echo "Starting ClamAV"
		if [ -S "/tmp/clamd.sock" ]; then
			unlink "/tmp/clamd.sock"
		fi
		clamd --foreground --config-file="${CLAMD_RUNTIME_CONF}" &
		while [ ! -S "/tmp/clamd.sock" ]; do
			if [ "${_timeout:=0}" -gt "${CLAMD_STARTUP_TIMEOUT:=1800}" ]; then
				echo
				echo "Failed to start clamd"
				exit 1
			fi
			printf "\r%s" "Socket for clamd not found yet, retrying (${_timeout}/${CLAMD_STARTUP_TIMEOUT}) ..."
			sleep 1
			_timeout="$((_timeout + 1))"
		done
		echo "socket found, clamd started."
	fi

	if [ "${CLAMAV_NO_MILTERD:-true}" != "true" ]; then
		echo "Starting clamav milterd"
		clamav-milter &
	fi

	# Wait forever (or until canceled)
	exec tail -f "/dev/null"
fi

exit 0
