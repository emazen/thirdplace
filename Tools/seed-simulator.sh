#!/bin/sh
# Fills the booted simulator's photo library with the test persona from seed-photos.swift.
set -e
cd "$(dirname "$0")/.."
swift Tools/seed-photos.swift build/SeedPhotos
xcrun simctl addmedia booted build/SeedPhotos/*.jpg
echo "Added to the booted simulator."
