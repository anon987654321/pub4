# SSH access — workstation, VMM host, VM, GitHub

Operator notes from live verification and [OpenBSD
Amsterdam](https://www.openbsd.amsterdam) docs research (2026-06-25). Canonical
network table remains in `README.md`.

## Architecture

```
Mac (workstation)
 ├─ ssh server4 / ssh dev     → server4.openbsd.amsterdam:31415  (VMM host, vmd)
 └─ ssh brgen / ssh brgen.no  → brgen.no:22                      (vm23 guest, apps)
        └─ /home/dev/pub4
```

| Layer | Hostname | Port | Role |
|-------|----------|------|------|
| VMM host | `server4.openbsd.amsterdam` | 31415 | Runs `vmd(8)`; `vmctl` console/stop/start |
| VM guest | `brgen.no` / `brgen.openbsd.amsterdam` | 22 | vm23 — Rails, MASTER, NSD, relayd |
| Backup | `wingman1.openbsd.amsterdam` | 31415 | `s4vm23@…` — 10G openrsync backup |

Verified on host (`ssh server4`):

```
vm23   owner: dev   state: running
```

Provider pattern: **s{server}vm{vmid}** → this VM is **s4vm23** (server 4, vm
23).

## Workstation `~/.ssh/config`

```sshconfig
Host server4 dev
  HostName server4.openbsd.amsterdam
  User dev
  Port 31415
  IdentityFile ~/.ssh/id_ed25519_brgen
  IdentitiesOnly yes

Host brgen brgen.no
  HostName brgen.no
  User dev
  IdentityFile ~/.ssh/id_ed25519_brgen
  IdentitiesOnly yes

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
```

Quick test:

```zsh
ssh -o BatchMode=yes server4 hostname    # → server4.openbsd.amsterdam
ssh -o BatchMode=yes brgen hostname      # → brgen.openbsd.amsterdam
ssh -T git@github.com                    # → Hi anon987654321! …
```

## Two keys, same filename

The deployment key (`id_ed25519_brgen`) is **not** the same file on Mac vs VM.

| Location | Comment | Purpose |
|----------|---------|---------|
| Mac `~/.ssh/id_ed25519_brgen` | `dev@brgen.no vm23 server4` | SSH to VMM host + VM (provider provisioning key) |
| VM `~/.ssh/id_ed25519_brgen` | `oowae5a@gmail.com` | GitHub SSH on VPS (`anon987654321`) |

Same path, different key material. Do not overwrite one with the other.

**GitHub from Mac:** copy the VM's GitHub key to `~/.ssh/id_ed25519_github`
(separate identity file). Adding the Mac deployment pubkey to GitHub via `gh
ssh-key add` failed on 2026-06-25 because `gh` token on the VM is expired (`HTTP
401`). Re-auth: `ssh brgen` → `gh auth login` → `gh ssh-key add -t "Mac"
~/.ssh/id_ed25519_brgen.pub` (from Mac, pipe pubkey), or add manually at GitHub
→ Settings → SSH keys.

Public deployment key (safe to share): see `priv/ssh/id_ed25519_brgen.pub` in
repo.

## VMM host (server4)

Per [onboard.html](https://www.openbsd.amsterdam/onboard.html):

```zsh
ssh -e none -p 31415 -o VerifyHostKeyDNS=yes dev@server4.openbsd.amsterdam
# or: ssh server4
```

Same username + pubkey as the VM. User is in `_vmdusers` for socket access to
`vmd`.

```zsh
vmctl status vm23
vmctl console vm23      # serial console; exit with ~.  Human recovery only — not for agents.
vmctl stop -fw vm23     # NEVER autonomous — causes downtime
vmctl start -c vm23
doas pkill -9 -xf "vmd: vm23"   # hung VM ([known.html](https://www.openbsd.amsterdam/known.html))
```

`OPENBSD/vps_console*.exp` scripts require `I_UNDERSTAND_CONSOLE_RISK=1` (see
`OPENBSD/RUNBOOK.md`).

Recovery when VM SSH is pf-blocked:

```zsh
ssh server4
vmctl console vm23
# login → doas pfctl -t bruteforce -T flush
```

## VM (brgen / vm23)

```zsh
ssh brgen
cd /home/dev/pub4 && git pull --ff-only
```

- OpenBSD **7.8** on VM (provider ships **7.9** — see
  [upgrade.html](https://www.openbsd.amsterdam/upgrade.html)).
- Initial root password (fresh installs): `awk '{print $NF}'
  ~/.ssh/authorized_keys`
- PTR / rDNS from inside VM only:
  [ptr.html](https://www.openbsd.amsterdam/ptr.html) (`ptr4` / `ptr6` token API)
- Backup: [backup.html](https://www.openbsd.amsterdam/backup.html) — `openrsync`
  over the `Host wingman1` stanza in dev's `~/.ssh/config`. **Port 31415, not
  22** — the host pings from 1 ms away and refuses 22, so a missing `Port` line
  reads as "the backup server is down". That line was absent, and
  `backup_priv.sh` passed the FQDN rather than the alias, which bypassed the
  stanza's user, key and host-key policy as well. Both fixed 2026-08-12; the
  account's `backup/` directory was empty, so nothing had ever been stored.

## OpenBSD Amsterdam doc index

| Topic | URL |
|-------|-----|
| Onboarding / console | https://www.openbsd.amsterdam/onboard.html |
| VMM internals (vmd, dhcpd, autoinstall) | https://www.openbsd.amsterdam/setup.html |
| PTR / reverse DNS | https://www.openbsd.amsterdam/ptr.html |
| Backup (10G free) | https://www.openbsd.amsterdam/backup.html |
| Upgrade (7.9) | https://www.openbsd.amsterdam/upgrade.html |
| Known issues | https://www.openbsd.amsterdam/known.html |
| mosh | https://www.openbsd.amsterdam/mosh.html |
| Server status | https://status.openbsd.amsterdam |
| Physical hosts | https://www.openbsd.amsterdam/servers.html |

## Provider model (summary)

From [setup.html](https://www.openbsd.amsterdam/setup.html):

- Physical Dell hosts (`server1` … `server29`, etc.) each run up to 40 VMs via
  `vmm`/`vmd`.
- VM config: qcow2 disk, static MAC, DHCP fixed lease, autoinstall +
  `siteXX.tgz`.
- SSHFP records in DNS — use `-o VerifyHostKeyDNS=yes` on first connect to host.
- €71/year base VM: 1G RAM, 50G disk, dedicated IPv4 + IPv6 /64.

## Billing / support reference

Include **server4 vm23** in provider correspondence (per operator README).
