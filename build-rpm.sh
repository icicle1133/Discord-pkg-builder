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

need_deps=0
for cmd in curl tar rpmbuild; do
  if ! command -v "$cmd" &>/dev/null; then
    need_deps=1
  fi
done

if [[ "$need_deps" == "1" ]]; then
  if command -v dnf &>/dev/null; then
    sudo dnf install -y curl tar rpm-build
  elif command -v yum &>/dev/null; then
    sudo yum install -y curl tar rpm-build
  elif command -v zypper &>/dev/null; then
    sudo zypper --non-interactive install curl tar rpm-build
  else
    echo "error: install curl tar rpm-build" >&2
    exit 1
  fi
fi

run_dir="$(pwd)"
work_dir="$(mktemp -d /tmp/discord-rpm.XXXXXX)"

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
version="$(printf '%s' "$version" | tr '-' '.')"

icon_src="$(find "$discord_dir" -name "discord.png" | head -n1 || true)"

rpm_dir="${work_dir}/rpm"
for dir in build buildroot rpms sources specs srpms; do
  mkdir -p "${rpm_dir}/${dir}"
done

install_root="${work_dir}/root"
install_dir="${install_root}/opt/${pkg}"
mkdir -p "$install_dir"
cp -r "$discord_dir"/. "$install_dir/"

icon_dir="${install_root}/usr/share/pixmaps"
desktop_dir="${install_root}/usr/share/applications"
bin_dir="${install_root}/usr/bin"
mkdir -p "$icon_dir" "$desktop_dir" "$bin_dir"

icon_file=""
if [[ -n "$icon_src" && -f "$icon_src" ]]; then
  icon_file="${pkg}.png"
  cp "$icon_src" "${icon_dir}/${icon_file}"
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

file_list="%files
/opt/${pkg}
/usr/share/applications/${pkg}.desktop
/usr/bin/${pkg}"
if [[ -n "$icon_file" ]]; then
  file_list="${file_list}
/usr/share/pixmaps/${icon_file}"
fi

cat > "${rpm_dir}/specs/${pkg}.spec" <<EOF
Name: ${pkg}
Version: ${version}
Release: 1%{?dist}
Summary: ${app} desktop app
License: custom
URL: https://discord.com
BuildArch: x86_64

%description
${app} desktop app

%prep

%build

%install
mkdir -p %{buildroot}
cp -r ${install_root}/. %{buildroot}/

${file_list}
EOF

rpmbuild --define "_topdir ${rpm_dir}" -bb "${rpm_dir}/specs/${pkg}.spec"

rpm_path="$(find "${rpm_dir}/rpms" -name "*.rpm" | head -n1)"
if [[ -z "$rpm_path" ]]; then
  echo "error: package build failed, no .rpm found." >&2
  exit 1
fi

final_path="${run_dir}/${pkg}-${version}.rpm"
cp "$rpm_path" "$final_path"

if command -v dnf &>/dev/null; then
  sudo dnf install -y "$final_path"
elif command -v yum &>/dev/null; then
  sudo yum install -y "$final_path"
elif command -v zypper &>/dev/null; then
  sudo zypper --non-interactive install "$final_path"
else
  sudo rpm -Uvh "$final_path"
fi

rm -rf "$work_dir"
