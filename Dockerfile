FROM alpine:3.17 AS builder

RUN apk -U add \
        alsa-lib-dev \
        alsa-plugins-pulse \
        autoconf \
        automake \
        avahi-dev \
        build-base \
        dbus \
        ffmpeg-dev \
        git \
        libconfig-dev \
        libgcrypt-dev \
        libplist-dev \
        libressl-dev \
        libsndfile-dev \
        libsodium-dev \
        libtool \
        pipewire-dev \
        mosquitto-dev \
        popt-dev \
        pulseaudio-dev \
        soxr-dev \
        xxd

##### ALAC #####
RUN git clone https://github.com/mikebrady/alac
WORKDIR /alac
RUN autoreconf -i
RUN ./configure
RUN make
RUN make install
WORKDIR /
##### ALAC END #####

##### NQPTP #####
RUN git clone https://github.com/mikebrady/nqptp
WORKDIR /nqptp
RUN autoreconf -i
RUN ./configure
RUN make
WORKDIR /
##### NQPTP END #####

##### SHAIRPORT-SYNC #####
RUN git clone https://github.com/mikebrady/shairport-sync.git
WORKDIR /shairport-sync
WORKDIR /shairport-sync/build
RUN autoreconf -i ../
RUN ../configure --sysconfdir=/etc --with-alsa --with-pa --with-soxr --with-avahi --with-ssl=openssl \
--with-airplay-2 --with-metadata --with-dummy --with-pipe --with-dbus-interface \
--with-mpris-interface --with-mqtt-client \
--with-apple-alac --with-convolution
RUN make
RUN DESTDIR=install make install
WORKDIR /
##### SPS END #####

# Shairport Sync Runtime System
FROM crazymax/alpine-s6:3.17-3.1.1.2

ENV S6_CMD_WAIT_FOR_SERVICES=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

RUN apk -U add \
alsa-lib \
avahi \
avahi-tools \
dbus \
ffmpeg \
glib \
less \
less-doc \
libconfig \
libgcrypt \
libplist \
libpulse \
libressl3.6-libcrypto \
libsndfile \
libsodium \
libuuid \
pipewire \
man-pages \
mandoc \
mosquitto \
popt \
soxr \
jq

# Copy build files.
COPY --from=builder /shairport-sync/build/install/usr/local/bin/shairport-sync /usr/local/bin/shairport-sync
COPY --from=builder /shairport-sync/build/install/usr/local/share/man/man1 /usr/share/man/man1
COPY --from=builder /nqptp/nqptp /usr/local/bin/nqptp
COPY --from=builder /usr/local/lib/libalac.* /usr/local/lib/
COPY --from=builder /shairport-sync/build/install/etc/shairport-sync.conf /etc/
COPY --from=builder /shairport-sync/build/install/etc/shairport-sync.conf.sample /etc/
COPY --from=builder /shairport-sync/build/install/etc/dbus-1/system.d/shairport-sync-dbus.conf /etc/dbus-1/system.d/
COPY --from=builder /shairport-sync/build/install/etc/dbus-1/system.d/shairport-sync-mpris.conf /etc/dbus-1/system.d/

WORKDIR /shairport-sync
COPY ./docker/etc/s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
COPY ./docker/etc/pulse /etc/pulse
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

# Create non-root user for running the container -- running as the user 'shairport-sync' also allows
# Shairport Sync to provide the D-Bus and MPRIS interfaces within the container

RUN addgroup shairport-sync
RUN adduser -D shairport-sync -G shairport-sync

# Add the shairport-sync user to the pre-existing audio group, which has ID 29, for access to the ALSA stuff
RUN addgroup -g 29 docker_audio && addgroup shairport-sync docker_audio && addgroup shairport-sync audio

# Remove anything we don't need.
RUN rm -rf /lib/apk/db/*

# Remove any statically-defined Avahi services, e.g. SSH and SFTP
RUN rm -rf /etc/avahi/services/*.service

# # Add run script that will start SPS
# COPY ./docker/run.sh ./run.sh
# RUN chmod +x /run.sh

# COPY bootstrap.sh /start
# RUN chmod +x /start

WORKDIR /
COPY apply-options.sh apply-options.sh
COPY shairport-sync.conf /etc/shairport-sync.conf

# Add run script that will start SPS
COPY run.sh ./run.sh
RUN chmod +x /run.sh

# ENTRYPOINT ["/start"]
ENTRYPOINT ["/init","./run.sh"]