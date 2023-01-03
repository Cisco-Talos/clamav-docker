# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2020 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2022 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

# hadolint ignore=DL3007  latest is the latest stable for alpine
FROM index.docker.io/library/alpine:latest AS builder

WORKDIR /src

COPY . /src/

# hadolint ignore=DL3008  We want the latest stable versions
RUN apk update && apk upgrade \
    && \
    apk add --no-cache \
        bsd-compat-headers \
        cmake \
        file \
        fts-dev \
        g++ \
        libtool \
        linux-headers \
        make \
        # Clamav dependencies provided by alpine
        libmilter-dev \
        ncurses-dev \
        # For the tests and for Mussels to build static libs
        python3 \
        py3-pytest \
        py3-pip \
        perl \
        # For building static libraries with Mussels
        git \
        patchelf \
    && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install mussels && \
    python3 -m mussels update && \
    python3 -m mussels cookbook trust -y clamav && \
    python3 -m mussels build clamav_deps -t host-static -r \
    && \
    mkdir -p "./build" && cd "./build" && \
    cmake .. \
        -D CMAKE_BUILD_TYPE="Release"                                                       \
        -D CMAKE_INSTALL_PREFIX="/usr"                                                      \
        -D CMAKE_INSTALL_LIBDIR="/usr/lib"                                                  \
        -D APP_CONFIG_DIRECTORY="/etc/clamav"                                               \
        -D DATABASE_DIRECTORY="/var/lib/clamav"                                             \
        -D ENABLE_CLAMONACC=OFF                                                             \
        -D ENABLE_EXAMPLES=OFF                                                              \
        -D ENABLE_MILTER=ON                                                                 \
        -D ENABLE_MAN_PAGES=OFF                                                             \
        -D ENABLE_STATIC_LIB=ON                                                             \
        -D ENABLE_SHARED_LIB=OFF                                                            \
        -D CMAKE_FIND_PACKAGE_PREFER_CONFIG=TRUE                                            \
        -D CMAKE_PREFIX_PATH="$HOME/.mussels/install/host-static"                           \
        -D CMAKE_MODULE_PATH="$HOME/.mussels/install/host-static/lib/cmake"                 \
        -D JSONC_INCLUDE_DIR="$HOME/.mussels/install/host-static/include/json-c"            \
        -D JSONC_LIBRARY="$HOME/.mussels/install/host-static/lib/libjson-c.a"               \
        -D ENABLE_JSON_SHARED=OFF                                                           \
        -D BZIP2_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                   \
        -D BZIP2_LIBRARY_RELEASE="$HOME/.mussels/install/host-static/lib/libbz2_static.a"   \
        -D CURL_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                    \
        -D CURL_LIBRARY="$HOME/.mussels/install/host-static/lib/libcurl.a"                  \
        -D OPENSSL_ROOT_DIR="$HOME/.mussels/install/host-static"                            \
        -D OPENSSL_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                 \
        -D OPENSSL_CRYPTO_LIBRARY="$HOME/.mussels/install/host-static/lib/libcrypto.a"      \
        -D OPENSSL_SSL_LIBRARY="$HOME/.mussels/install/host-static/lib/libssl.a"            \
        -D LIBXML2_INCLUDE_DIR="$HOME/.mussels/install/host-static/include/libxml2"         \
        -D LIBXML2_LIBRARY="$HOME/.mussels/install/host-static/lib/libxml2.a"               \
        -D PCRE2_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                   \
        -D PCRE2_LIBRARY="$HOME/.mussels/install/host-static/lib/libpcre2-8.a"              \
        -D ZLIB_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                    \
        -D ZLIB_LIBRARY="$HOME/.mussels/install/host-static/lib/libz.a"                     \
        -D LIBCHECK_INCLUDE_DIR="$HOME/.mussels/install/host-static/include"                \
        -D LIBCHECK_LIBRARY="$HOME/.mussels/install/host-static/lib/libcheck.a"             \
    && \
    make DESTDIR="/clamav" -j$(($(nproc) - 1)) install && \
    rm -r \
       "/clamav/usr/lib/pkgconfig/" \
    && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(PidFile\) .*|\1 /tmp/clamd.pid|" \
        -e "s|.*\(LocalSocket\) .*|\1 /tmp/clamd.sock|" \
        -e "s|.*\(TCPSocket\) .*|\1 3310|" \
        -e "s|.*\(TCPAddr\) .*|#\1 0.0.0.0|" \
        -e "s|.*\(User\) .*|\1 clamav|" \
        -e "s|^\#\(LogFile\) .*|\1 /var/log/clamav/clamd.log|" \
        -e "s|^\#\(LogTime\).*|\1 yes|" \
        "/clamav/etc/clamav/clamd.conf.sample" > "/clamav/etc/clamav/clamd.conf" && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(PidFile\) .*|\1 /tmp/freshclam.pid|" \
        -e "s|.*\(DatabaseOwner\) .*|\1 clamav|" \
        -e "s|^\#\(UpdateLogFile\) .*|\1 /var/log/clamav/freshclam.log|" \
        -e "s|^\#\(NotifyClamd\).*|\1 /etc/clamav/clamd.conf|" \
        -e "s|^\#\(ScriptedUpdates\).*|\1 yes|" \
        "/clamav/etc/clamav/freshclam.conf.sample" > "/clamav/etc/clamav/freshclam.conf" && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(PidFile\) .*|\1 /tmp/clamav-milter.pid|" \
        -e "s|.*\(MilterSocket\) .*|\1 inet:7357|" \
        -e "s|.*\(User\) .*|\1 clamav|" \
        -e "s|^\#\(LogFile\) .*|\1 /var/log/clamav/milter.log|" \
        -e "s|^\#\(LogTime\).*|\1 yes|" \
        -e "s|.*\(\ClamdSocket\) .*|\1 unix:/tmp/clamd.sock|" \
        "/clamav/etc/clamav/clamav-milter.conf.sample" > "/clamav/etc/clamav/clamav-milter.conf" || \
    exit 1 \
    && \
    ctest -V

FROM index.docker.io/library/alpine:latest

LABEL maintainer="ClamAV bugs <clamav-bugs@external.cisco.com>"

EXPOSE 3310
EXPOSE 7357

ENV TZ Etc/UTC

RUN apk add --no-cache \
        fts \
        libstdc++ \
        tini \
        tzdata \
        libunwind \
        libmilter \
        ncurses-libs \
    && \
    addgroup -S "clamav" && \
    adduser -D -G "clamav" -h "/var/lib/clamav" -s "/bin/false" -u 100 -S "clamav" && \
    install -d -m 755 -g "clamav" -o "clamav" "/var/log/clamav" && \
    chown -R clamav:clamav /var/lib/clamav

COPY --from=builder "/clamav" "/"
COPY "./scripts/clamdcheck.sh" "/usr/local/bin/"
COPY "./scripts/docker-entrypoint.sh" "/init"

HEALTHCHECK --start-period=6m CMD clamdcheck.sh

ENTRYPOINT [ "/init" ]
