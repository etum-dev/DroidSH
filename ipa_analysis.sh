#!/bin/bash
# str8 copy from mobile hacking labs
# Check if an IPA file was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <path_to_ipa_file>"
  exit 1
fi

IPA_FILE="$1"

# Check if the IPA file exists
if [ ! -f "$IPA_FILE" ]; then
  echo "[@] Error: IPA file not found!"
  exit 1
fi

# Get the app name from the IPA file
APP_NAME="$(basename ""$IPA_FILE"" .ipa)"
OUTPUT_DIR="$(dirname ""$IPA_FILE"" | xargs readlink -f)"

# Create output directory
OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
mkdir -p "$OUTPUT_DIR"

# Unzip the IPA contents
UNZIP_DIR="$OUTPUT_DIR/_extracted"
echo "[*] Extracting IPA contents..."
mkdir -p "$UNZIP_DIR"
unzip -q "$IPA_FILE" -d "$UNZIP_DIR"

# Locate the .app directory
APP_PATH=$(find "$UNZIP_DIR" -name "*.app" -type d)

if [ -z "$APP_PATH" ]; then
  echo "[@] No .app found in $UNZIP_DIR, exiting..."
  exit 1
fi

BINARY="$APP_PATH/$(basename ""$APP_PATH"" .app)"

# Check if the binary exists (file without an extension in the .app folder)
if [ ! -f "$BINARY" ]; then
  echo "[@] No binary found in $APP_PATH, exiting..."
  exit 1
fi

# Create directories for class dumps
CLASS_DUMP_OUTPUT="$OUTPUT_DIR/class_dump"
SWIFT_DUMP_OUTPUT="$OUTPUT_DIR/swift_dump"
mkdir -p "$CLASS_DUMP_OUTPUT"
mkdir -p "$SWIFT_DUMP_OUTPUT"

# Dump Objective-C classes using class-dump
echo "[*] Dumping Objective-C classes for $APP_NAME..."
ipsw class-dump "$BINARY" --headers -o "$CLASS_DUMP_OUTPUT"

# Dump Swift classes using swift-dump
echo "[*] Dumping Swift classes for $APP_NAME..."
ipsw swift-dump "$BINARY" > "$SWIFT_DUMP_OUTPUT/$APP_NAME-mangled.txt"
ipsw swift-dump "$BINARY" --demangle > "$SWIFT_DUMP_OUTPUT/$APP_NAME-demangled.txt"

echo "[+] Decompilation completed for $APP_NAME"
