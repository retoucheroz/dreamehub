#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build-app.sh
mkdir -p dist
package_stage=$(mktemp -d -t dreame-hub-swift-package)
ditto "build/Dreame Hub Swift.app" "$package_stage/Dreame Hub Swift.app"
ln -s /Applications "$package_stage/Applications"
cp README.md "$package_stage/README.md"
cp README.tr.md "$package_stage/README.tr.md"
cp README.it.md "$package_stage/README.it.md"
cp README.sv.md "$package_stage/README.sv.md"
cp INSTALL.html "$package_stage/INSTALL - Kurulum.html"
cp LICENSE THIRD_PARTY_NOTICES.md "$package_stage/"
cp -R licenses "$package_stage/licenses"
cp -R docs "$package_stage/docs"
cp docs/VERIFICATION.md "$package_stage/VERIFICATION.md"
package_output="$PWD/dist/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg"
hdiutil create -volname "Dreame Hub Swift" -srcfolder "$package_stage" -format UDZO -ov "$package_output"
hdiutil verify "$package_output"
shasum -a 256 "$package_output"
# Keep the bounded staging directory recoverable; it contains no account data.
echo "Package staging: $package_stage"
