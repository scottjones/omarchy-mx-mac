# hyprland-preview-share-picker in omarchy-base.packages has no aarch64 build, so
# xdg-desktop-portal-hyprland shows no source chooser and browser sharing silently
# degrades to tab-only. The -git package builds on aarch64, and only as the user.
[[ $(uname -m) == "aarch64" ]] || return 0

if omarchy-cmd-missing hyprland-preview-share-picker; then
  echo "Installing the browser screen-share picker for Apple Silicon."

  omarchy-pkg-aur-add hyprland-preview-share-picker-git ||
    echo "Warning: hyprland-preview-share-picker-git failed to build; browser screen sharing stays tab-only." >&2
fi

# Same PipeWire capturer flag the migration writes for existing aarch64 configs.
# Modern Chromium enables it by default; this covers older user flag files on
# a fresh aarch64 install. Do not write this into shipped x86 defaults.
for conf in ~/.config/{chromium,brave,chrome,microsoft-edge-stable}-flags.conf; do
  [[ -f $conf ]] || continue
  grep -q 'WebRTCPipeWireCapturer' "$conf" && continue
  if grep -q -- '--enable-features=' "$conf"; then
    sed -i 's/\(^--enable-features=[^[:space:]]*\)/\1,WebRTCPipeWireCapturer/' "$conf"
  else
    [[ -n $(tail -c1 "$conf") ]] && echo >>"$conf"
    echo '--enable-features=WebRTCPipeWireCapturer' >>"$conf"
  fi
done
