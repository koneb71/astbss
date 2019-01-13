#!/bin/bash

# Thanks to https://andrius.mobi/ Andrius Kairiukstis
# https://github.com/andrius/asterisk
# https://github.com/andrius/asterisk/tree/master/debian-stretch-slim-13-current

PROGNAME=$(basename $0)

if test -z ${ASTERISK_VERSION}; then
    echo "${PROGNAME}: ASTERISK_VERSION required" >&2
    exit 1
fi

set -ex
# set -e stops the execution of a script if a command or pipeline has an error
# set -x to see debug output.

useradd --system asterisk

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests \
    autoconf \
    binutils-dev \
    build-essential \
    ca-certificates \
    curl \
    file \
    libcurl4-openssl-dev \
    libedit-dev \
    libgsm1-dev \
    libjansson-dev \
    libogg-dev \
    libpopt-dev \
    libresample1-dev \
    libspandsp-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libsqlite3-dev \
    libsrtp0-dev \
    libssl-dev \
    libvorbis-dev \
    libxml2-dev \
    libxslt1-dev \
    portaudio19-dev \
    unixodbc \
    unixodbc-bin \
    unixodbc-dev \
    odbcinst \
    uuid \
    uuid-dev \
    xmlstarlet

apt-get purge -y --auto-remove
rm -rf /var/lib/apt/lists/*

mkdir -p /usr/src/asterisk
cd /usr/src/asterisk

curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz || \
curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz || \
curl -vsL http://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-${ASTERISK_VERSION}.tar.gz | tar --strip-components 1 -xz

# 1.5 jobs per core works out okay
: ${JOBS:=$(( $(nproc) + $(nproc) / 2 ))}

# format_mp3 - Download MP3 decoder library 
contrib/scripts/get_mp3_source.sh

./configure  --with-resample --with-pjproject-bundled
make menuselect/menuselect menuselect-tree menuselect.makeopts

# disable BUILD_NATIVE to avoid platform issues on Docker, EC2 and different Virtual instances
menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts
# menuselect/menuselect --enable STATIC_BUILD menuselect.makeopts
# menuselect/menuselect --enable LOW_MEMORY menuselect.makeopts
  

# enable good things
menuselect/menuselect --enable BETTER_BACKTRACES menuselect.makeopts

# codecs
# menuselect/menuselect --enable codec_opus menuselect.makeopts
# menuselect/menuselect --enable codec_silk menuselect.makeopts

# # download more sounds
# for i in CORE-SOUNDS-EN MOH-OPSOUND EXTRA-SOUNDS-EN; do
#     for j in ULAW ALAW G722 GSM SLN16; do
#         menuselect/menuselect --enable $i-$j menuselect.makeopts
#     done
# done

# we don't need any sounds in docker, they will be mounted as volume
menuselect/menuselect --disable-category MENUSELECT_CORE_SOUNDS
menuselect/menuselect --disable-category MENUSELECT_MOH
menuselect/menuselect --disable-category MENUSELECT_EXTRA_SOUNDS
# menuselect/menuselect --enable EXTRA-SOUNDS-EN-GSM menuselect.makeopts


menuselect/menuselect --enable cdr_csv menuselect.makeopts
menuselect/menuselect --enable format_mp3 menuselect.makeopts
menuselect/menuselect --enable res_config_mysql menuselect.makeopts
menuselect/menuselect --enable app_mysql menuselect.makeopts
# menuselect/menuselect --enable cdr_mysql menuselect.makeopts

menuselect/menuselect --enable app_dahdibarge menuselect.makeopts
menuselect/menuselect --enable app_dahdiras menuselect.makeopts
menuselect/menuselect --enable chan_dahdi menuselect.makeopts
menuselect/menuselect --enable codec_dahdi menuselect.makeopts

# Added 2018-07-09 for asterisk-certified-13.21-cert2
menuselect/menuselect --enable cdr_odbc menuselect.makeopts
menuselect/menuselect --enable chan_sip menuselect.makeopts
# menuselect/menuselect --enable chan_phone menuselect.makeopts
menuselect/menuselect --enable pbx_realtime menuselect.makeopts
menuselect/menuselect --enable res_pjsip_history menuselect.makeopts
menuselect/menuselect --enable res_pjsip_registrar_expire menuselect.makeopts

menuselect/menuselect --enable app_chanisavail menuselect.makeopts
menuselect/menuselect --enable app_mp3 menuselect.makeopts

  
make -j ${JOBS} all
make install

# copy default configs
# cp /usr/src/asterisk/configs/basic-pbx/*.conf /etc/asterisk/
make samples


# Install opus, for some reason menuselect option above does not working
mkdir -p /usr/src/codecs/opus \
  && cd /usr/src/codecs/opus \
  && curl -vsL http://downloads.digium.com/pub/telephony/codec_opus/${OPUS_CODEC}.tar.gz | tar --strip-components 1 -xz \
  && cp *.so /usr/lib/asterisk/modules/ \
  && cp codec_opus_config-en_US.xml /var/lib/asterisk/documentation/

mkdir -p /etc/asterisk/ \
         /var/spool/asterisk/fax

chown -R asterisk:asterisk /etc/asterisk \
                           /var/*/asterisk \
                           /usr/*/asterisk
chmod -R 750 /var/spool/asterisk

cd /
rm -rf /usr/src/asterisk \
       /usr/src/codecs

# remove *-dev packages
devpackages=`dpkg -l|grep '\-dev'|awk '{print $2}'|xargs`
DEBIAN_FRONTEND=noninteractive apt-get --yes purge \
  autoconf \
  build-essential \
  bzip2 \
  cpp \
  m4 \
  make \
  patch \
  perl \
  perl-modules \
  pkg-config \
  xz-utils \
  ${devpackages}
rm -rf /var/lib/apt/lists/*

exec rm -f /build-asterisk.sh
