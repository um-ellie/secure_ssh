#!/usr/bin/env bash
# =============================================================================
# ssh-harden.sh - Idempotent OpenSSH server hardening for most Linux distros
#
# What it does:
#   * Writes a drop-in file that is loaded FIRST (sshd uses the first value
#     it sees for each option), so nothing else can override it.
#   * Falls back to a managed block at the TOP of sshd_config when the distro
#     does not support "Include" (old OpenSSH).
#   * Refuses to disable password login unless a valid public key exists for
#     the login user (prevents lock-out).
#   * Validates config (sshd -t), verifies EFFECTIVE values (sshd -T),
#     reloads the service, and rolls back automatically on any failure.
#
# Usage:
#   sudo ./ssh-harden.sh [-u USER] [-k PUBKEY_FILE] [-y]
#
# Environment variables (optional):
#   SSH_PUBKEY=ssh-ed25519 AAAA...   public key text to install for USER
#   ALLOW_USERS="alice bob"          users for AllowUsers (default: USER)
#   ALLOW_TCP_FORWARDING=yes         keep TCP forwarding (default: no)
#
# Requires: bash 4+, OpenSSH server, root privileges (or sudo).
# =============================================================================
set -Eeuo pipefail

# ----------------------------- constants -------------------------------------
readonly MAIN_CONF="/etc/ssh/sshd_config"
readonly DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly CORE_DROPIN="${DROPIN_DIR}/00-hardening.conf"
readonly CRYPTO_DROPIN="${DROPIN_DIR}/01-hardening-crypto.conf"
readonly BEGIN_MARK="# BEGIN ssh-harden"
readonly END_MARK="# END ssh-harden"
STAMP="$(date +%Y%m%d-%H%M%S)"
readonly STAMP

# ----------------------------- helpers ---------------------------------------
CHANGED=0
MAIN_BACKUP=""

log()  { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

rollback() {
  warn "Rolling back changes..."
  rm -f "$CORE_DROPIN" "$CRYPTO_DROPIN"
  if [[ -n "$MAIN_BACKUP" && -f "$MAIN_BACKUP" ]]; then
    cat "$MAIN_BACKUP" > "$MAIN_CONF"
  fi
  CHANGED=0
}

die() {
  warn "$*"
  if [[ "$CHANGED" -eq 1 ]]; then rollback; fi
  exit 1
}

usage() {
  cat <<'EOF'
Usage: sudo ./ssh-harden.sh [-u USER] [-k PUBKEY_FILE] [-y]
  -u USER         login user that must keep SSH access
  -k PUBKEY_FILE  public key file to install for USER
  -y              non-interactive (assume yes)
  -h              show this help
EOF
}

# ----------------------------- privileges ------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || { echo "[!] Run as root or install sudo." >&2; exit 1; }
  exec sudo -E bash "$0" "$@"
fi

# ----------------------------- arguments -------------------------------------
TARGET_USER=""
PUBKEY_FILE=""
ASSUME_YES=0

while getopts ":u:k:yh" opt; do
  case "$opt" in
    u) TARGET_USER="$OPTARG" ;;
    k) PUBKEY_FILE="$OPTARG" ;;
    y) ASSUME_YES=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

INTERACTIVE=0
if [[ -t 0 && "$ASSUME_YES" -eq 0 ]]; then INTERACTIVE=1; fi

# ----------------------------- locate sshd -----------------------------------
SSHD=""
for candidate in "$(command -v sshd 2>/dev/null || true)" /usr/sbin/sshd /usr/local/sbin/sshd; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then SSHD="$candidate"; break; fi
done
[[ -n "$SSHD" ]] || die "OpenSSH server (sshd) is not installed."
[[ -f "$MAIN_CONF" ]] || die "$MAIN_CONF not found."

# sshd -t / -T need the privilege-separation directory on some distros
if [[ ! -d /run/sshd ]]; then mkdir -p /run/sshd && chmod 755 /run/sshd; fi

# ----------------------------- target user -----------------------------------
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="${SUDO_USER:-}"
  if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    if [[ "$INTERACTIVE" -eq 1 ]]; then
      read -rp "Login user that must keep SSH access: " TARGET_USER
    else
      die "No target user. Use -u USER."
    fi
  fi
fi
[[ -n "$TARGET_USER" ]] || die "Empty username."
[[ "$TARGET_USER" != "root" ]] || die "Root login will be disabled; choose a normal user."
id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist."

