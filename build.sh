#!/bin/bash

#*****************************************************************************#
#    Copyright (C) 2026 Julian Xhokaxhiu                                      #
#                                                                             #
#    This file is part of SummonKit                                           #
#                                                                             #
#    SummonKit is free software: you can redistribute it and\or modify        #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License            #
#                                                                             #
#    SummonKit is distributed in the hope that it will be useful,             #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#*****************************************************************************#

# =============================================================================
# build_app.sh  —  Assembles SummonKit.app from components
#
# Prerequisites:
#   1. Wine runtime extracted from Gcenx build placed at:
#      ./wine_runtime/   (the contents of the tar.xz from Gcenx releases)
#   2. Run this script from the repo root
#
# Usage:
#   ./build_app.sh [--dist /path/to/dist] [--sign "Developer ID Application: Your Name (TEAMID)"]
#
# Output:
#   <dist>/SummonKit.app (defaults to ./dist/SummonKit.app)
# =============================================================================

set -eo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
APP_NAME="SummonKit"
BUNDLE_ID="com.tsunamods.SummonKit"
APP_VERSION="${_APP_VERSION:-0.0.0}"
BUILD_VERSION="${_BUILD_VERSION:-$(date +%s)}"
SIGN_IDENTITY=""
DIST=""

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WINE_BASE="$SCRIPT_DIR/wine_runtime"
WINE_SRC="$WINE_BASE/Contents/Resources/wine"   # resolved later to support multiple archive layouts

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dist)
      DIST="${2:-}"
      if [ -z "$DIST" ]; then
        echo "ERROR: --dist requires a path"
        exit 1
      fi
      shift 2
      ;;
    --sign)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [ -z "$DIST" ]; then
  DIST="$(pwd)/dist"
fi

APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

# ---------------------------------------------------------------------------
# Download and extract Wine runtime if needed
# ---------------------------------------------------------------------------
resolve_wine_src() {
  # Different Wine archives can unpack in different layouts depending on release packaging.
  local candidate
  for candidate in \
    "$WINE_BASE/Contents/Resources/wine" \
    "$WINE_BASE" \
    "$WINE_BASE/Contents/Resources/wine/Contents/Resources/wine"; do
    if [ -f "$candidate/bin/wine" ]; then
      WINE_SRC="$candidate"
      return 0
    fi
  done

  return 1
}

install_dxmt_runtime() {
  local release_api="https://api.github.com/repos/3Shain/dxmt/releases/latest"
  local release_json=""
  local dxmt_url=""
  local dxmt_tag=""
  local tmp_dir=""
  local archive_path=""
  local dxmt_dest_root="$CONTENTS/Resources/dxmt"

  echo "→ Installing latest DXMT runtime files..."

  # Pass the GitHub token when available to avoid API rate-limit 403s on CI.
  local auth_header=""
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
  fi

  if ! release_json=$(curl -fsSL ${auth_header:+-H "$auth_header"} "$release_api"); then
    echo "ERROR: Failed to fetch DXMT latest release metadata"
    exit 1
  fi

  dxmt_tag=$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)

  dxmt_url=$(printf '%s\n' "$release_json" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -E 'builtin.*\.tar\.gz$' \
    | head -n 1)

  if [ -z "$dxmt_url" ]; then
    dxmt_url=$(printf '%s\n' "$release_json" \
      | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | grep -E '\.tar\.gz$' \
      | head -n 1)
  fi

  if [ -z "$dxmt_url" ]; then
    echo "ERROR: Could not find a DXMT .tar.gz asset in latest release"
    exit 1
  fi

  tmp_dir=$(mktemp -d)
  archive_path="$tmp_dir/dxmt.tar.gz"

  cleanup_dxmt_tmp() {
    rm -rf "$tmp_dir"
  }
  trap cleanup_dxmt_tmp RETURN

  echo "   DXMT release: ${dxmt_tag:-latest}"
  echo "   Download URL : $dxmt_url"

  if ! curl -fsSL --progress-bar -o "$archive_path" "$dxmt_url"; then
    echo "ERROR: Failed to download DXMT archive"
    exit 1
  fi

  rm -rf "$dxmt_dest_root"
  mkdir -p "$dxmt_dest_root"

  # Keep the archive layout intact (including version directory such as v0.74/)
  if ! tar -xzf "$archive_path" -C "$dxmt_dest_root"; then
    echo "ERROR: Failed to extract DXMT archive"
    exit 1
  fi

  echo "✓ DXMT runtime files extracted to: $dxmt_dest_root"
}

