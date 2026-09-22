#!/usr/bin/env bash
set -euo pipefail

variant="${1:-stable}"
variant="${variant,,}"

if [[ "$variant" == "stable" ]]; then
  url="https://discord.com/api/download?platform=linux&format=tar.gz"
  pkg="discord"
  app="Discord"
  exe="discord"
elif [[ "$variant" == "canary" ]]; then
  url="https://canary.discord.com/api/download?platform=linux&format=tar.gz"
  pkg="discord-canary"
  app="Discord Canary"
  exe="discord"
elif [[ "$variant" == "ptb" ]]; then
  url="https://ptb.discord.com/api/download?platform=linux&format=tar.gz"
  pkg="discord-ptb"
  app="Discord PTB"
  exe="discord"
else
  echo "error: unknown variant '${1}'. use: stable, canary, or ptb" >&2
  exit 1
fi

for cmd in curl tar fakeroot makepkg; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "error: '$cmd' not found. run ./install-deps.sh first." >&2
    exit 1
  fi
done

run_dir="$(pwd)"
work_dir="$(mktemp -d /tmp/discord-pkg.XXXXXX)"

tarball="${work_dir}/discord.tar.gz"
curl -L --progress-bar -o "$tarball" "$url"

extract_dir="${work_dir}/extracted"
mkdir -p "$extract_dir"
tar -xzf "$tarball" -C "$extract_dir"

discord_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [[ -z "$discord_dir" ]]; then
  echo "error: could not find extracted discord directory." >&2
  exit 1
fi

version="unknown"
build_info="${discord_dir}/resources/build_info.json"
if [[ -f "$build_info" ]]; then
  version="$(grep -oP '"version"\s*:\s*"\K[^"]+' "$build_info" || true)"
fi
if [[ -z "$version" || "$version" == "unknown" ]]; then
  version="$(basename "$discord_dir" | grep -oP '[\d.]+$' || true)"
fi
if [[ -z "$version" ]]; then
  version="0.0.0"
fi

icon_src="$(find "$discord_dir" -name "discord.png" | head -n1 || true)"

pkgbuild_dir="${work_dir}/pkgbuild"
install_dir="${pkgbuild_dir}/pkg/${pkg}/opt/${pkg}"
mkdir -p "$install_dir"
cp -r "$discord_dir"/. "$install_dir/"

icon_dir="${pkgbuild_dir}/pkg/${pkg}/usr/share/pixmaps"
desktop_dir="${pkgbuild_dir}/pkg/${pkg}/usr/share/applications"
bin_dir="${pkgbuild_dir}/pkg/${pkg}/usr/bin"
mkdir -p "$icon_dir" "$desktop_dir" "$bin_dir"

if [[ -n "$icon_src" && -f "$icon_src" ]]; then
  cp "$icon_src" "${icon_dir}/${pkg}.png"
fi

cat > "${desktop_dir}/${pkg}.desktop" <<EOF
[Desktop Entry]
Name=${app}
Exec=/opt/${pkg}/${exe}
Icon=${pkg}
Type=Application
Categories=Network;InstantMessaging;
EOF

ln -sf "/opt/${pkg}/${exe}" "${bin_dir}/${pkg}"

cat > "${pkgbuild_dir}/PKGBUILD" <<EOF
pkgname=${pkg}
pkgver=${version}
pkgrel=1
pkgdesc="${app} desktop app"
arch=('x86_64')
url="https://discord.com"
license=('custom')
package() {
  cp -r "\${srcdir}/pkg/${pkg}/." "\${pkgdir}/"
}
EOF

mkdir -p "${pkgbuild_dir}/src"
cp -r "${pkgbuild_dir}/pkg" "${pkgbuild_dir}/src/"

cd "$pkgbuild_dir"
makepkg --nodeps --nocheck --noprogressbar 2>&1

built_pkg="$(find "$pkgbuild_dir" -maxdepth 1 -name "*.pkg.tar.zst" | head -n1)"
if [[ -z "$built_pkg" ]]; then
  echo "error: package build failed, no .pkg.tar.zst found." >&2
  exit 1
fi

final_path="${run_dir}/${pkg}-${version}.pkg.tar.zst"
cp "$built_pkg" "$final_path"

sudo pacman -U "$final_path"

rm -rf "$work_dir"
