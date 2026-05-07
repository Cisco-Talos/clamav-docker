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

# ============================================================================
# UID/GID Configuration Support
# ============================================================================
# Allow runtime override of UID/GID via environment variables
# Default values match the Dockerfile (1000 for Debian)
CLAMAV_UID="${CLAMAV_UID:-1000}"
CLAMAV_GID="${CLAMAV_GID:-1000}"

# Validation function for UID/GID
validate_uid_gid() {
	# Check if UID is numeric
	if ! echo "${CLAMAV_UID}" | grep -qE '^[0-9]+$'; then
		echo "ERROR: CLAMAV_UID must be numeric, got: ${CLAMAV_UID}" >&2
		return 1
	fi

	# Check if GID is numeric
	if ! echo "${CLAMAV_GID}" | grep -qE '^[0-9]+$'; then
		echo "ERROR: CLAMAV_GID must be numeric, got: ${CLAMAV_GID}" >&2
		return 1
	fi

	# Check UID is not 0 (root)
	if [ "${CLAMAV_UID}" -eq 0 ]; then
		echo "ERROR: CLAMAV_UID cannot be 0 (root)" >&2
		return 1
	fi

	# Check GID is not 0 (root)
	if [ "${CLAMAV_GID}" -eq 0 ]; then
		echo "ERROR: CLAMAV_GID cannot be 0 (root)" >&2
		return 1
	fi

	# Check UID/GID are within reasonable range
	if [ "${CLAMAV_UID}" -gt 65535 ]; then
		echo "WARNING: CLAMAV_UID ${CLAMAV_UID} is unusually high (> 65535)" >&2
	fi

	if [ "${CLAMAV_GID}" -gt 65535 ]; then
		echo "WARNING: CLAMAV_GID ${CLAMAV_GID} is unusually high (> 65535)" >&2
	fi

	return 0
}

# Setup clamav user/group with custom UID/GID if needed
setup_clamav_user() {
	# Only modify if different from default (1000)
	if [ "${CLAMAV_UID}" != "1000" ] || [ "${CLAMAV_GID}" != "1000" ]; then
		echo "INFO: Reconfiguring clamav user: UID=${CLAMAV_UID}, GID=${CLAMAV_GID}"

		# Validate first
		validate_uid_gid || return 1

		# Modify user UID if needed
		if [ "${CLAMAV_UID}" != "1000" ]; then
			usermod -u "${CLAMAV_UID}" clamav || {
				echo "ERROR: Failed to set clamav user UID to ${CLAMAV_UID}" >&2
				return 1
			}
		fi

		# Modify group GID if needed
		if [ "${CLAMAV_GID}" != "1000" ]; then
			groupmod -g "${CLAMAV_GID}" clamav || {
				echo "ERROR: Failed to set clamav group GID to ${CLAMAV_GID}" >&2
				return 1
			}
		fi

		echo "INFO: Successfully reconfigured clamav user with UID=${CLAMAV_UID}, GID=${CLAMAV_GID}"
	else
		echo "INFO: Using default clamav user: UID=1000, GID=1000"
	fi
}

# Call setup function
setup_clamav_user || exit 1

# ============================================================================
# End of UID/GID Configuration
# ============================================================================


if [ ! -d "/run/clamav" ]; then
	echo "INFO: Creating /run/clamav directory"
	install -d -g "${CLAMAV_GID}" -m 775 -o "${CLAMAV_UID}" "/run/clamav"
else
	echo "INFO: Fixing ownership of /run/clamav directory"
	chown "${CLAMAV_UID}:${CLAMAV_GID}" "/run/clamav"
	chmod 775 "/run/clamav"
fi

# Ensure /var/log/clamav exists before chowning
if [ ! -d "/var/log/clamav" ]; then
    install -d -m 755 -g "${CLAMAV_GID}" -o "${CLAMAV_UID}" "/var/log/clamav"
fi
chown -R "${CLAMAV_UID}:${CLAMAV_GID}" /var/lib/clamav /var/log/clamav

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
		exec clamd "${@}"
	fi
	# else default to running clamav's servers

	# Help tiny-init a little
	mkdir -p "/run/lock"
	ln -f -s "/run/lock" "/var/lock"

	# Ensure we have some virus data, otherwise clamd refuses to start
	if [ ! -f "/var/lib/clamav/main.cvd" ]; then
		echo "Updating initial database"
		# Set "TestDatabases no" and remove "NotifyClamd" for initial download
		sed -e 's|^\(TestDatabases \)|\#\1|' \
			-e '$a TestDatabases no' \
			-e 's|^\(NotifyClamd \)|\#\1|' \
			/etc/clamav/freshclam.conf > /tmp/freshclam_initial.conf
		freshclam --foreground --stdout --config-file=/tmp/freshclam_initial.conf
		rm /tmp/freshclam_initial.conf
	fi

	if [ "${CLAMAV_NO_FRESHCLAMD:-false}" != "true" ]; then
		echo "Starting Freshclamd"
		freshclam \
		          --checks="${FRESHCLAM_CHECKS:-1}" \
		          --daemon \
		          --foreground \
		          --stdout \
		          --user="${CLAMAV_UID}" \
			  &
	fi

	if [ "${CLAMAV_NO_CLAMD:-false}" != "true" ]; then
		echo "Starting ClamAV"
		if [ -S "/run/clamav/clamd.sock" ]; then
			unlink "/run/clamav/clamd.sock"
		fi
		if [ -S "/tmp/clamd.sock" ]; then
			unlink "/tmp/clamd.sock"
		fi
		clamd --foreground &
		while [ ! -S "/run/clamav/clamd.sock" ] && [ ! -S "/tmp/clamd.sock" ]; do
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