download_wine_runtime() {
  local release_api="https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest"
  local release_json=""
  local wine_url=""
  local wine_tag=""
  local wine_archive=""

  echo "→ Fetching latest Wine runtime from Gcenx/macOS_Wine_builds..."

  if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is required but not installed"
    exit 1
  fi

  # Pass the GitHub token when available to avoid API rate-limit 403s on CI.
  local auth_header=""
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
  fi

  if ! release_json=$(curl -fsSL ${auth_header:+-H "$auth_header"} "$release_api"); then
    echo "ERROR: Failed to fetch Wine latest release metadata"
    exit 1
  fi

  wine_tag=$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)

  # Prefer wine-staging osx64 builds; fall back to any .tar.xz asset.
  wine_url=$(printf '%s\n' "$release_json" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -E 'wine-staging.*osx64.*\.tar\.xz$' \
    | head -n 1)

  if [ -z "$wine_url" ]; then
    wine_url=$(printf '%s\n' "$release_json" \
      | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
      | grep -E '\.tar\.xz$' \
      | head -n 1)
  fi

  if [ -z "$wine_url" ]; then
    echo "ERROR: Could not find a Wine .tar.xz asset in latest Gcenx release"
    exit 1
  fi

  wine_archive="$SCRIPT_DIR/$(basename "$wine_url")"

  echo "   Wine release : ${wine_tag:-latest}"
  echo "   Download URL : $wine_url"

  if ! curl -fsSL --progress-bar -o "$wine_archive" "$wine_url"; then
    echo "ERROR: Failed to download Wine runtime from: $wine_url"
    exit 1
  fi
  echo "✓ Download complete"

  echo "→ Extracting Wine runtime (this may take a few minutes)..."
  mkdir -p "$WINE_BASE"

  if tar -xf "$wine_archive" -C "$WINE_BASE" --strip-components=1; then
    echo "✓ Extraction complete"
    rm -f "$wine_archive"

    if ! resolve_wine_src; then
      echo "ERROR: Wine runtime extracted but wine binary could not be located"
      echo "Checked under: $WINE_BASE"
      exit 1
    fi

    echo "✓ Resolved Wine runtime path: $WINE_SRC"
  else
    echo "ERROR: Failed to extract Wine runtime"
    rm -f "$wine_archive"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "$WINE_BASE" ]; then
  echo "Wine runtime not found. Downloading..."
  download_wine_runtime
elif ! resolve_wine_src; then
  echo "Wine runtime directory exists but is incomplete. Re-downloading..."
  rm -rf "$WINE_BASE"
  download_wine_runtime
fi

echo "→ Using Wine runtime path: $WINE_SRC"

if [ ! -f "$WINE_SRC/bin/wine" ]; then
  echo "ERROR: wine binary not found in $WINE_SRC/bin/"
  echo "The Wine runtime extraction may have failed. Try manually deleting wine_runtime/ and running this script again."
  exit 1
fi


# ---------------------------------------------------------------------------
# Clean previous build
# ---------------------------------------------------------------------------
echo "→ Cleaning previous build..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" \
         "$CONTENTS/Resources" \
         "$CONTENTS/Resources/wine"

# ---------------------------------------------------------------------------
# Copy Wine runtime
# ---------------------------------------------------------------------------
echo "→ Copying Wine runtime (this may take a moment)..."
cp -r "$WINE_SRC/." "$CONTENTS/Resources/wine/"
echo "   Wine size: $(du -sh "$CONTENTS/Resources/wine" | cut -f1)"

# ---------------------------------------------------------------------------
# Install DXMT runtime (kept as extracted archive layout)
# ---------------------------------------------------------------------------
install_dxmt_runtime

# ---------------------------------------------------------------------------
# Resolve Swift package dependencies
# ---------------------------------------------------------------------------
echo "→ Resolving Swift package dependencies..."
cd "$SCRIPT_DIR"
swift package resolve
echo "   Dependencies resolved."

