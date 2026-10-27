# ssh-harden.sh — Step-by-Step Guide

A simple guide to secure the SSH server of a Linux machine (VM or server), with fixes for common problems.

---

## Table of Contents

1. [What does the script do?](#1-what-does-the-script-do)
2. [Before you start](#2-before-you-start)
3. [Step 1: Create an SSH key on your host](#step-1-create-an-ssh-key-on-your-host)
4. [Step 2: Copy the files to the VM](#step-2-copy-the-files-to-the-vm)
5. [Step 3: Run the script](#step-3-run-the-script)
6. [Step 4: Test in a NEW terminal](#step-4-test-in-a-new-terminal)
7. [Step 5: Take your snapshot](#step-5-take-your-snapshot)
8. [Options](#options)
9. [Settings that are applied](#settings-that-are-applied)
10. [Files the script creates or changes](#files-the-script-creates-or-changes)
11. [Troubleshooting](#troubleshooting)
12. [Rollback and recovery](#rollback-and-recovery)
13. [Re-running the script](#re-running-the-script)
14. [Other distributions](#other-distributions)
15. [Quick cheat sheet](#quick-cheat-sheet)

---

## 1. What does the script do?

The script makes your SSH server safer:

- It **turns off password login**. Only SSH keys can log in.
- It **turns off root login**.
- It **allows only the users you choose** (`AllowUsers`).
- It turns off things you usually do not need (X11, agent forwarding, TCP forwarding, tunnels).
- It limits login attempts and removes old, weak encryption algorithms.

It also protects you from mistakes:

| Safety feature | What it means |
|---|---|
| Key check | It will **not** disable passwords unless a valid public key exists for your user. |
| Backup | It saves a copy of `sshd_config` before it changes anything. |
| Syntax check | It runs `sshd -t` to test the new config. |
| Effective check | It runs `sshd -T` to confirm the settings really are active. |
| Auto rollback | If any check fails, it undoes its changes. |

> **Why a drop-in file?** SSH uses the **first** value it finds for each setting.
> The script writes a file that is loaded **first**, so no other file can override it.

---

## 2. Before you start

### Checklist

- [ ] A Linux VM with `openssh-server` installed
- [ ] A normal user with `sudo` rights (example: `youruser`)
- [ ] The VM IP address (run `ip -brief addr` inside the VM)
- [ ] Your host can already reach the VM with SSH (password login still works)
- [ ] **Two terminal windows** ready on the host (one for the script, one for testing)

### Requirements

- `bash` version 4 or newer (do **not** run the script with `sh`)
- Root access or `sudo`
- `ssh-keygen` (comes with `openssh-client`)

### Important idea

After the script runs, **only key login works**.
If you have no working key, you will be locked out of SSH.
That is why the steps below create and test the key **first**.

---

## Step 1: Create an SSH key on your host

Run this on your **host** computer (not inside the VM):

```bash
# Create a modern ed25519 key pair
ssh-keygen -t ed25519 -f ~/.ssh/my_key -C "my-key"
```

- It asks for a **passphrase**. A passphrase is recommended, but optional.
- Two files are created:
  - `~/.ssh/my_key` → your **private** key. **Never share it.**
  - `~/.ssh/my_key.pub` → your **public** key. This one is safe to share.

Check the public key. It must be **one line** starting with `ssh-ed25519`:

```bash
cat ~/.ssh/my_key.pub
```

---

## Step 2: Copy the files to the VM

Run this on your **host**. Replace `<VM_IP>` with the real IP:

```bash
# Copy the script and the PUBLIC key to the VM (password login still works now)
scp ssh-harden.sh ~/.ssh/my_key.pub youruser@<VM_IP>:~
```

> No SSH access yet? Open the console of your hypervisor (for example virt-manager, VirtualBox or Proxmox) and paste the script into a file with `nano ssh-harden.sh`.

---

## Step 3: Run the script

Log in to the VM, then run:

```bash
chmod +x ssh-harden.sh
sudo ./ssh-harden.sh -u youruser -k ~/my_key.pub
```

The script shows a summary and asks:

```
Apply SSH hardening now? [y/N]
```

Type `y` and press Enter.

### What a good run looks like

```
[+] Public key verified for 'youruser'.
[+] Backup created: /etc/ssh/sshd_config.bak-20260101-120000
[*] Using drop-in file: /etc/ssh/sshd_config.d/00-hardening.conf
[*] Validating configuration...
[+] Effective configuration verified with sshd -T.
[+] SSH service reloaded.
[+] sshd is listening on port 22.
[+] SSH hardening complete.
STOP: open a NEW terminal and test key-based login BEFORE closing this session.
```

> The `STOP:` line is a **warning**, not an error.
> It reminds you to do Step 4 before you close your current session.

**Do not close this terminal yet.**

---

## Step 4: Test in a NEW terminal

Open a **new** terminal on the host. Keep the old one open.

### Test 1: Key login must work

```bash
ssh -i ~/.ssh/my_key -o IdentitiesOnly=yes youruser@<VM_IP>
```

Expected result: you log in (the passphrase prompt is for your key, if you set one).

### Test 2: Password login must fail

```bash
ssh -o PubkeyAuthentication=no youruser@<VM_IP>
```

Expected result:

```
youruser@<VM_IP>: Permission denied (publickey).
```

### Test 3 (optional): Root login must fail

```bash
ssh -i ~/.ssh/my_key root@<VM_IP>
```

Expected result: `Permission denied`.

### Result

| Test 1 | Test 2 | What to do |
|---|---|---|
| Works | Fails | All good. Go to Step 5. |
| Fails | any | Do **not** close the old terminal. See [Troubleshooting](#troubleshooting) and [Rollback](#rollback-and-recovery). |

### Optional: make it easy with `~/.ssh/config`

Add this to `~/.ssh/config` on the host:

```
Host myvm
    HostName <VM_IP>
    User youruser
    IdentityFile ~/.ssh/my_key
    IdentitiesOnly yes
```

Now you can just type `ssh myvm`.

---

## Step 5: Take your snapshot

Only after the tests pass, take your snapshot (if you use snapshots in virt-manager, VirtualBox, Proxmox, etc.).

Every time you revert to this snapshot, SSH will already be hardened.
Your key stays valid, because it is stored inside the snapshot.

---

## Options

### Command-line flags

| Flag | Meaning | Example |
|---|---|---|
| `-u USER` | The user who must keep SSH access | `-u youruser` |
| `-k FILE` | Public key file to install for that user | `-k ~/my_key.pub` |
| `-y` | No questions (non-interactive) | `-y` |
| `-h` | Show help | `-h` |

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `SSH_PUBKEY` | empty | Public key text (instead of `-k`) |
| `ALLOW_USERS` | the `-u` user | Users allowed to log in, separated by spaces |
| `ALLOW_TCP_FORWARDING` | `no` | Use `yes`, `local` or `remote` if you need port forwarding or SOCKS |

### Examples

```bash
# Fully automatic
sudo ./ssh-harden.sh -u youruser -k ~/my_key.pub -y

# Allow two users and keep TCP forwarding
sudo ALLOW_USERS="youruser alice" ALLOW_TCP_FORWARDING=yes ./ssh-harden.sh -u youruser -k ~/my_key.pub -y

# Give the key as text
sudo SSH_PUBKEY="ssh-ed25519 AAAA... my-key" ./ssh-harden.sh -u youruser -y
```

> **Warning:** `AllowUsers` is a whitelist. Anyone not in the list cannot log in.

---

## Settings that are applied

| Setting | Value | Why |
|---|---|---|
| `PermitRootLogin` | `no` | Root is the most attacked account. |
| `PasswordAuthentication` | `no` | Stops password guessing. |
| `KbdInteractiveAuthentication` | `no` | Closes another password-like login path. (Older systems use `ChallengeResponseAuthentication`; the script picks the right name.) |
| `PubkeyAuthentication` | `yes` | Keys are the only way in. |
| `AuthenticationMethods` | `publickey` | Requires a key. |
| `PermitEmptyPasswords` | `no` | No blank passwords. |
| `HostbasedAuthentication` | `no` | Not needed. |
| `IgnoreRhosts` | `yes` | Ignores old `.rhosts` files. |
| `StrictModes` | `yes` | Rejects keys if file permissions are unsafe. |
| `MaxAuthTries` | `3` | Fewer guesses per connection. |
| `MaxSessions` | `4` | Limits sessions per connection. |
| `LoginGraceTime` | `30` | 30 seconds to finish login. |
| `MaxStartups` | `10:30:60` | Limits many unauthenticated connections at once. |
| `X11Forwarding` | `no` | Not needed for most VMs. |
| `AllowAgentForwarding` | `no` | Prevents agent misuse. |
| `AllowTcpForwarding` | `no` | Blocks tunnels (change with `ALLOW_TCP_FORWARDING`). |
| `GatewayPorts` | `no` | Forwarded ports stay private. |
| `PermitTunnel` | `no` | No VPN-style tunnels. |
| `PermitUserEnvironment` | `no` | Users cannot set environment tricks. |
| `Compression` | `no` | Avoids compression-related risks. |
| `ClientAliveInterval` / `ClientAliveCountMax` | `300` / `2` | Closes dead connections after about 10 minutes. |
| `LogLevel` | `VERBOSE` | Logs key fingerprints for better auditing. |
| `AllowUsers` | your user(s) | Only these users can log in. |

The optional crypto file removes weak algorithms: `*-cbc` ciphers, old SHA-1 key exchange groups, and weak MACs.
It only **removes** algorithms, so modern clients keep working.

---

## Files the script creates or changes

| File | What it is |
|---|---|
| `/etc/ssh/sshd_config.d/00-hardening.conf` | Main hardening settings (loaded first). |
| `/etc/ssh/sshd_config.d/01-hardening-crypto.conf` | Weak algorithm removal (skipped if not supported). |
| `/etc/ssh/sshd_config.bak-YYYYMMDD-HHMMSS` | Backup of your original config. |
| `~USER/.ssh/authorized_keys` | Your public key is added here. Permissions are fixed. |

On very old systems with no `Include` support, the script puts a marked block
(`# BEGIN ssh-harden` … `# END ssh-harden`) at the **top** of `/etc/ssh/sshd_config`.

---

## Troubleshooting

### A. Errors from the script

| Message | Cause | Fix |
|---|---|---|
| `Run as root or install sudo.` | You are not root and `sudo` is missing. | Run as root, or install sudo. |
| `OpenSSH server (sshd) is not installed.` | No SSH server. | `sudo apt install openssh-server` (Debian/Ubuntu). |
| `/etc/ssh/sshd_config not found.` | Unusual install. | Reinstall the SSH server package. |
| `No target user. Use -u USER.` | Non-interactive run without a user. | Add `-u youruser`. |
| `Root login will be disabled; choose a normal user.` | You used `-u root`. | Use a normal user. |
| `User '...' does not exist.` | Typo or missing account. | Check with `id USERNAME`. |
| `AllowUsers entry '...' does not exist.` | A name in `ALLOW_USERS` is wrong. | Fix the name. |
| `Invalid ALLOW_TCP_FORWARDING value.` | Wrong value. | Use `yes`, `no`, `local` or `remote`. |
| `Cannot read public key file: ...` | Wrong path or no permission. | Check the path with `ls -l`. |
| `No public key available. Use -k FILE or SSH_PUBKEY=...` | No key found, and the run was non-interactive. | Pass `-k ~/my_key.pub`. |
| `The supplied text is not a valid SSH public key.` | You gave a private key, a broken copy, or text split on several lines. | Use the `.pub` file. It must be **one line**. |
| `No valid public key in ...; refusing to continue` | Safety stop. | Add a valid key, then run again. |
| `Home directory of '...' not found.` | The user has no home directory. | Create it, or use another user. |
| `sshd -t reported errors in the new configuration.` | The new config is invalid. The script rolls back. | Run `sudo sshd -t` to see the exact error. |
| `Effective '...' is '...', expected '...'` | Another config line overrides the setting. | Run `grep -rniE "PasswordAuthentication" /etc/ssh/` to find it. |
| `sshd -T failed.` | `sshd` cannot test the config. | Run `sudo sshd -T` and read the error. Check host keys exist: `ls /etc/ssh/ssh_host_*`. |
| `Could not find the SSH systemd unit` | Unusual service name. | Run `systemctl list-unit-files \| grep -i ssh`. |
| `Failed to reload ...` / `... is not active after reload.` | The service has a problem. The script rolls back. | Run `sudo journalctl -u ssh -n 50 --no-pager`. |
| `No supported init system found` | No systemd, OpenRC or `service`. | Reload sshd yourself. |
| `Nothing is listening on port ...!` | The service is not listening. | **Keep your session open.** Check `sudo systemctl status ssh`. |
| `Crypto restrictions not supported ...; skipping them.` | Old OpenSSH. | **Harmless.** The main hardening still applied. |
| `Configuration invalid after removing crypto drop-in.` | A deeper config problem. | Run `sudo sshd -t` and fix the error. |

### B. Errors on your host when connecting

| Message | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | The server did not accept your key. | See the checklist below. |
| `Too many authentication failures` | `MaxAuthTries` is 3 and your ssh-agent offers many keys first. | Use `-i KEY -o IdentitiesOnly=yes` (or `IdentitiesOnly yes` in `~/.ssh/config`). |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` | The key file is readable by others. | `chmod 600 ~/.ssh/my_key` |
| `Connection refused` | SSH is not running, wrong IP or port, or a firewall. | Check `systemctl status ssh` in the VM console. |
| `Connection timed out` | Wrong IP, VM is off, or the network blocks you. | Check the IP with `ip -brief addr` in the VM. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | The VM has new host keys (for example, a rebuilt VM). | Only if you trust the change: `ssh-keygen -R <VM_IP>`. |
| `no matching cipher / key exchange / MAC found` | A very old client cannot use the modern algorithms. | Update your SSH client. As a last resort, delete `01-hardening-crypto.conf` and reload. |
| `channel ... open failed: administratively prohibited` | TCP forwarding is off. | Run the script again with `ALLOW_TCP_FORWARDING=yes`. |
| `X11 forwarding request failed` | X11 is off. | This is expected. Remove `-X` from your command. |

### Checklist for `Permission denied (publickey)`

1. **Are you using the right key and user?**
   `ssh -i ~/.ssh/my_key -o IdentitiesOnly=yes youruser@<VM_IP>`
2. **Is the user in `AllowUsers`?**
   `sudo sshd -T | grep -i allowusers`
3. **Is the public key in the right place?**
   `sudo cat /home/youruser/.ssh/authorized_keys`
4. **Are the permissions correct?** (`StrictModes` needs this)
   ```bash
   ls -ld /home/youruser /home/youruser/.ssh /home/youruser/.ssh/authorized_keys
   # Home must not be writable by group/others, .ssh = 700, authorized_keys = 600
   ```
5. **Read the server log** while you try to connect:
   ```bash
   # Debian/Ubuntu (systemd)
   sudo journalctl -u ssh -f
   # RHEL/Fedora
   sudo tail -f /var/log/secure
   ```
6. **Get detailed client output:**
   `ssh -vvv -i ~/.ssh/my_key youruser@<VM_IP>`

---

## Rollback and recovery

### Case 1: You still have the old terminal open (best case)

Run the command printed at the end of the script. It looks like this:

```bash
# Remove the hardening files and restore the original config
sudo rm -f /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/01-hardening-crypto.conf
sudo cp -p /etc/ssh/sshd_config.bak-YYYYMMDD-HHMMSS /etc/ssh/sshd_config

# Check and reload
sudo sshd -t && sudo systemctl reload ssh
```

> Use the real backup file name. List them with `ls /etc/ssh/sshd_config.bak-*`.

### Case 2: You are locked out of SSH

Your VM is not lost. The **local console** does not use SSH.

1. Open the VM in your hypervisor (for example **virt-manager**) and use the console window.
2. Log in with the user's **password** (console login is not affected by SSH settings; the account must still have a password set).
3. Run the rollback commands from Case 1.

### Case 3: You have a snapshot

Revert to a snapshot taken **before** the script, and start again from Step 1.

---

## Re-running the script

It is safe to run the script again:

- The drop-in files are **replaced**, not duplicated.
- Old inline blocks (old systems) are removed first, then written again.
- A new timestamped backup is created each run.
- Keys already in `authorized_keys` are not added twice.

Use this to change options, for example to turn TCP forwarding on:

```bash
sudo ALLOW_TCP_FORWARDING=yes ./ssh-harden.sh -u youruser -y
```

### Check the current effective settings anytime

```bash
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication|authenticationmethods|allowusers|maxauthtries|allowtcpforwarding) '
```

### Remove the hardening completely

```bash
sudo rm -f /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/01-hardening-crypto.conf
sudo sshd -t && sudo systemctl reload ssh
```

The public key stays in `authorized_keys`. Remove it by hand if you want.

---

## Other distributions

The script detects most differences itself:

| Difference | How the script handles it |
|---|---|
| Service name `ssh` (Debian/Ubuntu) or `sshd` (RHEL, Fedora, Arch, SUSE) | Auto-detected |
| Ubuntu socket activation | Uses `reload-or-restart` and checks the socket |
| No systemd (OpenRC, SysV) | Uses `rc-service` or `service` |
| Old OpenSSH without `Include` | Uses a marked block at the top of `sshd_config` |
| Old option name `ChallengeResponseAuthentication` | Auto-detected |
| `sshd` not in your `PATH` | Searches `/usr/sbin` and `/usr/local/sbin` |

Notes:

- **Alpine:** install bash first: `apk add bash openssh`.
- **RHEL/Fedora with a custom SSH port and SELinux:** this script does not change ports, so no SELinux change is needed.
- Logs on RHEL-like systems are in `/var/log/secure`.

---

## Quick cheat sheet

```bash
# 1. Host: create key
ssh-keygen -t ed25519 -f ~/.ssh/my_key

# 2. Host: copy files
scp ssh-harden.sh ~/.ssh/my_key.pub youruser@<VM_IP>:~

# 3. VM: run the script
chmod +x ssh-harden.sh
sudo ./ssh-harden.sh -u youruser -k ~/my_key.pub

# 4. Host, NEW terminal: test (must work)
ssh -i ~/.ssh/my_key -o IdentitiesOnly=yes youruser@<VM_IP>

# 5. Host, NEW terminal: test (must fail)
ssh -o PubkeyAuthentication=no youruser@<VM_IP>

# 6. Take your snapshot
```

**Golden rule:** never close your working session until a second, new session with the key has succeeded.