ALLOW_USERS="${ALLOW_USERS:-$TARGET_USER}"
for u in $ALLOW_USERS; do
  id "$u" >/dev/null 2>&1 || die "AllowUsers entry '$u' does not exist."
done
TCP_FWD="${ALLOW_TCP_FORWARDING:-no}"
[[ "$TCP_FWD" =~ ^(yes|no|local|remote)$ ]] || die "Invalid ALLOW_TCP_FORWARDING value."

# ----------------------------- authorized key --------------------------------
has_key() {
  [[ -s "$1" ]] && grep -Eq \
    '(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]{20,}' "$1"
}

ensure_authorized_key() {
  local user="$1" home group ssh_dir ak key_text="" tmp
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" && -d "$home" ]] || die "Home directory of '$user' not found."
  group="$(id -gn "$user")"
  ssh_dir="${home}/.ssh"
  ak="${ssh_dir}/authorized_keys"

  # Collect a key from -k file or SSH_PUBKEY variable, if provided
  if [[ -n "$PUBKEY_FILE" ]]; then
    [[ -r "$PUBKEY_FILE" ]] || die "Cannot read public key file: $PUBKEY_FILE"
    key_text="$(cat "$PUBKEY_FILE")"
  elif [[ -n "${SSH_PUBKEY:-}" ]]; then
    key_text="$SSH_PUBKEY"
  fi

  # No key supplied and none installed: ask for one (or abort)
  if [[ -z "$key_text" ]] && ! has_key "$ak"; then
    warn "No public key found for '$user'. Password login will be disabled, so one is required."
    if [[ "$INTERACTIVE" -eq 1 ]]; then
      read -rp "Paste the PUBLIC key (e.g. ssh-ed25519 AAAA...): " key_text
    else
      die "No public key available. Use -k FILE or SSH_PUBKEY=... to provide one."
    fi
  fi

  if [[ -n "$key_text" ]]; then
    tmp="$(mktemp)"
    printf '%s\n' "$key_text" > "$tmp"
    if ! ssh-keygen -l -f "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      die "The supplied text is not a valid SSH public key."
    fi
    install -d -m 700 -o "$user" -g "$group" "$ssh_dir"
    touch "$ak"
    # Append each key line only if it is not already present
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      grep -qxF "$line" "$ak" || printf '%s\n' "$line" >> "$ak"
    done < "$tmp"
    rm -f "$tmp"
  fi

  has_key "$ak" || die "No valid public key in $ak; refusing to continue (lock-out protection)."

  # Permissions required by StrictModes
  chown -R "$user:$group" "$ssh_dir"
  chmod 700 "$ssh_dir"
  chmod 600 "$ak"
  chmod go-w "$home"
  ok "Public key verified for '$user'."
}

# ----------------------------- config rendering ------------------------------
# Newer OpenSSH calls it KbdInteractiveAuthentication; older uses the old name.
if "$SSHD" -T 2>/dev/null | grep -qi '^kbdinteractiveauthentication '; then
  KBD_OPT="KbdInteractiveAuthentication"
else
  KBD_OPT="ChallengeResponseAuthentication"
fi

render_core() {
  cat <<EOF
# Managed by ssh-harden.sh - re-run the script instead of editing by hand
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
${KBD_OPT} no
AuthenticationMethods publickey
HostbasedAuthentication no
IgnoreRhosts yes
StrictModes yes
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 30
MaxStartups 10:30:60
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding ${TCP_FWD}
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no
Compression no
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
AllowUsers ${ALLOW_USERS}
EOF
}

# Only REMOVES weak algorithms (the "-" prefix), so it stays compatible
render_crypto() {
  cat <<'EOF'
# Managed by ssh-harden.sh - removes weak algorithms only
Ciphers -*-cbc
KexAlgorithms -diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
MACs -hmac-md5*,hmac-sha1-96*,umac-64*
EOF
}

has_include() {
  grep -Eiq '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' "$MAIN_CONF"
}

strip_inline_block() {
  sed -i "/${BEGIN_MARK}/,/${END_MARK}/d" "$MAIN_CONF"
}

validate() {
  "$SSHD" -t || return 1
}

