#!/system/bin/sh

# For running on Android
# Filter and copy upon file event creation trigger
# non slopcoded because i deadass fucking love writing shell scripts
usage() {
    echo "Usage: $0 <target app>"
    echo "Options:"
    echo "  -h, --help = help message"
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Error: expected one argument" >&2
    echo
    usage
    exit 1
fi

ARG="$1"
fsmon="./fsmon-and-arm64"

echo "Monitoring: $ARG"

"$fsmon" -b "/sdcard/fsmontest/" /data/data/"$ARG"/ |
while read action pid file path
do
    echo "pid=[$pid]"
    echo "action=[$action]"
    echo "file=[$file]"
    echo "path=[$path]"
done
