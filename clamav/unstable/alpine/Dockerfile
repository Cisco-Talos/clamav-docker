# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2020 Olliver Schinagl <oliver@schinagl.nl>
# Copyright (C) 2021-2023 Cisco Systems, Inc. and/or its affiliates. All rights reserved.
ARG BASE_IMAGE=alpine:latest

# hadolint ignore=DL3007  latest is the latest stable for alpine
FROM index.docker.io/library/${BASE_IMAGE} AS builder

WORKDIR /src

COPY . /src/

ARG LIBXML2_VERSION=2.15.4
ARG LIBXML2_SHA256=98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821

# hadolint ignore=DL3008  We want the latest stable versions
RUN apk update && apk upgrade \
    && \
    apk add \
        bsd-compat-headers \
        cmake \
        curl \
        file \
        g++ \
        libtool \
        linux-headers \
        make \
        musl-fts-dev \
        # Clamav dependencies provided by alpine
        bzip2-dev \
        check-dev \
        curl-dev \
        json-c-dev \
        libmilter-dev \
        ncurses-dev \
        openssl-dev \
        pcre2-dev \
        zlib-dev \
        xz \
        # For the tests
        python3 \
        py3-pytest \
        # For Rust/Cargo
        cargo \
        rust \
    && \
    curl -fsSL "https://download.gnome.org/sources/libxml2/2.15/libxml2-${LIBXML2_VERSION}.tar.xz" \
        -o /tmp/libxml2.tar.xz \
    && echo "${LIBXML2_SHA256}  /tmp/libxml2.tar.xz" | sha256sum -c - \
    && mkdir -p /tmp/libxml2-src \
    && tar -xJf /tmp/libxml2.tar.xz -C /tmp/libxml2-src --strip-components=1 \
    && cmake -S /tmp/libxml2-src -B /tmp/libxml2-build \
        -D CMAKE_BUILD_TYPE="Release" \
        -D CMAKE_INSTALL_PREFIX="/opt/libxml2" \
        -D CMAKE_INSTALL_LIBDIR="lib" \
        -D BUILD_SHARED_LIBS=ON \
        -D LIBXML2_WITH_ZLIB=ON \
    && cmake --build /tmp/libxml2-build --parallel \
    && cmake --install /tmp/libxml2-build \
    && rm -rf /tmp/libxml2-src /tmp/libxml2-build /tmp/libxml2.tar.xz \
    && export PKG_CONFIG_PATH="/opt/libxml2/lib/pkgconfig" \
    && export LD_LIBRARY_PATH="/opt/libxml2/lib" \
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
        -D ENABLE_STATIC_LIB=OFF                                                            \
        -D ENABLE_JSON_SHARED=ON                                                            \
        -D LIBXML2_INCLUDE_DIR="/opt/libxml2/include/libxml2"                               \
        -D LIBXML2_LIBRARY="/opt/libxml2/lib/libxml2.so"                                   \
    && \
    make DESTDIR="/clamav" -j$(($(nproc) - 1)) install && \
    rm -r \
       "/clamav/usr/lib/pkgconfig/" \
    && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(LocalSocket\) .*|\1 /tmp/clamd.sock|" \
        -e "s|.*\(TCPSocket\) .*|\1 3310|" \
        -e "s|.*\(TCPAddr\) .*|#\1 0.0.0.0|" \
        -e "s|.*\(User\) .*|\1 clamav|" \
        -e "s|^\#\(LogFile\) .*|\1 /var/log/clamav/clamd.log|" \
        -e "s|^\#\(LogTime\).*|\1 yes|" \
        "/clamav/etc/clamav/clamd.conf.sample" > "/clamav/etc/clamav/clamd.conf" && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(DatabaseOwner\) .*|\1 clamav|" \
        -e "s|^\#\(UpdateLogFile\) .*|\1 /var/log/clamav/freshclam.log|" \
        -e "s|^\#\(NotifyClamd\).*|\1 /etc/clamav/clamd.conf|" \
        -e "s|^\#\(ScriptedUpdates\).*|\1 yes|" \
        "/clamav/etc/clamav/freshclam.conf.sample" > "/clamav/etc/clamav/freshclam.conf" && \
    sed -e "s|^\(Example\)|\# \1|" \
        -e "s|.*\(MilterSocket\) .*|\1 inet:7357|" \
        -e "s|.*\(User\) .*|\1 clamav|" \
        -e "s|^\#\(LogFile\) .*|\1 /var/log/clamav/milter.log|" \
        -e "s|^\#\(LogTime\).*|\1 yes|" \
        -e "s|.*\(\ClamdSocket\) .*|\1 unix:/tmp/clamd.sock|" \
        "/clamav/etc/clamav/clamav-milter.conf.sample" > "/clamav/etc/clamav/clamav-milter.conf" || \
    exit 1 \
    && \
    ctest -V

FROM index.docker.io/library/${BASE_IMAGE}

LABEL maintainer="ClamAV bugs <clamav-bugs@external.cisco.com>"

EXPOSE 3310
EXPOSE 7357

ENV TZ=Etc/UTC

RUN apk update && apk upgrade \
    && \
    apk add \
        fts \
        libstdc++ \
        tini \
        tzdata \
        # Clamav dependencies provided by alpine
        json-c \
        libbz2 \
        libcurl \
        libmilter \
        ncurses-libs \
        pcre2 \
        zlib \
    && \
    rm -rf /var/cache/apk/* && \
    addgroup -S "clamav" && \
    adduser -D -G "clamav" -h "/var/lib/clamav" -s "/bin/false" -u 100 -S "clamav" && \
    install -d -m 755 -g "clamav" -o "clamav" "/var/log/clamav" && \
    chown -R clamav:clamav /var/lib/clamav

COPY --from=builder "/clamav" "/"
COPY --from=builder "/opt/libxml2" "/opt/libxml2"
COPY --from=builder "/opt/libxml2/lib/libxml2.so.16.1.4" "/usr/lib/libxml2.so.16.1.4"
RUN ln -s "libxml2.so.16.1.4" "/usr/lib/libxml2.so.16"
COPY "./scripts/clamdcheck.sh" "/usr/local/bin/"
COPY "./scripts/docker-entrypoint.sh" "/init"
COPY "./scripts/docker-entrypoint-unprivileged.sh" "/init-unprivileged"

HEALTHCHECK --start-period=6m CMD clamdcheck.sh

ENTRYPOINT [ "/init" ]