verify_effective() {
  local out pair key want got
  out="$("$SSHD" -T 2>/dev/null)" || die "sshd -T failed."
  for pair in \
    "permitrootlogin=no" \
    "passwordauthentication=no" \
    "${KBD_OPT,,}=no" \
    "pubkeyauthentication=yes" \
    "x11forwarding=no" \
    "maxauthtries=3" \
    "authenticationmethods=publickey"; do
    key="${pair%%=*}"
    want="${pair#*=}"
    got="$(awk -v k="$key" '$1==k {print $2; exit}' <<<"$out")"
    if [[ "$got" != "$want" ]]; then
      die "Effective '$key' is '${got:-unset}', expected '$want' (something overrides it)."
    fi
  done
  ok "Effective configuration verified with sshd -T."
}

# ----------------------------- reload service --------------------------------
reload_sshd() {
  local svc=""
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    for u in ssh sshd; do
      if systemctl list-unit-files "${u}.service" 2>/dev/null | grep -q "^${u}\.service"; then
        svc="$u"; break
      fi
    done
    [[ -n "$svc" ]] || die "Could not find the SSH systemd unit (tried ssh, sshd)."
    systemctl reload-or-restart "$svc" || die "Failed to reload ${svc}.service."
    if ! systemctl is-active --quiet "$svc" && ! systemctl is-active --quiet "${svc}.socket"; then
      die "${svc} is not active after reload."
    fi
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd reload || die "Failed to reload sshd (OpenRC)."
  elif command -v service >/dev/null 2>&1; then
    service ssh reload 2>/dev/null || service sshd reload || die "Failed to reload SSH service."
  else
    die "No supported init system found; reload sshd manually."
  fi
  ok "SSH service reloaded."
}

# ----------------------------- main ------------------------------------------
log "Target user : $TARGET_USER"
log "AllowUsers  : $ALLOW_USERS"
log "TCP forward : $TCP_FWD"

if [[ "$INTERACTIVE" -eq 1 ]]; then
  read -rp "Apply SSH hardening now? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
fi

ensure_authorized_key "$TARGET_USER"

MAIN_BACKUP="${MAIN_CONF}.bak-${STAMP}"
cp -p "$MAIN_CONF" "$MAIN_BACKUP"
ok "Backup created: $MAIN_BACKUP"

CHANGED=1

if has_include; then
  log "Using drop-in file: $CORE_DROPIN"
  mkdir -p "$DROPIN_DIR"
  render_core > "$CORE_DROPIN"
  chmod 644 "$CORE_DROPIN"
  strip_inline_block   # clean any old inline block from a previous run
else
  log "No Include support found; writing a managed block at the top of $MAIN_CONF"
  strip_inline_block
  tmp="$(mktemp)"
  { echo "$BEGIN_MARK"; render_core; echo "$END_MARK"; cat "$MAIN_CONF"; } > "$tmp"
  cat "$tmp" > "$MAIN_CONF"
  rm -f "$tmp"
fi

log "Validating configuration..."
validate || die "sshd -t reported errors in the new configuration."

# Optional crypto drop-in: keep it only if this OpenSSH version accepts it
if has_include; then
  render_crypto > "$CRYPTO_DROPIN"
  chmod 644 "$CRYPTO_DROPIN"
  if ! validate; then
    warn "Crypto restrictions not supported by this OpenSSH version; skipping them."
    rm -f "$CRYPTO_DROPIN"
    validate || die "Configuration invalid after removing crypto drop-in."
  fi
fi

verify_effective
reload_sshd
CHANGED=0

# ----------------------------- report ----------------------------------------
PORT="$("$SSHD" -T 2>/dev/null | awk '$1=="port" {print $2; exit}')"
if command -v ss >/dev/null 2>&1 && [[ -n "$PORT" ]]; then
  if ss -ltn "sport = :${PORT}" 2>/dev/null | grep -q LISTEN; then
    ok "sshd is listening on port ${PORT}."
  else
    warn "Nothing is listening on port ${PORT}! Check the service before logging out."
  fi
fi

echo
log "Key effective settings:"
"$SSHD" -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|authenticationmethods|allowusers|maxauthtries|x11forwarding|allowtcpforwarding) ' || true

echo
ok "SSH hardening complete."
echo "STOP: open a NEW terminal and test key-based login BEFORE closing this session."
echo "Rollback: sudo rm -f ${CORE_DROPIN} ${CRYPTO_DROPIN} && sudo cp -p ${MAIN_BACKUP} ${MAIN_CONF}"
