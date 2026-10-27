# ssh-harden

A safe, simple Bash script that hardens the OpenSSH server on a Linux machine.

It disables password and root login, allows only the users you choose, and checks
everything before it reloads the service. If something goes wrong, it rolls back.

> **Read this first:** after the script runs, **only SSH keys can log in**.
> Make sure you have a working key **and** a way to reach the machine without SSH
> (for example a VM console). See [Safety](#safety).

---

## Features

- Disables password login, keyboard-interactive login and root login
- Requires public key authentication and limits login attempts
- Allows only the users you list (`AllowUsers`)
- Turns off X11, agent forwarding, TCP forwarding and tunnels (TCP forwarding can be re-enabled)
- Removes weak encryption algorithms (it only removes; it never forces new ones)
- Uses a **drop-in file** that is loaded first, so other config files cannot override it
- Works with old OpenSSH (no `Include` support) by using a marked block at the top of `sshd_config`
- Detects the service name (`ssh` / `sshd`), `sshd` path and the right option names automatically
- Can run **again and again** safely (idempotent)

## Safety checks built in

| Check | What it does |
|---|---|
| Key check | Refuses to continue unless a valid public key exists for your user |
| Backup | Saves `sshd_config` as `sshd_config.bak-<timestamp>` before changes |
| `sshd -t` | Tests the new configuration |
| `sshd -T` | Confirms the **effective** values are really active |
| Auto rollback | Restores the old configuration if any check fails |

---

## Quick start

```bash
# 1. On your own computer: create a key pair
ssh-keygen -t ed25519 -f ~/.ssh/my_key

# 2. Copy the script and the PUBLIC key to the server
scp ssh-harden.sh ~/.ssh/my_key.pub youruser@<SERVER_IP>:~

# 3. On the server: run the script
chmod +x ssh-harden.sh
sudo ./ssh-harden.sh -u youruser -k ~/my_key.pub

# 4. On your own computer, in a NEW terminal: test BEFORE closing the old session
ssh -i ~/.ssh/my_key -o IdentitiesOnly=yes youruser@<SERVER_IP>
```

Download the file first. Do **not** run it with `curl ... | bash`; the script needs
to start itself again with `sudo`, which does not work through a pipe.

For the full walkthrough, tests, and error fixes, read **[GUIDE.md](GUIDE.md)**.

---

## Usage

```
sudo ./ssh-harden.sh [-u USER] [-k PUBKEY_FILE] [-y]
```

| Flag | Meaning |
|---|---|
| `-u USER` | The user who must keep SSH access |
| `-k FILE` | Public key file to install for that user |
| `-y` | Non-interactive (no questions) |
| `-h` | Show help |

| Environment variable | Default | Meaning |
|---|---|---|
| `SSH_PUBKEY` | empty | Public key text (instead of `-k`) |
| `ALLOW_USERS` | the `-u` user | Users allowed to log in, separated by spaces |
| `ALLOW_TCP_FORWARDING` | `no` | `yes`, `local` or `remote` to keep port forwarding |

```bash
# Example: allow two users and keep TCP forwarding
sudo ALLOW_USERS="youruser alice" ALLOW_TCP_FORWARDING=yes \
  ./ssh-harden.sh -u youruser -k ~/my_key.pub -y
```

---

## Requirements

- Linux with the OpenSSH server installed
- `bash` 4 or newer (not `sh`)
- Root access or `sudo`
- `ssh-keygen` (from `openssh-client`)

## Supported systems

The script is written for most Linux distributions that use OpenSSH:

| System | Status |
|---|---|
| Debian | Tested |
| Ubuntu, Fedora, RHEL-like, Arch, openSUSE, Alpine | Designed to work, **not fully tested yet** |
| macOS, BSD | Not supported |

Tested it somewhere else? Please open an issue and tell us the distribution and version.

---

## What changes on your system

| File | What it is |
|---|---|
| `/etc/ssh/sshd_config.d/00-hardening.conf` | Main hardening settings |
| `/etc/ssh/sshd_config.d/01-hardening-crypto.conf` | Weak algorithm removal (skipped if unsupported) |
| `/etc/ssh/sshd_config.bak-<timestamp>` | Backup of the original config |
| `~USER/.ssh/authorized_keys` | Your public key is added; permissions are fixed |

The script does not change the SSH port, does not touch the firewall, and does not
send any data over the network.

## Undo

```bash
# Remove the hardening files and reload SSH
sudo rm -f /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/01-hardening-crypto.conf
sudo sshd -t && sudo systemctl reload ssh   # on some systems the service is called "sshd"
```

If you used the inline mode (old OpenSSH), restore the backup instead:
`sudo cp -p /etc/ssh/sshd_config.bak-<timestamp> /etc/ssh/sshd_config`

---

## Safety

- Always keep your **current session open** until a **second new session with the key works**.
- Keep another way in (VM console, cloud console, physical access).
- `AllowUsers` is a whitelist: users not in the list cannot log in.
- `MaxAuthTries` is 3. If your SSH agent holds many keys, use `-o IdentitiesOnly=yes`.

## Disclaimer

This script changes the security configuration of your SSH server. It is provided
**as is**, without any warranty. Test it on a non-production machine first. You are
responsible for the systems you run it on.

## Contributing

Issues and pull requests are welcome, especially test reports for other distributions.
Please run `shellcheck ssh-harden.sh` before you open a pull request.
