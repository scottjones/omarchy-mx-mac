# Seed absent policy and supervise the runtime graph without replacing user choices.
omarchy-hw-apple-silicon || return 0

mic_policy_dir="$HOME/.config/wireplumber/wireplumber.conf.d"
mic_policy="$mic_policy_dir/asahi-headset-mic.conf"
mkdir -p "$mic_policy_dir"
if [[ ! -e $mic_policy && ! -L $mic_policy ]]; then
  cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/asahi-headset-mic.conf" "$mic_policy"
fi

# Package-owned unit; ExecCondition no-ops off Apple Silicon. Do not copy into
# ~/.config/systemd/user — /usr/lib/systemd/user/ stays authoritative.
systemctl --user daemon-reload >/dev/null 2>&1 || true
if ! systemctl --user enable omarchy-asahi-mic.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-asahi-mic.service \
    "$wants_dir/omarchy-asahi-mic.service"
fi

mic_status=0
omarchy-audio-asahi-mic-map || mic_status=$?
if [[ -S ${XDG_RUNTIME_DIR:-/run/user/$UID}/bus ]]; then
  systemctl --user start omarchy-asahi-mic.service >/dev/null 2>&1 || true
fi
# Warn rather than abort user setup: a broken PipeWire graph is not a reason
# to skip electron-gl, share-picker, and the rest of install/user/all.sh.
if (( mic_status != 0 && mic_status != 75 )); then
  echo "Warning: Asahi microphone mapping failed (status $mic_status); sound still works." >&2
fi
