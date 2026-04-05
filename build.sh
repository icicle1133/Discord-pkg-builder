#!/usr/bin/env bash
set -euo pipefail

variant="${1:-stable}"
variant="${variant,,}"

if [[ "$variant" == "stable" ]]; then
  downloadurl="https://discord.com/api/download?platform=linux&format=tar.gz"
  pkgname="discord"
  appname="Discord"
  execname="Discord"
elif [[ "$variant" == "canary" ]]; then
  downloadurl="https://canary.discord.com/api/download?platform=linux&format=tar.gz"
  pkgname="discord-canary"
  appname="Discord Canary"
  execname="DiscordCanary"
elif [[ "$variant" == "ptb" ]]; then
  downloadurl="https://ptb.discord.com/api/download?platform=linux&format=tar.gz"
  pkgname="discord-ptb"
  appname="Discord PTB"
  execname="DiscordPTB"
else
  echo "error: unknown variant '${1}'. use: stable, canary, or ptb" >&2
  exit 1
fi

for cmd in curl tar fakeroot makepkg; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "error: '$cmd' not found. run discord-pkg-deps.sh first." >&2
    exit 1
  fi
done

rundir="$(pwd)"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/discord-pkg.XXXXXX")"

tarball="${workdir}/discord.tar.gz"
curl -L --progress-bar -o "$tarball" "$downloadurl"

extractdir="${workdir}/extracted"
mkdir -p "$extractdir"
tar -xzf "$tarball" -C "$extractdir"

discorddir="$(find "$extractdir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [[ -z "$discorddir" ]]; then
  echo "error: could not find extracted discord directory." >&2
  exit 1
fi

version="unknown"
buildinfo="${discorddir}/resources/build_info.json"
if [[ -f "$buildinfo" ]]; then
  version="$(grep -oP '"version"\s*:\s*"\K[^"]+' "$buildinfo" || true)"
fi
if [[ -z "$version" || "$version" == "unknown" ]]; then
  version="$(basename "$discorddir" | grep -oP '[\d.]+$' || true)"
fi
if [[ -z "$version" ]]; then
  version="0.0.0"
fi

iconsrc="$(find "$discorddir" -name "discord.png" | head -n1 || true)"

pkgbuilddir="${workdir}/pkgbuild"
mkdir -p "$pkgbuilddir"

installdir="${pkgbuilddir}/pkg/${pkgname}/opt/${pkgname}"
mkdir -p "$installdir"
cp -r "$discorddir"/. "$installdir/"

icondir="${pkgbuilddir}/pkg/${pkgname}/usr/share/pixmaps"
mkdir -p "$icondir"
if [[ -n "$iconsrc" && -f "$iconsrc" ]]; then
  cp "$iconsrc" "${icondir}/${pkgname}.png"
fi

desktopdir="${pkgbuilddir}/pkg/${pkgname}/usr/share/applications"
mkdir -p "$desktopdir"
cat > "${desktopdir}/${pkgname}.desktop" <<EOF
[Desktop Entry]
Name=${appname}
Exec=/opt/${pkgname}/${execname}
Icon=${pkgname}
Type=Application
Categories=Network;InstantMessaging;
EOF

bindir="${pkgbuilddir}/pkg/${pkgname}/usr/bin"
mkdir -p "$bindir"
ln -sf "/opt/${pkgname}/${execname}" "${bindir}/${pkgname}"

cat > "${pkgbuilddir}/PKGBUILD" <<EOF
pkgname=${pkgname}
pkgver=${version}
pkgrel=1
pkgdesc="${appname} desktop app"
arch=('x86_64')
url="https://discord.com"
license=('custom')
package() {
  cp -r "\${srcdir}/pkg/${pkgname}/." "\${pkgdir}/"
}
EOF

mkdir -p "${pkgbuilddir}/src"
cp -r "${pkgbuilddir}/pkg" "${pkgbuilddir}/src/"

cd "$pkgbuilddir"
makepkg --nodeps --nocheck --noprogressbar 2>&1


builtpkg="$(find "$pkgbuilddir" -maxdepth 1 -name "*.pkg.tar.zst" | head -n1)"
if [[ -z "$builtpkg" ]]; then
  echo "error: package build failed, no .pkg.tar.zst found." >&2
  exit 1
fi

finalpath="${rundir}/${pkgname}-${version}.pkg.tar.zst"
cp "$builtpkg" "$finalpath"

sudo pacman -U "$finalpath"

rm -rf "$workdir"
