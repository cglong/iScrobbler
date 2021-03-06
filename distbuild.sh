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
#VOLUME="iScrobbler ${VER}"
VOLUME="iScrobbler"
hdiutil create -megabytes 10 -fs HFS+ -volname "${VOLUME}" -layout SPUD ${IMAGE}
DEVICE=`hdid "${IMAGE}" | sed -n 1p | cut -f1`

cp -pR ${BIN}/iScrobbler.app "/Volumes/${VOLUME}/"
cp ./CHANGE_LOG "/Volumes/${VOLUME}"/
cp ./res/English.lproj/Readme.webarchive "/Volumes/${VOLUME}/"
cp ./res/gpl.txt "/Volumes/${VOLUME}/LICENSE"

ln -sf /Applications "/Volumes/${VOLUME}/Applications"

mkdir "/Volumes/${VOLUME}/hidden"
/Developer/Tools/SetFile -a V "/Volumes/${VOLUME}/hidden"
cp res/bg_DS_Store "/Volumes/${VOLUME}/.DS_Store"
cp res/bg.png "/Volumes/${VOLUME}/hidden/"

cd ~/Desktop

hdiutil eject ${DEVICE}

# UDBZ is 10.4+ only
hdiutil convert -format UDBZ -o ~/Desktop/iscrobbler."${VER}".dmg -ov ${IMAGE}
# hdiutil internet-enable -yes ~/Desktop/iscrobbler."${VER}".dmg

rm ${IMAGE}

cd ~/Desktop
openssl sha1 iscrobbler."${VER}".dmg
