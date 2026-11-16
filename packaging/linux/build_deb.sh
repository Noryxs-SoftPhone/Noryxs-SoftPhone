#!/usr/bin/env bash
# Empaqueta la app Linux (bundle de Flutter) en un .deb instalable con:
#   sudo apt install ./NORYXS-Terminal_<versión>_amd64.deb
# Uso (desde la raíz del repo, tras 'flutter build linux --release'):
#   packaging/linux/build_deb.sh
set -euo pipefail

PKG="noryxs-terminal"
NAME="NORYXS Terminal"
BIN="noryxs_terminal"
DESC="NORYXS Virtual SIP Terminal"
APPID="com.noryxs.noryxs_terminal"   # = APPLICATION_ID de linux/CMakeLists.txt (Wayland asocia ventana e icono por él)
BUNDLE="app/build/linux/x64/release/bundle"
ICON="app/linux/runner/resources/noryxs.png"

# Versión de pubspec.yaml: 1.0.0+1 -> 1.0.0-1
VER=$(sed -n 's/^version: *//p' app/pubspec.yaml | head -1)
DEBVER="${VER%%+*}-${VER##*+}"
[ "$VER" = "${VER%%+*}" ] && DEBVER="$VER"

ROOT=$(mktemp -d)
chmod 755 "$ROOT"
trap 'rm -rf "$ROOT"' EXIT
install -d "$ROOT/DEBIAN" "$ROOT/opt/$PKG" "$ROOT/usr/bin" \
           "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE"/. "$ROOT/opt/$PKG/"
ln -s "/opt/$PKG/$BIN" "$ROOT/usr/bin/$PKG"
install -m 644 "$ICON" "$ROOT/usr/share/icons/hicolor/256x256/apps/$PKG.png"

cat > "$ROOT/usr/share/applications/$APPID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$NAME
Comment=$DESC
Exec=/opt/$PKG/$BIN
Icon=$PKG
Terminal=false
Categories=Network;Telephony;
StartupWMClass=$APPID
DESKTOP

SIZE=$(du -sk "$ROOT/opt" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $DEBVER
Section: comm
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, libasound2t64 | libasound2, libopus0, libssl3t64 | libssl3, libfontconfig1, libayatana-appindicator3-1
Recommends: pipewire-alsa | libasound2-plugins
Maintainer: $NAME <$PKG@localhost>
Description: $DESC
 Teléfono IP multilínea (SIP) para FreePBX/Asterisk con motor PJSIP.
CONTROL

OUT="NORYXS-Terminal_${DEBVER}_amd64.deb"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT"
echo "Generado $OUT"
