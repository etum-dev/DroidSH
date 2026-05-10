#!/usr/bin/env bash

if [ -z "$1" ]; then
        echo "enter root folder of extracted ipa"
        read ROOTPATH
fi
if [ -z "$2" ]; then
        echo "enter output for converted plists"
        read OUTPATH
fi

ROOTPATH="${1:-$ROOTPATH}"
OUTPATH="${2:-$OUTPATH}"

function check_tools(){
        if ! command -v plistutil >/dev/null 2>&1
        then
                echo "Install plist plise"
        fi

}
function gather_plists(){
        plistfiles=$(find "$ROOTPATH" -iname "*.plist")
        echo $plistfiles
}

check_tools

# check if folder exists
if [ -d $OUTPATH ]; then
        read -p "Folder already exists, proceed? (Y/N)" YN
        echo #
        if [[ ! "$YN" =~ ^[Yy]$ ]]
        then
                exit 1
        fi
else
#ensure no trailing /"
        mkdir -p "${OUTPATH%/}"
fi

gather_plists
        for x in $plistfiles 
        do
                echo "Yknow what? fuck you *xmls your$x*"
                # outputs to dst folder and names the plist <framework name>CONVERT.plist
                newname="${x##*/}"
                echo $newname
                plistutil -i "$x" -o "$OUTPATH/$newname"
        done
