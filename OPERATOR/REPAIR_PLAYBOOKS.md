# Repair Playbooks

## Integrity Gate Failure

First command:

```sh
ruby OPERATOR/integrity_gate.rb
```

Read the first failing gate. Do not jump to full deploy. Most failures are inventory drift, frontend rules, relayd/domain mismatch, or missing generated assets.

## App CI Failure On VPS

First command:

```sh
zsh OPENBSD/sh/vps_ci.sh <app>
```

Keep one run at a time. If npm or sass touches root-owned cache, export `HOME=/home/<app>` and `NPM_CONFIG_CACHE=/home/<app>/.npm`.

## MASTER Dead Tap After Deploy

First commands:

```sh
cd /home/dev/pub4/MASTER/web
RAILS_ENV=production rails assets:precompile
doas rcctl restart master
```

Then open `https://ai.brgen.no`, tap to start, and inspect whether the prompt appears. If the digest is stale, rerun the deploy path that includes `master_web_assets_gate`.

## relayd Or Domain Drift

First commands:

```sh
ruby RAILS/domain_alignment_gate.rb
ruby OPENBSD/deploy_smoke_gate.rb
```

Compare `rails/apps.yml`, `master.json`, `openbsd/etc/relayd.conf`, and acme/NSD config. Restart relayd only after the config is coherent.

## pf Lockout

Use the VMM host:

```sh
ssh server4
vmctl console vm23
doas pfctl -t bruteforce -T flush
```

Do not keep reconnecting from the blocked client.

## TTS Silent

Check host binary availability:

```sh
command -v edge-tts || command -v espeak
```

If neither exists, install or configure a fallback. Do not debug web routes first if synthesis cannot run.
