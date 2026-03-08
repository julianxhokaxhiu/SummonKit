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

set -euo pipefail

export _BUILD_VERSION="$(date +%s)"

if [[ "$_BUILD_BRANCH" == "refs/heads/master" || "$_BUILD_BRANCH" == "refs/tags/canary" ]]; then
  export _IS_BUILD_CANARY="true"
  export _IS_GITHUB_RELEASE="true"
elif [[ "$_BUILD_BRANCH" == refs/tags/* ]]; then
  export _IS_GITHUB_RELEASE="true"
fi
export _RELEASE_VERSION="v${_APP_VERSION}-${_BUILD_VERSION}"

echo "--------------------------------------------------"
echo "RELEASE VERSION: $_RELEASE_VERSION"
echo "--------------------------------------------------"

echo "_BUILD_VERSION=${_BUILD_VERSION}" >> "${GITHUB_ENV}"
echo "_RELEASE_VERSION=${_RELEASE_VERSION}" >> "${GITHUB_ENV}"
echo "_IS_BUILD_CANARY=${_IS_BUILD_CANARY}" >> "${GITHUB_ENV}"
echo "_IS_GITHUB_RELEASE=${_IS_GITHUB_RELEASE}" >> "${GITHUB_ENV}"

npm install --global create-dmg

echo "--------------------------------------------------"
echo " Building and packaging SummonKit"
echo "--------------------------------------------------"

./build.sh --dist ./dist
create-dmg --no-code-sign --no-version-in-filename dist/SummonKit.app dist/
mv "./dist/${_RELEASE_NAME}.dmg" "./dist/${_RELEASE_NAME}-${_RELEASE_VERSION}.dmg"

# ---------------------------------------------------------------------------
# Validate app binary architecture (must be universal)
# ---------------------------------------------------------------------------
APP_BINARY="./dist/SummonKit.app/Contents/MacOS/SummonKit"
if [ ! -f "$APP_BINARY" ]; then
  echo "ERROR: Expected app binary not found at: $APP_BINARY"
  exit 1
fi

APP_ARCHS=$(lipo -archs "$APP_BINARY")
echo "Binary architectures: $APP_ARCHS"

if [[ "$APP_ARCHS" != *"arm64"* || "$APP_ARCHS" != *"x86_64"* ]]; then
  echo "ERROR: SummonKit binary is not universal (missing arm64 and/or x86_64)."
  exit 1
fi
echo "✓ Universal binary check passed (arm64 + x86_64)."

# ---------------------------------------------------------------------------
# Generate Sparkle appcast (only for actual GitHub releases)
# ---------------------------------------------------------------------------
if [[ "$_IS_GITHUB_RELEASE" == "true" ]]; then
  echo "--------------------------------------------------"
  echo " Generating Sparkle appcast"
  echo "--------------------------------------------------"

  # Resolve the exact Sparkle version that was pinned by SPM so we download
  # the matching CLI tools (which include generate_appcast / generate_keys).
  SPARKLE_VERSION=$(jq -r '
    .pins[]
    | select(.identity | ascii_downcase | test("sparkle"))
    | .state.version
  ' Package.resolved)

  if [ -z "$SPARKLE_VERSION" ]; then
    echo "ERROR: Could not determine Sparkle version from Package.resolved"
    exit 1
  fi

  echo "Sparkle version: $SPARKLE_VERSION"

  # Download the full Sparkle release archive (contains bin/generate_appcast)
  SPARKLE_TOOLS_DIR=$(mktemp -d)
  curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS_DIR"

  GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/bin/generate_appcast"
  chmod +x "$GENERATE_APPCAST"

  # Write the EdDSA private key to a temp file (supplied via GitHub secret)
  SPARKLE_KEY_FILE=$(mktemp)
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_KEY_FILE"
  trap 'rm -f "$SPARKLE_KEY_FILE"; rm -rf "$SPARKLE_TOOLS_DIR"' EXIT

  # Canary releases are always published under the fixed "canary" tag;
  # stable releases are published under the version tag (e.g. 1.0.0).
  # The DMG filename is determined by create-dmg from the app name and
  # Info.plist version, e.g. "SummonKit-v0.1.0-12345678.dmg" → urlencoded by
  # generate_appcast automatically.  We just need the correct tag in the
  # prefix so the download URL resolves to the right GitHub Release asset.
  if [[ "$_IS_BUILD_CANARY" == "true" ]]; then
    RELEASE_TAG="canary"
    APPCAST_FILE="appcast-canary.xml"
  else
    RELEASE_TAG="$_APP_VERSION"
    APPCAST_FILE="appcast.xml"
  fi

  # generate_appcast scans the dist/ directory, finds the DMG, and signs it.
  # --download-url-prefix must match where the DMG will be attached as a
  # GitHub Release asset so Sparkle can download the right file.
  "$GENERATE_APPCAST" \
    --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "https://github.com/julianxhokaxhiu/SummonKit/releases/download/${RELEASE_TAG}/" \
    --link "https://github.com/julianxhokaxhiu/SummonKit" \
    --full-release-notes-url "https://github.com/julianxhokaxhiu/SummonKit/releases/tag/${RELEASE_TAG}" \
    ./dist/

  # Rename the generated file to the channel-specific name so stable and
  # canary appcasts can coexist on the gh-pages branch.
  mv ./dist/appcast.xml "./dist/${APPCAST_FILE}"

  echo "✓ ${APPCAST_FILE} generated at dist/${APPCAST_FILE}"
fi
