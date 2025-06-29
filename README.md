# SSH Security Hardening Script

This Bash script provides a simple, safe, and automated way to apply essential SSH server hardening configurations on a Linux system. It includes a backup mechanism, syntax validation, and optional user-based SSH access control.

> ⚠️ **Warning**: This script modifies your `/etc/ssh/sshd_config`. Always test SSH access in a separate session before logging out to avoid locking yourself out.

## Features

- ✅ Creates a backup of the existing SSH configuration
- ✅ Appends secure SSH settings if not already present
- ✅ Optionally restricts SSH access to a specific user via `AllowUsers`
- ✅ Validates `sshd_config` syntax before restarting the SSH service
- ✅ Displays current `sshd` service status after reloading

## SSH Settings Applied

If not already present, the following secure defaults are added:

```ini
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers [your_user]  # If you choose to add one
```

## Usage

### ⚙️ Requirements

- Bash shell
- `sudo` privileges
- Linux system with `systemd`
- SSH server installed (`sshd`)

### 🛠 How to Run

1. Save the script to a file.
2. Make it executable:
   ```bash
   chmod +x secure-ssh.sh
   ```
3. Run it with:
   ```bash
   ./secure-ssh.sh
   ```

You will be prompted to optionally specify a username for SSH access (added to `AllowUsers`).

> 🧪 Keep an active SSH session open during testing to avoid losing access.

## Output

The script provides clear, colorless terminal output with progress indicators, and shows warnings or failures if encountered (e.g., syntax issues or failure to restart the SSH service).

## Example Session

```text
[*] Starting SSH hardening...
Enter a username to allow SSH access (leave blank to skip): adminuser
[*] Creating backup at /etc/ssh/sshd_config.bak...
[✓] Backup created.
[*] Appending secure SSH settings...
[✓] Added 'AllowUsers adminuser' to sshd_config.
[✓] Settings appended.
[*] Validating sshd configuration...
[✓] SSH config is valid.
[*] Restarting sshd...
[✓] sshd restarted successfully.
[*] sshd status:
● ssh.service - OpenSSH server daemon
...
[✓] SSH hardening complete!
🛑 Keep a test SSH session open before logging out!
```

## Notes

- If the script detects it has already modified the file, it won’t duplicate the settings.
- A backup is created only once and not overwritten unless manually removed.

## Author

**Ellie**
**umellie8@gmail.com**
Feel free to reach out or contribute by submitting issues or pull requests.
