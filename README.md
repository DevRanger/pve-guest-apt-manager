# pve-lxc-apt-manager

Parallel apt update/upgrade + maintenance orchestrator for Proxmox LXC containers.

Built for real-world Proxmox environments where you want:
- One command to patch everything
- Clean logging
- Reboot detection
- Optional cleanup
- Zero babysitting

---

# ✨ Features

### 🚀 Parallel LXC Updates
Runs `apt update && apt upgrade` across all running LXCs at once.

- Configurable concurrency (default: 10 at a time)
- Skips stopped containers automatically
- Live terminal dashboard with status + progress bar

### 📊 Smart Logging System
Two log levels:

**LOG_LEVEL=2 (default — recommended)**
- Clean high-level operator log
- Start/complete/fail events
- Summary + UI snapshot
- Captures full apt output *only if a container fails*

**LOG_LEVEL=1 (debug)**
- Full apt output for all containers
- Deep troubleshooting mode

Each run creates a timestamped logfile:
```
lxc-apt-upgrade_YYYY-MM-DD_HHMMSS.log
```

Colored logs supported:
```
less -R logfile.log
```

### 🧹 Optional Cleanup Mode
After upgrades complete, prompts to run:

```
apt autoremove
apt autoclean
```

Helps keep containers lean and prevents disk bloat.

### 🔁 Reboot Detection
Automatically detects:
```
/var/run/reboot-required
```

Prompts to reboot only containers that actually need it.

### 🎛 Clean Terminal UI
Live updating dashboard showing:
- Pending
- Running
- Completed
- Failed
- Skipped

Per-container status:
```
Grafana (CT 110)   COMPLETE
PiHole (CT 107)    RUNNING
DevTest (CT 104)   FAILED
```

---

# 📦 Installation

On your Proxmox host:

```bash
cd /root
nano pve-lxc-apt-manager.sh
```

Paste script → save.

Make executable:
```bash
chmod +x pve-lxc-apt-manager.sh
```

Optional: run from anywhere
```bash
ln -s /root/pve-lxc-apt-manager.sh /usr/local/sbin/pve-lxc-apt-manager
```

---

# ▶️ Running

Normal run:
```bash
pve-lxc-apt-manager
```

Debug mode:
```bash
LOG_LEVEL=1 pve-lxc-apt-manager
```

### ⏱ Note on startup
After launching, the script may take **5–15 seconds** before the terminal UI appears.

During this time it is:
- Enumerating containers
- Checking status
- Spawning parallel workers
- Initializing logging/UI

It can look like it’s hanging, it isn’t 🙂

---

# ⚙️ Configuration

Edit top of script:

```bash
MAX_JOBS=10
REFRESH_SEC=1
LOG_LEVEL=2
```

### Concurrency tuning
| Host Type | Suggested |
|----------|-----------|
Small homelab | 4–6 |
Modern SSD host | 8–12 |
Big iron | 15–25 |

---

# 🧠 Usage

### Normal run
```bash
./pve-lxc-apt-manager.sh
```

### Debug mode (full apt logs)
```bash
LOG_LEVEL=1 ./pve-lxc-apt-manager.sh
```

### View logs
```bash
less -R lxc-apt-upgrade_*.log
```

---

# 🛡 Safety Behavior

- Skips stopped containers
- Prompts before cleanup
- Prompts before reboot
- Only reboots containers that require it
- Captures apt failure output automatically
- Won’t require rerun just to see errors

---

# ⚠️ MIT License Notice / Use At Your Own Risk

This project is licensed under the MIT License.

That means:
- You are free to use, modify, and distribute this however you want.
- There is **no warranty** or guarantee of fitness for any purpose.
- You assume all responsibility for what this script does in your environment.

This script performs package upgrades and optional reboots across multiple containers.  
If you run it against production systems, that decision is yours.

**Do not run this blindly in environments you do not understand.**  
Test first. Know what your containers do. Be an adult.

---

# 🧰 Requirements

- Proxmox VE host
- LXC containers using apt (Debian/Ubuntu)
- Root shell on host

---

# 🗺 Possible Future Improvements

- Discord/webhook summary
- Multi-node cluster support
- Dry-run mode
- Patch scheduler
- Tag/label-based container selection