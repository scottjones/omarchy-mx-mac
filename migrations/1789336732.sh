echo "Add the [omarchy-aarch64] repository on Apple Silicon"

# Existing Apple Silicon installs that never had the stanza cannot pkg-add any
# of Omarchy's own aarch64 packages; the migrations that follow this one do.
omarchy-hw-apple-silicon || exit 0

source "$OMARCHY_PATH/install/hardware/apple/pacman.sh"

# omarchy-update syncs the databases before running migrations, so a stanza
# added here has no database yet and the next pkg-add would fail asking for
# -Sy. Fetch it now; only when this run actually added the repository.
if (( OMARCHY_AARCH64_REPO_ADDED )); then
  sudo pacman -Sy
fi