# ---------------------------------------------------------------------------
# Compile Swift launcher
# ---------------------------------------------------------------------------
echo "→ Compiling Swift launcher via Swift Package Manager (universal: arm64 + x86_64)..."

ARM64_BUILD_PATH="$SCRIPT_DIR/.build-arm64"
X64_BUILD_PATH="$SCRIPT_DIR/.build-x86_64"
UNIVERSAL_BINARY="$SCRIPT_DIR/.build/SummonKit-universal"

rm -rf "$ARM64_BUILD_PATH" "$X64_BUILD_PATH"

swift build -c release --arch arm64 --build-path "$ARM64_BUILD_PATH" 2>&1 | sed 's/^/   [arm64] /'
swift build -c release --arch x86_64 --build-path "$X64_BUILD_PATH" 2>&1 | sed 's/^/   [x86_64] /'

ARM64_BINARY="$ARM64_BUILD_PATH/release/SummonKit"
X64_BINARY="$X64_BUILD_PATH/release/SummonKit"

if [ ! -f "$ARM64_BINARY" ]; then
  echo "ERROR: Build failed — arm64 binary not found at: $ARM64_BINARY"
  exit 1
fi

if [ ! -f "$X64_BINARY" ]; then
  echo "ERROR: Build failed — x86_64 binary not found at: $X64_BINARY"
  exit 1
fi

mkdir -p "$SCRIPT_DIR/.build"
lipo -create -output "$UNIVERSAL_BINARY" "$ARM64_BINARY" "$X64_BINARY"

cp "$UNIVERSAL_BINARY" "$CONTENTS/MacOS/SummonKit"
chmod +x "$CONTENTS/MacOS/SummonKit"

# Embed the rpath so the binary finds Sparkle.framework at runtime inside
# the bundle (Contents/Frameworks/) without needing DYLD_LIBRARY_PATH.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/SummonKit"
echo "   Launcher architectures: $(lipo -archs "$CONTENTS/MacOS/SummonKit")"
echo "   Launcher compiled successfully."

# ---------------------------------------------------------------------------
# Copy Sparkle.framework
# ---------------------------------------------------------------------------
echo "→ Copying Sparkle.framework..."
mkdir -p "$CONTENTS/Frameworks"

SPARKLE_FWK=$(find "$SCRIPT_DIR/.build/artifacts" -name "Sparkle.framework" | head -n 1)
if [ -z "$SPARKLE_FWK" ]; then
  echo "ERROR: Sparkle.framework not found in SPM artifacts under .build/artifacts/"
  exit 1
fi

cp -r "$SPARKLE_FWK" "$CONTENTS/Frameworks/"
echo "   Sparkle.framework copied to Contents/Frameworks/."

# ---------------------------------------------------------------------------
# Copy Info.plist
# ---------------------------------------------------------------------------
echo "→ Writing Info.plist..."
cp "$SCRIPT_DIR/misc/Info.plist" "$CONTENTS/Info.plist"

# Set bundle versions: CFBundleVersion is build metadata (unix timestamp),
# while CFBundleShortVersionString stays semantic (major.minor.patch).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"

# ---------------------------------------------------------------------------
# Copy icon
# ---------------------------------------------------------------------------
echo "→ Writing AppIcon.icns..."
cp "$SCRIPT_DIR/misc/app.icns" "$CONTENTS/Resources/AppIcon.icns"

# ---------------------------------------------------------------------------
# Fix executable permissions on all Wine binaries
# ---------------------------------------------------------------------------
echo "→ Fixing Wine binary permissions..."
find "$CONTENTS/Resources/wine/bin" -type f -exec chmod +x {} \;
find "$CONTENTS/Resources/wine/lib" -name "*.dylib" -type f -exec chmod 755 {} \; 2>/dev/null || true

