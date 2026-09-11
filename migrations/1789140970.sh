echo "Apply the Asahi Steam network-wait workaround"

# Fresh installs call omarchy-launch-steam --prepare from the Steam installer.
# Existing Apple Silicon users need the desktop entry and UI patch too.
[[ $(uname -m) == aarch64 ]] || exit 0
omarchy-cmd-present steam || [[ -d $HOME/.local/share/Steam ]] || exit 0
omarchy-launch-steam --prepare
