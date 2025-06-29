#!/bin/bash

# ===================== SSH Security Hardening Script =======================
# Appends secure SSH settings, optionally adds a user to AllowUsers,
# backs up original config, checks syntax, and safely restarts sshd.
# ============================================================================
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_PATH="/etc/ssh/sshd_config.bak"
MARKER="# ===== Custom SSH Security Settings (Added by Admin) ====="

echo "[*] Starting SSH hardening..."

# Step 1: Ask for optional AllowUsers username
read -rp "Enter a username to allow SSH access (leave blank to skip): " SSH_USER

# Step 2: Backup original config
if [ -f "$BACKUP_PATH" ]; then
  echo "[i] Backup already exists at $BACKUP_PATH. Skipping backup."
else
  echo "[*] Creating backup at $BACKUP_PATH..."
  sudo cp "$SSH_CONFIG" "$BACKUP_PATH" || { echo "[!] Backup failed. Aborting."; exit 1; }
  echo "[✓] Backup created."
fi

# Step 3: Check if settings already exist
if grep -qF "$MARKER" "$SSH_CONFIG"; then
  echo "[i] Custom SSH settings already exist. Skipping append."
else
  echo "[*] Appending secure SSH settings..."
  sudo tee -a "$SSH_CONFIG" > /dev/null << EOF

$MARKER
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF

  # Append AllowUsers line if a username was provided
  if [[ -n "$SSH_USER" ]]; then
    echo "AllowUsers $SSH_USER" | sudo tee -a "$SSH_CONFIG" > /dev/null
    echo "[✓] Added 'AllowUsers $SSH_USER' to sshd_config."
  else
    echo "[i] No username provided. Skipping AllowUsers line."
  fi

  echo "[✓] Settings appended."
fi

# Step 4: Test config syntax
echo "[*] Validating sshd configuration..."
if ! sudo sshd -t; then
  echo "[!] sshd configuration has errors. Please fix them before restarting."
  exit 1
fi
echo "[✓] SSH config is valid."

# Step 5: Restart sshd
echo "[*] Restarting sshd..."
if sudo systemctl restart sshd; then
  echo "[✓] sshd restarted successfully."
else
  echo "[!] Failed to restart sshd. Manual intervention may be required."
  exit 1
fi

# Step 6: Show service status
echo "[*] sshd status:"
sudo systemctl status sshd --no-pager

echo "[✓] SSH hardening complete!"
echo "🛑 Keep a test SSH session open before logging out!"
