#!/usr/bin/env bash
# Builds fieldkit.slnx and packs every package into artifacts/packages.
# Usage: ./build.sh [Configuration]   (default Release)
set -euo pipefail
cd "$(dirname "$0")"

configuration="${1:-Release}"
solution=fieldkit.slnx
packages=artifacts/packages

# start from an empty output folder, so only this build's packages are in it
rm -rf "$packages"

dotnet restore "$solution"
dotnet build "$solution" --configuration "$configuration" --no-restore -p:FieldKitRelease=true
dotnet pack "$solution" --configuration "$configuration" --no-build -p:FieldKitRelease=true

echo
echo "Packages in $packages:"
ls -1 "$packages"
