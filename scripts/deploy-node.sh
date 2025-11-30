#!/usr/bin/env bash
set -e

# Usage: ./scripts/deploy-node.sh <hostname> <target-connection-string>
# Example: ./scripts/deploy-node.sh edge-gw root@192.168.10.50

HOST_NAME=$1
TARGET=$2
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$(dirname "$SCRIPT_DIR")
KEY_DIR="$REPO_ROOT/secrets/keys/$HOST_NAME"

if [ -z "$HOST_NAME" ] || [ -z "$TARGET" ]; then
    echo "Usage: $0 <hostname> <target-user@ip>"
    exit 1
fi

echo "Deploying to $HOST_NAME at $TARGET..."

mkdir -p "$KEY_DIR"
KEY_FILE="$KEY_DIR/ssh_host_ed25519_key"

if [ ! -f "$KEY_FILE" ]; then
    echo "Generating new SSH host key for $HOST_NAME..."
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "root@$HOST_NAME"
else
    echo "Using existing SSH host key from $KEY_DIR"
fi

echo "----------------------------------------------------------------"
echo "Ensure the following AGE key is added to secrets/.sops.yaml:"
nix shell nixpkgs#ssh-to-age -c ssh-to-age -i "$KEY_FILE.pub"
echo "Then run: sops updatekeys secrets/secrets.yaml"
echo "----------------------------------------------------------------"
read -p "Press Enter to continue with deployment (or Ctrl-C to abort if you need to update secrets first)..."

# nixos-anywhere expects a directory that maps to the root / of the target
TEMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR/etc/ssh"
cp "$KEY_FILE" "$TEMP_DIR/etc/ssh/"
cp "$KEY_FILE.pub" "$TEMP_DIR/etc/ssh/"
chmod 600 "$TEMP_DIR/etc/ssh/ssh_host_ed25519_key"

echo "Starting nixos-anywhere..."
nix run github:nix-community/nixos-anywhere -- \
    --extra-files "$TEMP_DIR" \
    --flake "$REPO_ROOT#$HOST_NAME" \
    "$TARGET"