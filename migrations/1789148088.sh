echo "Repair missing Snapper root setup on Apple Silicon"

# The asahi-overlay skipped Snapper at install because Limine is absent.
# The leaf is now defensive (btrfs-only, optional Limine unit), so existing
# Macs can get a root config without a reinstall. Gate on Apple Silicon: the
# leaf returns non-zero on a partial or customised layout, and a failing
# migration would skip every later one for x86 users with an admin Snapper.
omarchy-hw-apple-silicon || exit 0

filesystem=$(stat -f -c %T /) || exit 0
if [[ $filesystem != "btrfs" ]]; then
  echo "Skipping Snapper setup: / is $filesystem, not btrfs."
  exit 0
fi

if (( EUID == 0 )); then
  bash -euo pipefail "$OMARCHY_PATH/install/config/snapper.sh"
else
  sudo env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$OMARCHY_PATH/install/config/snapper.sh"
fi
