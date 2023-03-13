#!/sbin/tini /bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2021 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2022 Cisco Systems, Inc. and/or its affiliates. All rights reserved.
#
# A beginning user should be able to docker run image bash (or sh) without
# needing to learn about --entrypoint
# https://github.com/docker-library/official-images#consistency

set -u

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

	# Ensure we have some up to date virus data, otherwise clamd refuses to start
	echo "Updating initial database"
	freshclam --foreground --stdout

	if [ "${CLAMAV_NO_FRESHCLAMD:-false}" != "true" ]; then
		echo "Starting Freshclamd"

		while true; do
			ps aux |grep freshclam |grep -q -v grep
			status=$?

			if [ $status -ne 0 ]; then
				freshclam \
						--checks="${FRESHCLAM_CHECKS:-1}" \
						--daemon \
						--foreground \
						--stdout \
						--user="clamav" \
					&
			else
				break;
			fi

			if [ "${_timeout:=0}" -gt "${FRESHCLAM_STARTUP_TIMEOUT:=600}" ]; then
				echo
				echo "Failed to start freshclam"
				exit 1
			fi

			ps aux |grep freshclam |grep -q -v grep
			status=$?
			
			if [ $status -ne 0 ]; then
				echo "freshclam not started yet, retrying (${_timeout}/${FRESHCLAM_STARTUP_TIMEOUT}) ..."
				sleep 3
				_timeout="$((_timeout + 1))"
			fi
		done
	fi

	if [ "${CLAMAV_NO_CLAMD:-false}" != "true" ]; then
		echo "Starting ClamAV"

		if [ -S "/tmp/clamd.sock" ]; then
			unlink "/tmp/clamd.sock"
		fi

		while [ ! -S "/tmp/clamd.sock" ]; do
			ps aux |grep clamd |grep -q -v grep
			status=$?

			if [ $status -ne 0 ]; then
				clamd --foreground &
			fi

			if [ "${_timeout:=0}" -gt "${CLAMD_STARTUP_TIMEOUT:=600}" ]; then
				echo
				echo "Failed to start clamd"
				exit 1
			fi

			echo "Socket for clamd not found yet, retrying (${_timeout}/${CLAMD_STARTUP_TIMEOUT}) ..."
			sleep 3
			_timeout="$((_timeout + 1))"
		done
		echo "socket found, clamd started."
	fi

	if [ "${CLAMAV_NO_MILTERD:-true}" != "true" ]; then
		echo "Starting clamav milterd"
		
		while true; do
			ps aux |grep clamav-milter |grep -q -v grep
			status=$?

			if [ $status -ne 0 ]; then
				clamav-milter &
			else
				break;
			fi

			if [ "${_timeout:=0}" -gt "${MILTER_STARTUP_TIMEOUT:=600}" ]; then
				echo
				echo "Failed to start clamav-milter"
				exit 1
			fi


			ps aux |grep clamav-milter |grep -q -v grep
			status=$?
			
			if [ $status -ne 0 ]; then
				echo "clamav-milter not started yet, retrying (${_timeout}/${MILTER_STARTUP_TIMEOUT}) ..."
				sleep 3
				_timeout="$((_timeout + 1))"
			fi
		done
	fi

	# Wait forever (or until canceled)
	exec tail -f "/dev/null"
fi

exit 0
