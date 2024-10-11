#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2021 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2023 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

set -eu

DEF_CLAMAV_DOCKER_NAMESPACE="clamav"
DEF_CLAMAV_DOCKER_IMAGE="clamav"
DEF_DOCKER_REGISTRY="registry.hub.docker.com"


usage()
{
	echo "Usage: ${0} [OPTIONS]"
	echo "Update docker images with latest clamav database."
	echo "    -h  Print this usage"
	echo "    -n  Namespace to use to use (default: '${DEF_CLAMAV_DOCKER_NAMESPACE}') [CLAMAV_DOCKER_NAMESPACE]"
	echo "    -i  Image to use to use (default: '${DEF_CLAMAV_DOCKER_IMAGE}') [CLAMAV_DOCKER_IMAGE]"
	echo "    -p  Password for docker registry (file or string) [DOCKER_PASSWD]"
	echo "    -r  Registry to use to push docker images to (default: '${DEF_DOCKER_REGISTRY}') [DOCKER_REGISTRY]"
	echo "    -t  Tag(s) WITH _base suffix to update (default: all tags)"
	echo "    -u  Username for docker registry [DOCKER_USER]"
	echo
	echo "Options that can also be passed in environment variables listed between [BRACKETS]."
}

init()
{
	if [ -z "${clamav_docker_user:-}" ] ||
           [ -z "${clamav_docker_passwd:-}" ]; then
		echo "No username or password set, skipping login"
		return
	fi

	docker --version

	if [ -f "${clamav_docker_passwd}" ]; then
		_passwd="$(cat "${clamav_docker_passwd}")"
	fi
	echo "${_passwd:-${clamav_docker_passwd}}" | \
	docker login \
		--password-stdin \
		--username "${clamav_docker_user}" \
		"${docker_registry}"
}

cleanup()
{
	if [ -z "${clamav_docker_user:-}" ]; then
		echo "No username set, skipping logout"
		return
	fi

	docker logout "${docker_registry:-}"
}

docker_tags_get()
{
	_tags="$(wget -q -O - "https://${docker_registry}/v2/namespaces/${clamav_docker_namespace}/repositories/${clamav_docker_image}/tags" |
	         sed -e 's|[][]||g' -e 's|"||g' -e 's| ||g' | \
		     tr '}' '\n' | \
		     sed -n -e 's|.*name:\(.*\)$|\1|p')"

	echo "Tags:"
	echo "${_tags}"

	for _tag in ${_tags}; do
		# Only get the tags that have the _base suffix
		if [ "${_tag%%_base}" != "${_tag}" ]; then
			clamav_docker_tags="${_tag} ${clamav_docker_tags:-}"
		fi
	done

	echo "Tags:"
	echo "${clamav_docker_tags}"
}

clamav_db_update()
{
	if [ -z "${clamav_docker_tags:-}" ]; then
		echo "No tags to update with, cannot continue."
		exit 1
	fi

	for _tag in ${clamav_docker_tags}; do
		{
			# Starting with the image tag with the _base suffix
			echo "FROM ${docker_registry}/${clamav_docker_namespace}/${clamav_docker_image}:${_tag}"
			# Update the database
			echo "RUN freshclam --foreground --stdout && rm /var/lib/clamav/freshclam.dat || rm /var/lib/clamav/mirrors.dat || true"
		} | \
		# Pull and Build the updated image with the tag without the _base suffix.
    docker build --sbom=true --provenance mode=max,builder-id="${BUILD_URL}" \
       --annotation "org.opencontainers.image.url=${REPOSITORY}" \
       --annotation "org.opencontainers.image.source=${REPOSITORY}" \
       --annotation "org.opencontainers.image.version=${FULL_VERSION}" \
       --annotation "org.opencontainers.image.ref.name=${BRANCH}" \
       --annotation "org.opencontainers.image.created=$(date -Iseconds)" \
       --pull --push --rm --tag "${docker_registry}/${clamav_docker_namespace}/${clamav_docker_image}:${_tag%%_base}" -
	done
}

main()
{
	_start_time="$(date "+%s")"

	while getopts ":hi:n:p:r:t:u:" _options; do
		case "${_options}" in
		h)
			usage
			exit 0
			;;
		i)
			clamav_docker_image="${OPTARG}"
			;;
		n)
			clamav_docker_namespace="${OPTARG}"
			;;
		p)
			clamav_docker_passwd="${OPTARG}"
			;;
		r)
			docker_registry="${OPTARG}"
			;;
		t)
			clamav_docker_tag="${OPTARG}"
			;;
		u)
			clamav_docker_user="${OPTARG}"
			;;
		:)
			>&2 echo "Option -${OPTARG} requires an argument."
			exit 1
			;;
		?)
			>&2 echo "Invalid option: -${OPTARG}"
			exit 1
			;;
		esac
	done
	shift "$((OPTIND - 1))"

	clamav_docker_namespace="${clamav_docker_namespace:-${CLAMAV_DOCKER_NAMESPACE:-${DEF_CLAMAV_DOCKER_NAMESPACE}}}"
	clamav_docker_image="${clamav_docker_image:-${CLAMAV_DOCKER_IMAGE:-${DEF_CLAMAV_DOCKER_IMAGE}}}"
	clamav_docker_passwd="${clamav_docker_passwd:-${DOCKER_PASSWD:-}}"
	clamav_docker_tag="${clamav_docker_tag:-}"
	clamav_docker_user="${clamav_docker_user:-${DOCKER_USER:-}}"
	docker_registry="${docker_registry:-${DOCKER_REGISTRY:-${DEF_DOCKER_REGISTRY}}}"

	init

	if [ -n "${clamav_docker_tag}" ]; then
		clamav_docker_tags="${clamav_docker_tag}"
	else
		docker_tags_get
	fi

	clamav_db_update

	echo "==============================================================================="
	echo "Build report for $(date -u)"
	echo
	echo "Updated database for image tags ..."
	echo "${clamav_docker_tags:-}"
	echo
	echo "... successfully in $(($(date "+%s") - _start_time)) seconds"
	echo "==============================================================================="

	cleanup
}

main "${@}"

exit 0
