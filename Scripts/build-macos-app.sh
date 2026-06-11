#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="Plain Craft Launcher (PCL) macOS"
BUNDLE_ID="${BUNDLE_ID:-com.paipaiio.pcl}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-0}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$ROOT_DIR/Resources/PCLMacIcon.icns"
MS_CLIENT_ID="${PCL_MS_CLIENT_ID:-}"

usage() {
  cat <<USAGE
Usage: Scripts/build-macos-app.sh [options]

Options:
  --install              Install the built app to /Applications after packaging.
  --install-dir PATH     Install to a custom Applications-like directory.
  --configuration NAME   Build configuration, default: ${CONFIGURATION}.
  -h, --help             Show this help.

Environment:
  CONFIGURATION          Build configuration when --configuration is omitted.
  BUNDLE_ID              Bundle identifier, default: com.paipaiio.pcl.
  PCL_MS_CLIENT_ID       Optional Microsoft OAuth client id embedded in Info.plist.
  INSTALL_TO_APPLICATIONS=1
                         Same as --install.
  INSTALL_DIR            Custom install directory when installing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_TO_APPLICATIONS=1
      ;;
    --install-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --install-dir" >&2
        exit 2
      fi
      INSTALL_DIR="$2"
      shift
      ;;
    --configuration)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --configuration" >&2
        exit 2
      fi
      CONFIGURATION="$2"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$INSTALL_TO_APPLICATIONS" in
  1|true|TRUE|yes|YES)
    INSTALL_TO_APPLICATIONS=1
    ;;
  *)
    INSTALL_TO_APPLICATIONS=0
    ;;
esac

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

MS_CLIENT_ID_PLIST=""
if [[ -n "$MS_CLIENT_ID" ]]; then
  MS_CLIENT_ID_PLIST="  <key>PCLMicrosoftClientID</key>
  <string>$(xml_escape "$MS_CLIENT_ID")</string>"
fi

backup_path_for() {
  local install_dir="$1"
  local stamp
  local candidate
  local index=1
  stamp="$(date +%Y%m%d-%H%M%S)"
  candidate="$install_dir/$APP_NAME.backup-$stamp.app"
  while [[ -e "$candidate" ]]; do
    candidate="$install_dir/$APP_NAME.backup-$stamp-$index.app"
    index=$((index + 1))
  done
  printf '%s' "$candidate"
}

install_built_app() {
  local source_app="$1"
  local install_dir="$2"
  local target_app="$install_dir/$APP_NAME.app"
  local temp_app="$DIST_DIR/$APP_NAME.installing.app"
  local backup_app=""

  mkdir -p "$install_dir"
  rm -rf "$temp_app"
  ditto "$source_app" "$temp_app"

  if [[ -e "$target_app" ]]; then
    backup_app="$(backup_path_for "$install_dir")"
    mv "$target_app" "$backup_app"
    echo "Backed up existing app: $backup_app"
  fi

  if ! mv "$temp_app" "$target_app"; then
    rm -rf "$temp_app"
    if [[ -n "$backup_app" && -e "$backup_app" && ! -e "$target_app" ]]; then
      mv "$backup_app" "$target_app"
      echo "Restored previous app after install failure: $target_app" >&2
    fi
    echo "Failed to install app to: $target_app" >&2
    return 1
  fi

  echo "$target_app"
}

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/PCLMac"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing built executable: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/PCLMac"
chmod +x "$MACOS_DIR/PCLMac"
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/PCLMacIcon.icns"
fi
if [[ -f "$ROOT_DIR/README.html" ]]; then
  cp "$ROOT_DIR/README.html" "$RESOURCES_DIR/README.html"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>PCLMac</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>PCLMacIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
$MS_CLIENT_ID_PLIST
</dict>
</plist>
PLIST

echo "$APP_DIR"

if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
  install_built_app "$APP_DIR" "$INSTALL_DIR"
fi
