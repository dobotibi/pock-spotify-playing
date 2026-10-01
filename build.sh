#!/bin/zsh
# Builds SpotifyPlaying.pock (universal: arm64 + x86_64).
# PockKit/TinyConstraints are compiled as interface-only modules; the real binaries come from Pock.app at runtime.
# Usage: ./build.sh [--install]
set -e
ROOT=${0:A:h}
DEPS=$ROOT/deps
OUT=$ROOT/build
POCK_FW=/Applications/Pock.app/Contents/Frameworks
SDK=$(xcrun --sdk macosx --show-sdk-path)
[[ -d $POCK_FW ]] || { echo "Pock.app not found in /Applications"; exit 1; }
# Dependency sources (only their interfaces are compiled)
mkdir -p $DEPS
[[ -d $DEPS/pockkit ]] || git clone -q --depth 1 --branch 0.3.1 https://github.com/pock/pockkit.git $DEPS/pockkit
[[ -d $DEPS/TinyConstraints ]] || git clone -q --depth 1 --branch 4.0.1 https://github.com/roberthein/TinyConstraints.git $DEPS/TinyConstraints
rm -rf $OUT && mkdir -p $OUT
for ARCH in arm64 x86_64; do
  T=$ARCH-apple-macos10.15
  M=$OUT/$ARCH/mods && mkdir -p $M
  swiftc -parse-as-library -module-name TinyConstraints -target $T -sdk $SDK -emit-module -emit-module-path $M/TinyConstraints.swiftmodule $DEPS/TinyConstraints/TinyConstraints/Classes/*.swift 2>/dev/null
  swiftc -parse-as-library -module-name PockKit -target $T -sdk $SDK -I $M -emit-module -emit-module-path $M/PockKit.swiftmodule $(find $DEPS/pockkit/PockKit -name '*.swift') 2>/dev/null
  swiftc -O -module-name SpotifyPlaying -target $T -sdk $SDK -I $M \
    -emit-library -o $OUT/$ARCH/SpotifyPlaying \
    -F $POCK_FW -framework PockKit -framework TinyConstraints \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    $ROOT/Sources/*.swift
done
B=$OUT/SpotifyPlaying.pock/Contents
mkdir -p $B/MacOS $B/Resources
lipo -create $OUT/arm64/SpotifyPlaying $OUT/x86_64/SpotifyPlaying -output $B/MacOS/SpotifyPlaying
cp $ROOT/Info.plist $B/Info.plist
cp $ROOT/Resources/* $ROOT/LICENSE $B/Resources/
codesign --force --sign - $OUT/SpotifyPlaying.pock
# Shareable package: widget + README
mkdir -p $OUT/share && cp -R $OUT/SpotifyPlaying.pock $ROOT/docs/INSTALL.txt $OUT/share/
ditto -c -k --norsrc --noextattr $OUT/share $OUT/SpotifyPlaying.zip
echo "Built $OUT/SpotifyPlaying.pock"
if [[ "$1" == "--install" ]]; then
  W=~/Library/Application\ Support/Pock/Widgets
  osascript -e 'tell application id "com.pigigaldi.pock" to quit' 2>/dev/null || true
  sleep 1; pkill -x Pock || true
  rm -rf "$W/SpotifyPlaying.pock" && cp -R $OUT/SpotifyPlaying.pock "$W/"
  open -a Pock
  echo "Installed and restarted Pock"
fi
