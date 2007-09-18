#!/bin/sh
# Created by Brian Bergstrand for the iScrobbler project.
# Licensed under the GPL. See gpl.txt for the terms.

PATH="/usr/bin:/usr/local/bin:/bin:"

if [ ! -d ./build ]; then
	echo "Invalid working directory"
	exit 1
fi

BIN=./build/Release # XCode 2.1 default
if [ ! -z $1 ] && [ "$1" == "-d" ]; then
	BIN=./build/Debug
fi

if [ ! -d ${BIN} ]; then
	BIN=./build/Deployment
	if [ ! -d ${BIN} ]; then
		BIN=./build
	fi
fi

if [ ! -d ${BIN} ]; then
	exit 1
fi

echo "Using ${BIN}/iScrobbler.app, continue?"
read ANS

if [ ! -z ${ANS} ] && [ ${ANS} != 'y' ] && [ ${ANS} != 'Y' ]; then
	exit 2
fi

echo "Enter the iScrobbler version number:"
read VER

IMAGE=/tmp/scrobbuild_$$.dmg
VOLUME="iScrobbler ${VER}"
hdiutil create -megabytes 5 -fs HFS+ -volname "${VOLUME}" ${IMAGE}
DEVICE=`hdid "${IMAGE}" | sed -n 1p | cut -f1`

cp -pR ${BIN}/iScrobbler.app "/Volumes/${VOLUME}/"
cp ./CHANGE_LOG "/Volumes/${VOLUME}"/
cp ./res/English.lproj/Readme.webarchive "/Volumes/${VOLUME}/"
cp ./res/gpl.txt "/Volumes/${VOLUME}/LICENSE"

#create src zipball of HEAD
echo "Exporting source..."
svn export . /tmp/issrc
cd /tmp
zip -qr -9 "${HOME}/Desktop/iscrobbler_src.${VER}.zip" issrc
rm -rf issrc

cd ~/Desktop

hdiutil eject ${DEVICE}

hdiutil convert -imageKey zlib-level=9 -format UDZO -o ~/Desktop/iscrobbler."${VER}".dmg -ov ${IMAGE}
# hdiutil internet-enable -yes ~/Desktop/iscrobbler."${VER}".dmg

rm ${IMAGE}

cd ~/Desktop
openssl sha1 iscrobbler."${VER}".dmg