# ---------------------------------------------------------------------------
# Remove Wine's quarantine attributes (prevents Gatekeeper blocking Wine libs)
# ---------------------------------------------------------------------------
echo "→ Stripping quarantine attributes..."
xattr -cr "$APP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
  echo "→ Signing with: $SIGN_IDENTITY"

  # Sign Wine dylibs first (inside-out signing)
  find "$CONTENTS/Resources/wine/lib" -name "*.dylib" | while read -r lib; do
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/misc/entitlements.plist" "$lib" 2>/dev/null || true
  done

  # Sign Wine binaries
  find "$CONTENTS/Resources/wine/bin" -type f | while read -r bin; do
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/misc/entitlements.plist" "$bin" 2>/dev/null || true
  done

  # Sign Sparkle.framework (inside-out: helpers, then framework itself)
  if [ -d "$CONTENTS/Frameworks/Sparkle.framework" ]; then
    # XPC service bundles
    find "$CONTENTS/Frameworks/Sparkle.framework" -name "*.xpc" | while read -r item; do
      codesign --force --sign "$SIGN_IDENTITY" --options runtime "$item" 2>/dev/null || true
    done
    # Helper app bundles (Autoupdate.app, Updater.app, etc.)
    find "$CONTENTS/Frameworks/Sparkle.framework" -name "*.app" | while read -r item; do
      codesign --force --sign "$SIGN_IDENTITY" --options runtime "$item" 2>/dev/null || true
    done
    # Sign the framework binary directly to avoid the "ambiguous bundle" warning
    # that codesign emits when given the .framework directory itself.
    codesign --force --sign "$SIGN_IDENTITY" --options runtime \
      "$CONTENTS/Frameworks/Sparkle.framework/Versions/Current/Sparkle"
  fi

  # Sign the whole bundle
  codesign \
    --force \
    --options runtime \
    --entitlements "$SCRIPT_DIR/misc/entitlements.plist" \
    --sign "$SIGN_IDENTITY" \
    "$APP"

  echo "   Signed successfully."
  echo ""
  echo "→ To notarize for distribution:"
  echo "   zip -r \"$DIST/SummonKit.zip\" \"$APP\""
  echo "   xcrun notarytool submit \"$DIST/SummonKit.zip\" \\"
  echo "     --apple-id you@email.com \\"
  echo "     --team-id YOURTEAMID \\"
  echo "     --password APP_SPECIFIC_PASS \\"
  echo "     --wait"
  echo "   xcrun stapler staple \"$APP\""
else
  echo "→ Ad-hoc signing with entitlements (required for Apple Silicon)..."

  # Sign Wine dylibs first (inside-out signing)
  find "$CONTENTS/Resources/wine/lib" -name "*.dylib" | while read -r lib; do
    codesign --force --sign - --entitlements "$SCRIPT_DIR/misc/entitlements.plist" "$lib" 2>/dev/null || true
  done

  # Sign Wine binaries
  find "$CONTENTS/Resources/wine/bin" -type f | while read -r bin; do
    codesign --force --sign - --entitlements "$SCRIPT_DIR/misc/entitlements.plist" "$bin" 2>/dev/null || true
  done

  # Sign Sparkle.framework (inside-out: helpers, then framework itself)
  if [ -d "$CONTENTS/Frameworks/Sparkle.framework" ]; then
    # XPC service bundles
    find "$CONTENTS/Frameworks/Sparkle.framework" -name "*.xpc" | while read -r item; do
      codesign --force --sign - --options runtime "$item" 2>/dev/null || true
    done
    # Helper app bundles (Autoupdate.app, Updater.app, etc.)
    find "$CONTENTS/Frameworks/Sparkle.framework" -name "*.app" | while read -r item; do
      codesign --force --sign - --options runtime "$item" 2>/dev/null || true
    done
    # Sign the framework binary directly to avoid the "ambiguous bundle" warning
    # that codesign emits when given the .framework directory itself.
    codesign --force --sign - \
      "$CONTENTS/Frameworks/Sparkle.framework/Versions/Current/Sparkle"
  fi

  # Sign the whole bundle with entitlements (critical for Wine on Apple Silicon)
  codesign \
    --force \
    --sign - \
    --entitlements "$SCRIPT_DIR/misc/entitlements.plist" \
    "$APP"

  echo "   Ad-hoc signed with Wine entitlements."
  echo "   On first launch: Right-click → Open to bypass Gatekeeper."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  ✓ Build complete!"
echo "============================================"
echo ""
echo "  App bundle : $APP"
echo "  Total size : $(du -sh "$APP" | cut -f1)"
echo ""
