#!/bin/sh
# Created by Brian Bergstrand for the iScrobbler project.
# Licensed under the GPL. See gpl.txt for the terms.

PATH="/usr/bin:/bin:"

if [ ! -d ./build ]; then
	echo "Invalid working directory"
	exit 1
fi

BIN=./build/Release # XCode 2.1 default
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
cp ./English.lproj/iPodLimitations.rtf "/Volumes/${VOLUME}/"
cp ./CHANGE_LOG "/Volumes/${VOLUME}"/
ditto -rsrc How\ to\ install\ iScrobbler\ \(OSX\)\ properly\!.webloc "/Volumes/${VOLUME}/"
mkdir "/Volumes/${VOLUME}/REQUIRES 10.3.9 +"
mkdir "/Volumes/${VOLUME}/REQUIRES iTunes 4.7.1 +"
cp ./gpl.txt "/Volumes/${VOLUME}/LICENSE"

hdiutil eject ${DEVICE}

hdiutil convert -imageKey zlib-level=9 -format UDZO -o ~/Desktop/iscrobbler."${VER}".dmg -ov ${IMAGE}

rm ${IMAGE}	
