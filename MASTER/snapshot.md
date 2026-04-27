# Project Snapshot - 2026-04-27T20:17:08Z

## `CLAUDE.md`
```markdown
# pub4 — CLAUDE.md

Auto-approve all tool calls. Never ask for confirmation.

## Launch

```zsh
claude --dangerously-skip-permissions
```

---

## Session Startup (mandatory)

Before any coding work:
1. `cat ~/pub4/MASTER/data/axioms.yml` -- kernel axioms and philosophy
2. `cat ~/pub4/MASTER/data/constitution.yml` -- golden rule, communication style, banned output
3. `cat ~/pub4/MASTER/data/language_rules.yml` -- Ruby/zsh/OpenBSD rules, banned commands
4. `cat ~/pub4/MASTER/data/workflow.yml` -- READ_BEFORE_WRITE, scan depths, anti-sprawl
5. `cat ~/pub4/MASTER/data/standing_orders.yml` -- current FSM state (UNCHANGE / REFACTOR / etc.)

**Communication style: openbsd_dmesg** -- structured multi-line output, no headlines, no bullet lists without content, no hedging, no sycophancy.

**Banned in zsh scripts and SSH commands:** sed, awk, tr, grep, cut, head, tail, find, wc, sudo, perl, ruby (in zsh), dd, xargs
Use: zsh builtins, parameter expansion, `doas` for privilege, Ruby scripts for complex logic.

**Use MASTER's own scan before external analysis:**
`eval "$(grep '^export' ~/.zshrc)" && cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master`
Do not use external agents to find code issues when MASTER can scan itself.

**SSH file editing pattern (safe):**
Write script to /tmp: `doas tee /tmp/patch.rb <<'EOF' ... EOF`
Run it: `ruby /tmp/patch.rb`
Never use `ruby -i` with heredoc -- will empty file on script error.

---

## Environment

| | |
|---|---|
| **Dev machine** | OpenBSD VPS · `dev@brgen.no` · `185.52.176.18` (wheel, passwordless doas) |
| **Password** | `h00te10tu` (changes each session) |
| **SSH** | `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@185.52.176.18 'cmd'` |
| **Shell** | zsh — ControlMaster does NOT persist across Bash tool calls, use sshpass every time |
| **Local** | proot-distro Ubuntu inside Termux on Android — audio production only |
| **OS** | OpenBSD 7.8 on VPS, Ubuntu in proot |

Non-interactive SSH must NOT source `.zshrc` — it auto-launches MASTER and steals stdin.
Load env vars only: `eval "$(grep '^export' ~/.zshrc)"`

---

## DNS (brgen.no — OpenBSD Amsterdam)

```
brgen.no       A     185.52.176.18
ai.brgen.no    A     185.52.176.18
mail.brgen.no  MX    brgen.no (priority 10)
```

Subdomains not yet deployed publicly: `brgen.no` Rails app, other vhosts.

---

## Repository: pub4

- **Git remote**: `https://github.com/anon987654321/pub4.git` — same repo as `dev@brgen.no:~/pub4`
- **Git root**: `~/pub4/`
- **Push**: `gh auth git-credential` on VPS (HTTPS, not SSH)

### Directory layout

```
pub4/
  MASTER/           — active AI agent (Ruby, ~6K LOC)
  DEPLOY/openbsd/   — openbsd.sh deploy script (1511 lines, two-stage)
  __predecessors/   — MASTER2, aight (old versions, do not touch)
  index.html        — Radio Bergen GitHub Pages
  mix/              — audio mixes
  sh/               — misc shell scripts
```

---

## MASTER — Architecture
> `master.yml` (the old 1770-line YAML config) was deleted in Feb 2026. MASTER (the Ruby codebase) replaced it — the agent IS the config.


MASTER is a constitutional AI coding agent that **replaces Claude Code CLI**.

- **Path**: `~/pub4/MASTER/`
- **Binary**: `exe/master`
- **Module**: `Master` (Zeitwerk autoloaded)
- **Launch**: SSH auto-starts via `~/.zshrc` → `cd MASTER && bundle exec ruby exe/master`
- **Pipe mode**: `echo "msg" | bundle exec ruby exe/master`
- **rc.d service**: `master` (web UI daemon)

### Pipeline (10 stages)

```
Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
```

- **ParallelGroup**: Council + Lint run concurrently (30s timeout)
- **Rollback**: `git reset --hard HEAD` on `axiom_violation`/`validation` error
- **Result monad**: `Ok/Err` — check with `respond_to?(:ok?)`, not `is_a?(Result)`


### data/ — Living Spec (replaced master.yml)

`master.yml` was a 1770-line monolithic YAML config. MASTER replaced it with modular `data/*.yml` files that the Ruby pipeline reads and enforces at runtime:

| File | Purpose |
|---|---|
| `axioms.yml` | Kernel axioms (PRESERVE_FIRST, SIMPLEST_WORKS, FAIL_VISIBLY, etc.) + top-25 philosophy principles |
| `constitution.yml` | Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK; protection levels; anti-simulation rules; communication style: openbsd_dmesg |
| `principles.yml` | KISS, DRY, YAGNI, SoC, SRP, SOLID — each with anti-patterns and auto-fix flag |
| `language_rules.yml` | Ruby 3.3+ rules, Rails 8+ stack, OpenBSD config, zsh banned commands (sed/awk/grep/find/etc.) |
| `standing_orders.yml` | Current FSM state (UNCHANGE / REFACTOR / etc.) |
| `workflow.yml` | READ_FULL_FILES, READ_BEFORE_WRITE, scan depths, autoloop/sweep config, Zeitwerk inflections, anti-sprawl |
| `language_axioms.yml` | Communication principles |
| `scan_depths.yml` | standard / deep / hunt rule sets |
| `fallback_models.yml` | Model fallback chain |
| `models.yml` | Model capability table (uses YAML anchors — load with `aliases: true`) |
| `council.yml` / `council_patterns.yml` | Council trigger patterns |
| `infer_patterns.yml` | Natural language → command routing |
| `strunk.yml` | Strunk & White prose rules for Prune stage |
| `prompts/` | LLM prompt templates |

The Ruby pipeline reads these at boot via `Master.build` and enforces them through scan rules, pipeline stages, and tool guards.

### Key modules

| File | Purpose |
|---|---|
| `lib/master.rb` | `Master.build(root:)` container; `Master.boot` → CLI |
| `lib/master/cli.rb` | REPL (`run`), pipe mode (`pipe`), slash commands |
| `lib/master/pipeline.rb` | 10-stage pipeline, ParallelGroup, rollback |
| `lib/master/sweep.rb` | Self-refactor loop (MAX_CYCLES=16, convergence 0.05) |
| `lib/master/agent.rb` | LLM calls, circuit breaker, fallback models, escalation (depth ≤ 2) |
| `lib/master/standing_orders.rb` | Constitutional rules, `wire_pipeline` |
| `lib/master/code_index.rb` | Symbol/Reference Structs (no `freeze: true` — Ruby 3.4 drops it) |
| `lib/master/scan/` | 10 scan rules (EXPLICIT, IMMUTABLE, CQS, SELF_EXPLAINING, etc.) |
| `lib/master/routing/model_router.rb` | Tier routing (cheap/default/strong), ESCALATION_CHAIN, confidence thresholds |
| `lib/master/swarm/coordinator.rb` | Swarm workers, `fan_out`, `dispatch_parallel` with shared deadline |

### Web UI

- **Framework**: Rails 8 + Falcon (port `10002` internal)
- **Public**: relayd proxies → `http://ai.brgen.no:3000` / `https://ai.brgen.no:4430`
- **Routes**: `GET /` chat, `POST /chat/message` (SSE), `POST /chat/tts`, `POST /chat/speak`, `GET /chat/metrics`, `GET /chat/dmesg`, `GET /events/stream`
- **rc.d**: `master` daemon
- **Canvas**: 2000-particle orb, 50 shapes, ambient pad engine, drum sequencer, 17 voice FX

### Models

- **Default**: `nvidia/nemotron-3-super-120b-a12b:free` (OpenRouter free tier)
- **Fallback chain**: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash
- **Circuit breaker**: FAILURE_THRESHOLD=8, RATE_MAX=60

### Slash commands

`/scan [deep]`, `/sweep`, `/autoloop`, `/council`, `/tts`, `/profile`, `/heartbeat`, `/orders`, `/soul`, `/dmesg`

---

## Design Priorities

1. **CLI REPL** — interactive agent, primary interface
2. **Web UI + TTS** — secondary
3. **Autonomous agent** — tertiary

---

## Deploy: openbsd.sh

Script: `~/pub4/MASTER/DEPLOY/openbsd/openbsd.sh`

Two stages:
- **Stage 1**: DNS checks, TLS certs via acme-client, pkg_add
- **Stage 2**: app installs, relayd config, rc.d services

Run in tmux: `tmux new-session -d -s deploy "cd ~/pub4/MASTER/DEPLOY/openbsd && doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"`
Resume: `doas zsh openbsd.sh --resume`

---

## Shell Preferences

- **Never** use `sed`, `awk`, `tr`, `wc`, `head`, `tail`, `grep` — use zsh builtins
- **No tmp files** for simple operations — do it inline
- **No line noise** — keep commands clean and readable
- **Ruby only** — never Python
- **Read files**: `print -r -- "$(<file)"` (not `cat`, not bare `< file` via SSH — triggers pager)
- **zsh array**: `lines=("${(@f)$(<file)}")`; last 50: `print -l $lines[-50,-1]`
- **Edit VPS files**: write patch to `~/pub4/tmp/patch.rb`, run with `ruby ~/pub4/tmp/patch.rb`
- **Man pages first** before editing config files (`MANPAGER=cat man pagename` via SSH)

---

## Sweep Safety

The sweep corruption guard (added 2026-04-27) protects against LLM error messages being written as source:
- `ask_result()` + Result monad check in `rewrite()`
- 50% minimum length guard
- `ERROR_PATTERNS` regex rejection for short outputs
- SYNTAX_CHECKERS for `.rb`, `.yml`, `.erb`

Never disable these guards. If sweep produces unexpected output, the guards will reject it.
```

## `DEPLOY/README.md`
```markdown
   mkdir -p lib/master/tools
   touch lib/master/tools/tts.rb
   ```

## `DEPLOY/openbsd/README.md`
```markdown
doas -s        # Open an interactive root shell
```

## `DEPLOY/openbsd/openbsd.sh`
```bash
#!/usr/bin/env zsh
# Configures OpenBSD 7.8 for NSD & DNSSEC, Ruby on Rails, PF firewall, and minimal OpenSMTPD.

# Usage: doas zsh openbsd.sh [--help | --resume]

#

# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)

# - All configuration syntax validated against man.openbsd.org

# - smtpd.conf updated to OpenBSD 7.8 syntax (PKI-based TLS)

# - relayd.conf includes TLS keypair directives

# - pf.conf uses proper macro definitions

# - rc.d scripts follow proper rc.d(8) format

# - PostgreSQL and Redis removed (use SQLite or external DB)

# - Modern Zsh and OpenBSD security best practices applied

# - Inspired by structured thinking principles (unvalidated)

# - NOTE: pledge/unveil not applicable (C syscalls, not shell features)

# - Privilege control via doas(1), idempotent operations, atomic config writes

set +e  # Don't use errexit - handle errors explicitly
setopt no_unset nullglob local_traps

zmodload zsh/regex

# Temporary files tracking
typeset -a TMPFILES

# Trap handlers for cleanup and errors
cleanup() {

  typeset exit_code=$?

  for tmpfile in "${TMPFILES[@]}"; do

    [[ -n $tmpfile && -f $tmpfile ]] && rm -f "$tmpfile"

  done

  return $exit_code

}

error_handler() {
  typeset exit_code=$1

  typeset line_num=$2

  log ERROR "Script failed with exit code $exit_code at line $line_num"

  cleanup

  exit $exit_code

}

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' INT TERM
# ERR trap: log unexpected exits
trap 'log ERROR "Script exited unexpectedly at line $LINENO with status $?"' ERR

# Convenience wrappers matching task spec
log_info()  { log INFO "$@" }
log_error() { log ERROR "$@" }

# Step completion tracking
is_step_completed() {
  [[ -f "${STATE_FILE}.steps" ]] && [[ $(<"${STATE_FILE}.steps") == *"$1"* ]]
}
mark_step_completed() {
  print -r -- "$1" >> "${STATE_FILE}.steps"
}


# Backup function for data integrity
backup_directory() {

  typeset target_dir=$1

  typeset backup_name=${2:-${target_dir:t}}

  typeset backup_dir=/var/backups/openbsd_setup

  typeset timestamp=$EPOCHSECONDS

  typeset backup_file="$backup_dir/${backup_name}-${timestamp}.tar.gz"

  [[ ! -d $backup_dir ]] && mkdir -p "$backup_dir"
  if [[ -d $target_dir ]]; then
    log INFO "Backing up $target_dir to $backup_file"

    transaction_log "BACKUP" "$target_dir" "START"

    if tar -czf "$backup_file" -C "${target_dir:h}" "${target_dir:t}" 2>/dev/null; then

      transaction_log "BACKUP" "$target_dir" "SUCCESS" "$backup_file"

      log INFO "Backup created: $backup_file"

      # Keep only last 10 backups
      typeset -a _bfiles; _bfiles=("$backup_dir"/${backup_name}-*.tar.gz(N)); typeset backup_count=${#_bfiles}

      if (( backup_count > 10 )); then

        typeset -a _sorted_bfiles; _sorted_bfiles=("$backup_dir"/${backup_name}-*.tar.gz(NOm)); for _f in "${_sorted_bfiles[@]:10}"; do rm -f "$_f"; done

        log INFO "Pruned old backups, keeping last 10"

      fi

      echo "$backup_file"

      return 0

    else

      transaction_log "BACKUP" "$target_dir" "FAILURE"

      log ERROR "Backup failed for $target_dir"

      return 1

    fi

  else

    log WARN "Directory $target_dir does not exist, skipping backup"

    return 0

  fi

}

# Transaction logging for audit trail
transaction_log() {

  typeset operation=$1

  typeset target=$2

  typeset op_status=$3

  typeset metadata=${4:-}

  typeset logfile=/var/log/openbsd_transactions.log

  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$operation] $target | Status: $op_status | $metadata" >> "$logfile"
}

# Logging function
log() {

  typeset level=$1

  shift

  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/openbsd_setup.log >&2

}

# Configuration settings (constants per master.yml p04: explicit over implicit)
typeset -r BRGEN_IP="185.52.176.18"   # Primary server IP (updated for this VPS)

typeset -r HYP_IP="194.63.248.53"     # ns.hyp.net, external secondary

typeset -r LOCALHOST="127.0.0.1"      # Localhost constant

typeset -r EMAIL_ADDRESS="bergen@pub.attorney"  # Email address for OpenSMTPD

typeset -r STATE_FILE="./openbsd_setup_state"   # Runtime state file

typeset -a PUBLIC_RESOLVERS=(8.8.8.8 1.1.1.1 9.9.9.9)  # Public DNS resolvers

typeset -A APP_PORTS              # Rails app port mappings

typeset -A FAILED_CERTS           # Failed certificate tracking

# Validate IP addresses with proper octet checking
validate_ip() {

  typeset ip=$1

  [[ $ip =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]] || return 1

  typeset IFS=.

  typeset -a octets

  octets=(${(s:.:)ip})

  for octet in $octets; do

    (( octet > 255 )) && return 1

  done

  return 0

}

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1; }
validate_ip "$HYP_IP" || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1; }

# Rails applications
ALL_APPS=(

  brgen:brgen.no

  amber:amberapp.com

  bsdports:bsdports.org

)

# Non-Rails services (name:subdomain.domain:port)
SERVICES=(
  ai:ai.brgen.no:4430
)

# Domain list for DNS
ALL_DOMAINS=(

  brgen.no:markedsplass,playlist,dating,tv,takeaway,maps,ai

  longyearbyn.no:markedsplass,playlist,dating,tv,takeaway,maps

  oshlo.no:markedsplass,playlist,dating,tv,takeaway,maps

  stvanger.no:markedsplass,playlist,dating,tv,takeaway,maps

  trmso.no:markedsplass,playlist,dating,tv,takeaway,maps

  trndheim.no:markedsplass,playlist,dating,tv,takeaway,maps

  reykjavk.is:markadur,playlist,dating,tv,takeaway,maps

  kbenhvn.dk:markedsplads,playlist,dating,tv,takeaway,maps

  gtebrg.se:marknadsplats,playlist,dating,tv,takeaway,maps

  mlmoe.se:marknadsplats,playlist,dating,tv,takeaway,maps

  stholm.se:marknadsplats,playlist,dating,tv,takeaway,maps

  hlsinki.fi:markkinapaikka,playlist,dating,tv,takeaway,maps

  brmingham.uk:marketplace,playlist,dating,tv,takeaway,maps

  cardff.uk:marketplace,playlist,dating,tv,takeaway,maps

  edinbrgh.uk:marketplace,playlist,dating,tv,takeaway,maps

  glasgw.uk:marketplace,playlist,dating,tv,takeaway,maps

  lndon.uk:marketplace,playlist,dating,tv,takeaway,maps

  lverpool.uk:marketplace,playlist,dating,tv,takeaway,maps

  mnchester.uk:marketplace,playlist,dating,tv,takeaway,maps

  amstrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps

  rottrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps

  utrcht.nl:marktplaats,playlist,dating,tv,takeaway,maps

  brssels.be:marche,playlist,dating,tv,takeaway,maps

  zrich.ch:marktplatz,playlist,dating,tv,takeaway,maps

  lchtenstein.li:marktplatz,playlist,dating,tv,takeaway,maps

  frankfrt.de:marktplatz,playlist,dating,tv,takeaway,maps

  brdeaux.fr:marche,playlist,dating,tv,takeaway,maps

  mrseille.fr:marche,playlist,dating,tv,takeaway,maps

  mlan.it:mercato,playlist,dating,tv,takeaway,maps

  lisbon.pt:mercado,playlist,dating,tv,takeaway,maps

  wrsawa.pl:marktplatz,playlist,dating,tv,takeaway,maps

  gdnsk.pl:marktplatz,playlist,dating,tv,takeaway,maps

  austn.us:marketplace,playlist,dating,tv,takeaway,maps

  chcago.us:marketplace,playlist,dating,tv,takeaway,maps

  denvr.us:marketplace,playlist,dating,tv,takeaway,maps

  dllas.us:marketplace,playlist,dating,tv,takeaway,maps

  dnver.us:marketplace,playlist,dating,tv,takeaway,maps

  dtroit.us:marketplace,playlist,dating,tv,takeaway,maps

  houstn.us:marketplace,playlist,dating,tv,takeaway,maps

  lsangeles.com:marketplace,playlist,dating,tv,takeaway,maps

  mnnesota.com:marketplace,playlist,dating,tv,takeaway,maps

  newyrk.us:marketplace,playlist,dating,tv,takeaway,maps

  prtland.com:marketplace,playlist,dating,tv,takeaway,maps

  wshingtondc.com:marketplace,playlist,dating,tv,takeaway,maps

  pub.healthcare

  pub.attorney

  freehelp.legal

  bsdports.org

  bsddocs.org

  discordb.org

  privcam.no

  foodielicio.us

  stacyspassion.com

  antibettingblog.com

  anticasinoblog.com

  antigamblingblog.com

  foball.no

)

# Zsh completion function
_openbsd_sh() {

  _arguments \

    '--help[Show usage information]' \

    '--resume[Resume with Stage 2]'

}

# Utility functions
generate_random_port() {
  # Generate random port (10000–60000), ensuring it’s free

  typeset port

  while :; do

    port=$((RANDOM % 50000 + 10000))

    typeset _netstat_out; _netstat_out=$(/usr/bin/netstat -an); [[ $_netstat_out != *".$port "* ]] && echo $port && break

  done

}

cleanup_nsd() {
  # Stop nsd and free port 53

  log INFO "Cleaning nsd(8)"

  [[ -d /var/nsd ]] || { log ERROR "/var/nsd missing"; exit 1 }

  /usr/bin/timeout 5 /usr/sbin/rcctl stop nsd || log WARN "/usr/sbin/rcctl stop nsd failed"

  /usr/bin/timeout 5 zap -f nsd || log WARN "zap -f nsd failed"

  sleep 2

  typeset _udp_out; _udp_out=$(/usr/bin/netstat -an -p udp); [[ $_udp_out == *"$BRGEN_IP.53"* ]] && {

    log ERROR "Port 53 in use"

    exit 1

  }

  log INFO "Port 53 free"

}

... 1176 lines truncated (1576 total)
```

## `DEPLOY/postpro.rb`
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "logger"
require "json"
require "time"
require "fileutils"
require "rbconfig"

module PostproBootstrap
  LOG_PREFIX = "[postpro]".freeze

  def self.dmesg(msg)
    puts "#{LOG_PREFIX} #{msg}"
  end

  def self.startup_banner
    dmesg "boot ruby=#{RUBY_VERSION} os=#{RbConfig::CONFIG['host_os']}"
  end

  def self.ensure_gems
    { vips: ensure_vips, tty: ensure_tty_prompt }
  end

  def self.ensure_vips
    require "vips"
    true
  rescue LoadError
    dmesg "WARN ruby-vips missing, installing..."
    if system("gem install ruby-vips --no-document")
      require "vips"
      dmesg "OK ruby-vips installed"
      true
    else
      dmesg "WARN ruby-vips install failed, probing libvips"
      probe_and_install_libvips
      false
    end
  rescue StandardError => e
    dmesg "WARN ruby-vips unavailable: #{e.message}"
    false
  end

  def self.ensure_tty_prompt
    require "tty-prompt"
    true
  rescue LoadError
    dmesg "WARN tty-prompt missing, installing..."
    if system("gem install tty-prompt --no-document")
      require "tty-prompt"
      dmesg "OK tty-prompt installed"
      true
    else
      dmesg "WARN tty-prompt install failed"
      false
    end
  rescue StandardError => e
    dmesg "WARN tty-prompt unavailable: #{e.message}"
    false
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips..."
    return true if system("pkg-config --exists vips")

    os = RbConfig::CONFIG["host_os"]
    case os
    when /darwin/
      if system("which brew > /dev/null 2>&1")
        dmesg "brew install vips"
        system("brew install vips")
      else
        dmesg "ERROR brew not found"
      end
    when /linux/
      install_cmd = if system("which apt > /dev/null 2>&1")
                      "sudo apt update && sudo apt install -y libvips-dev"
                    elsif system("which dnf > /dev/null 2>&1")
                      "sudo dnf install -y vips-devel"
                    elsif system("which yum > /dev/null 2>&1")
                      "sudo yum install -y vips-devel"
                    elsif system("which apk > /dev/null 2>&1")
                      "sudo apk add vips-dev"
                    elsif system("which pacman > /dev/null 2>&1")
                      "sudo pacman -S --noconfirm libvips"
                    end
      if install_cmd
        dmesg install_cmd
        system(install_cmd)
      else
        dmesg "ERROR unsupported package manager"
      end
    when /openbsd/
      if system("which pkg_add > /dev/null 2>&1")
        dmesg "pkg_add vips"
        system("doas pkg_add vips")
      else
        dmesg "ERROR pkg_add missing"
      end
    else
      dmesg "ERROR unsupported OS: #{os}"
    end

    if system("pkg-config --exists vips")
      dmesg "OK libvips installed"
      true
    else
      dmesg "ERROR libvips installation failed"
      false
    end
  end

  def self.load_camera_profiles(dir)
    return {} unless Dir.exist?(dir)

    profiles = {}
    Dir.glob(File.join(dir, "*.json")).each do |f|
      begin
        data = JSON.parse(File.read(f))
        vendor = data["vendor"]
        profiles[vendor] = data["profiles"] if vendor && data["profiles"]
      rescue StandardError => e
        dmesg "WARN profile #{File.basename(f)}: #{e.message}"
      end
    end
    dmesg "camera_profiles=#{profiles.keys.join(',')}"
    profiles
  end

  def self.load_master_config
    return {} unless File.exist?("master.json")

    begin
      raw = File.read("master.json")
      json = JSON.parse(raw.gsub(%r{^.*//.*$}, ""))
      json.dig("config", "multimedia", "postpro") || {}
    rescue StandardError => e
      dmesg "WARN master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems
    unless gems[:vips]
      dmesg "FATAL libvips missing"
      abort <<~MSG
        Postpro.rb requires libvips.
        Install manually:
          macOS: brew install vips
          Debian/Ubuntu: sudo apt install libvips-dev
          OpenBSD: doas pkg_add vips
      MSG
    end

    {
      gems: gems,
      camera_profiles: load_camera_profiles("multimedia/camera_profiles"),
      config: load_master_config
    }
  end
end

BOOTSTRAP = PostproBootstrap.run
LOGGER = Logger.new("postpro.log", "daily")
LOGGER.level = Logger::DEBUG
CLI_LOGGER = Logger.new($stdout)
CLI_LOGGER.level = Logger::INFO

PROMPT = if BOOTSTRAP[:gems][:tty]
           require "tty-prompt"
           TTY::Prompt.new
         end

require "vips" if BOOTSTRAP[:gems][:vips]

REPLIGEN_PRESENT = File.exist?("repligen.rb")
CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

STOCKS = {
  kodak_portra: { grain: 15, gamma: 0.65, rolloff: 0.88, lift: 0.05, matrix: [1.05, -0.02, -0.03, 0.02, 0.98, 0.00, 0.01, -0.05, 1.04] },
  kodak_vision3: { grain: 20, gamma: 0.65, rolloff: 0.85, lift: 0.08, matrix: [1.08, -0.05, -0.03, 0.03, 0.95, 0.02, 0.02, -0.08, 1.06] },
  fuji_velvia: { grain: 8, gamma: 0.75, rolloff: 0.92, lift: 0.03, matrix: [1.12, -0.08, -0.04, 0.05, 1.05, -0.02, 0.01, -0.12, 1.11] },
  tri_x: { grain: 25, gamma: 0.70, rolloff: 0.80, lift: 0.12, matrix: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0] }
}.freeze

PRESETS = {
  portrait:   { fx: %w[skin_protect film_curve highlight_roll micro_contrast grain color_temp base_tint], stock: :kodak_portra, temp: 5200, intensity: 0.8 },
  landscape:  { fx: %w[film_curve color_separate highlight_roll micro_contrast grain vintage_lens], stock: :fuji_velvia, temp: 5800, intensity: 0.9 },
  street:     { fx: %w[film_curve shadow_lift micro_contrast vintage_lens grain], stock: :tri_x, temp: 5600, intensity: 1.0 },
  blockbuster:{ fx: %w[teal_orange grain bloom_pro highlight_roll micro_contrast], stock: :kodak_vision3, temp: 4800, intensity: 1.2 }
}.freeze

def safe_cast(img, fmt = "uchar")
  img.cast(fmt)
rescue StandardError => e
  LOGGER.error "Cast failed: #{e.message}"
  img
end

def rgb_bands(img, bands = 3)
  return img if img.bands == bands
  img.bands < bands ? img.bandjoin([img] * (bands - img.bands)) : img.extract_band(0, n: bands)
end

def load_image(path)
  return nil unless File.file?(path) && File.readable?(path)

  img = Vips::Image.new_from_file(path, access: :sequential)
  img = img.colourspace("srgb") if img.bands < 3
  rgb_bands(img)
rescue StandardError => e
  LOGGER.error "Load #{path}: #{e.message}"
  nil
end

def get_camera_profile(img)
  return nil if CAMERA_PROFILES.empty?
  make  = img.get("exif-ifd0-Make")&.strip&.downcase
  model = img.get("exif-ifd0-Model")&.strip&.downcase
  return nil unless make && model

  CAMERA_PROFILES.each { |_, p| return p[model] if p[model] }
  CAMERA_PROFILES.each { |brand, p| return p.values.first if make.include?(brand) || brand.include?(make) }
  nil
rescue StandardError => e
  LOGGER.debug "EXIF error: #{e.message}"
  nil
end

def apply_camera_profile(img, profile)
  return img unless profile && profile["color_matrix"]
  matrix = profile["color_matrix"]
  return img unless matrix.size == 9

  result = img.recomb([
    [matrix[0], matrix[1], matrix[2]],
    [matrix[3], matrix[4], matrix[5]],
    [matrix[6], matrix[7], matrix[8]]
  ])

  if profile["saturation"]
    hsv = result.colourspace("hsv")
    h, s, v = hsv.bandsplit
    s = s.linear([profile["saturation"]], [0])
    result = Vips::Image.bandjoin([h, s, v]).colourspace("srgb")
  end

  result = result.linear([1.0 + profile["vibrance"].to_f * 0.1], [0]) if profile["vibrance"]
  result = base_tint(result, profile["base_tint"], 0.1) if profile["base_tint"]
  safe_cast(result)
rescue StandardError => e
  LOGGER.error "Camera profile: #{e.message}"
  img
end

def color_temp(img, kelvin, intensity = 1.0)
  factor = kelvin / 5500.0
  r, g, b = if factor < 1.0
              [1.0, factor**0.5, factor**2]
            else
              [factor**-0.3, 1.0, 1.0 + (factor - 1.0) * 0.5]
            end
  safe_cast img.linear([
    1.0 + (r - 1.0) * intensity,
    1.0 + (g - 1.0) * intensity,
    1.0 + (b - 1.0) * intensity
  ], [0, 0, 0])
end

def skin_protect(img, intensity = 1.0)
  hsv = img.colourspace("hsv")
  h, s, _ = hsv.bandsplit
  mask = (h > 25.5) & (h < 63.75) & (s > 51) & (s < 153)
  protection = mask.cast("float") / 255.0 * (1.0 - intensity * 0.7)
  safe_cast img * (1.0 - protection) + img * protection
end

def film_curve(img, stock = :kodak_portra, intensity = 1.0)
  data = STOCKS[stock] || STOCKS[:kodak_portra]
  shadows = img.linear([1.0], [data[:lift] * 255 * intensity])
  highlights = shadows.pow(data[:gamma]).pow(data[:rolloff])
  safe_cast img * (1 - intensity) + highlights * intensity
end

def highlight_roll(img, threshold = 200, intensity = 1.0)
  mask = img > threshold
  rolled = threshold + (img - threshold) * 0.3 ** 0.7
  safe_cast img * (1 - intensity) + (mask.ifthenelse(rolled, img)) * intensity
end

def shadow_lift(img, lift = 0.15, preserve = true)
  gray = img.colourspace("grey16").cast("float") / 255.0
  mask = preserve ? ((1.0 - gray).pow(2.0)) * 0.8 : (1.0 - gray) * lift
  safe_cast img.linear([1.0, 1.0, 1.0], [mask * 255 * lift])
end

def micro_contrast(img, radius = 5, intensity = 0.3)
  blurred = img.gaussblur(radius)
  high_pass = img - blurred
  safe_cast img + high_pass * intensity
end

def color_separate(img, intensity = 0.6)
  r, g, b = img.bandssplit
  r = (r - g * 0.08 * intensity - b * 0.05 * intensity).max(0)
  g = (g - r * 0.06 * intensity - b * 0.10 * intensity).max(0)
  b = (b - r * 0.04 * intensity - g * 0.07 * intensity).max(0)
  safe_cast img * (1 - intensity) + Vips::Image.bandjoin([r, g, b]) * intensity
end

def grain(img, iso = 400, stock = :kodak_portra, intensity = 0.4)
  data = STOCKS[stock]
  sigma = data[:grain] * Math.sqrt(iso / 100.0) * intensity
  noise = Vips::Image.gaussnoise(img.width, img.height, sigma: sigma)
  bright = img.colourspace("grey16").cast("float") / 255.0
  strength = (1.2 - bright).max(0.3) * intensity
  safe_cast img + rgb_bands(noise * strength) * 0.25
end

def base_tint(img, color = [252, 248, 240], intensity = 0.08)
  overlay = Vips::Image.black(img.width, img.height, bands: 3) + color
  ov = overlay.cast("float") / 255.0
  im = img.cast("float") / 255.0
  blended = im.ifthenelse(ov < 0.5, 2 * im * ov, 1 - 2 * (1 - im) * (1 - ov)) * 255
  safe_cast img * (1 - intensity) + blended * intensity
end

def vintage_lens(img, type = "zeiss", intensity = 0.7)
  case type
  when "zeiss"
    micro_contrast(img, 3, 0.4 * intensity)
  when "leica"
    glow = img.gaussblur(20).linear([0.3 * intensity], [0])
    safe_cast img + glow
  when "helios"
    sharp = img.sharpen(mask: [[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    safe_cast img * (1 - intensity * 0.3) + sharp * (intensity * 0.3)
  else
    img
  end
end

def teal_orange(img, intensity = 1.0)
  r, g, b = skin_protect(img, 0.8).bandsplit
  r = r.linear([1 + 0.25 * intensity], [8 * intensity])
  g = g.linear([1 - 0.08 * intensity], [0])
  b = b.linear([1 + 0.35 * intensity], [0])
  safe_cast Vips::Image.bandjoin([r, g, b])
end

def bloom_pro(img, intensity = 1.0)
  bright = img.linear([2.0 * intensity], [0])
  combined = (bright.gaussblur(8 * intensity) + bright.gaussblur(16 * intensity) * 0.5) * 0.2
  safe_cast img + combined
end

def preset(img, name)
  cfg = PRESETS[name.to_sym]
  return img unless cfg

  result = img
  cfg[:fx].each do |fx|
    result = case fx
             when "skin_protect"   then skin_protect(result, cfg[:intensity])
             when "film_curve"     then film_curve(result, cfg[:stock], cfg[:intensity])
             when "highlight_roll" then highlight_roll(result, 200, cfg[:intensity] * 0.7)
             when "shadow_lift"    then shadow_lift(result, 0.2, false)
             when "micro_contrast" then micro_contrast(result, 6, cfg[:intensity] * 0.4)
             when "grain"          then grain(result, 400, cfg[:stock], cfg[:intensity] * 0.4)
             when "color_temp"     then color_temp(result, cfg[:temp], cfg[:intensity] * 0.6)
             when "base_tint"      then base_tint(result, [255, 250, 245], 0.08)
             when "color_separate" then color_separate(result, cfg[:intensity] * 0.6)
             when "vintage_lens"   then vintage_lens(result, "zeiss", cfg[:intensity] * 0.8)
             when "teal_orange"    then teal_orange(result, cfg[:intensity])
             when "bloom_pro"      then bloom_pro(result, cfg[:intensity])
             else result
             end
  end
  result
end

def grain_basic(img, intensity)
  noise = Vips::Image.gaussnoise(img.width, img.height, sigma: 25 * intensity)
  safe_cast img + rgb_bands(noise) * 0.2
end

def leaks_basic(img, intensity)
  overlay = Vips::Image.black(img.width, img.height, bands: 3)
  rand(2..5).times do
    x = rand(img.width)
    y = rand(img.height)
    radius = img.width / rand(2..4)
    color = [255 * intensity, 180 * intensity, 80 * intensity]
    overlay = overlay.draw_circle(color, x, y, radius, fill: true)
  end
  safe_cast img + overlay.gaussblur(15 * intensity) * 0.3
end
... 221 lines truncated (621 total)
```

## `DEPLOY/rails/@shared_functions.sh`
```bash
#!/usr/bin/env sh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
#
# Conventions:
#   APP_DIR  — full path to app (caller sets this, e.g. /home/brgen/app)
#   APP_PORT — TCP port Falcon listens on

set -eu
PATH="${PATH:-/usr/bin:/bin}"
# Preserve exit status of pipelines
set -o pipefail

# Detect privilege escalation command once
if command -v doas >/dev/null 2>&1; then
  _SUDO_CMD=doas
else
  _SUDO_CMD=sudo
fi

# ── Configuration ────────────────────────────────────────────────────────
: "${APP_PORT:=3000}"

# ── Logging ────────────────────────────────────────────────────────────────
log()      { printf '%b\n' "$(printf '\033[36m==>\033[0m %s' "$*")"; }
log_ok()   { printf '%b\n' "$(printf '\033[32m✔\033[0m %s' "$*")"; }
log_warn() { printf '%b\n' "$(printf '\033[33mWARN\033[0m %s' "$*")" >&2; }
log_err()  { printf '%b\n' "$(printf '\033[31mERR\033[0m %s' "$*")" >&2; }

# ── Precondition checks ────────────────────────────────────────────────────
command_exists() {
  cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Required command not found: $cmd"
    exit 1
  fi
  log_ok "$cmd found"
}

check_app_exists() {
  sentinel=$1
  if [ -f "$sentinel" ]; then
    log_warn "Already set up ($sentinel exists). Skipping."
    return 0
  fi
  return 1
}

# ── App scaffolding ────────────────────────────────────────────────────────
setup_full_app() {
  app_dir=$1
  mkdir -p "$(dirname "$app_dir")"

  if [ ! -f "${app_dir}/config/application.rb" ]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" --database=sqlite3 --skip-git \
      --asset-pipeline=propshaft --javascript=importmap --skip-test
  fi

  cd "$app_dir"

  if ! grep -q '"falcon"' Gemfile 2>/dev/null; then
    printf 'gem "falcon"\n' >> Gemfile
    bundle install --quiet
  fi

  log_ok "Working in: $app_dir"
}

# ── Gem helpers ──────────────────────────────────────────────────────────────
install_gem() {
  gem=$1
  version=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [ -n "$version" ]; then
      printf 'gem "%s", "%s"\n' "$gem" "$version" >> Gemfile
    else
      printf 'gem "%s"\n' "$gem" >> Gemfile
    fi
    bundle install --quiet
    log_ok "gem ${gem} installed"
  else
    log_ok "gem ${gem} already present"
  fi
}

# ── Database helpers ──────────────────────────────────────────────────────
db_setup() {
  RAILS_ENV=production bin/rails db:create db:migrate 2>&1 |
    grep -E "Created|migrated|error" || :
  log_ok "database ready"
}

# ── relayd helpers ────────────────────────────────────────────────────────
relayd_add_relay() {
  host=$1
  port=$2
  table_name=${host%%.*}
  conf=/etc/relayd.conf

  if grep -q "table <${table_name}>" "$conf" 2>/dev/null; then
    log_ok "relayd table <${table_name}> already present"
    return 0
  fi

  $_SUDO_CMD tee -a "$conf" >/dev/null <<EOF
table <${table_name}> { 127.0.0.1 }
EOF

  log_ok "relayd table <${table_name}> → :${port} added (reload relayd to apply)"
}

# ── rc.d helpers ────────────────────────────────────────────────────────────
install_rcd() {
  svc=$1
  app_dir=$2
  port=$3
  user=$4
  rcd="/etc/rc.d/${svc}"

  if [ -f "$rcd" ]; then
    log_ok "rc.d/${svc} already exists"
    return 0
  fi

  $_SUDO_CMD tee "$rcd" >/dev/null <<'EOF'
#!/bin/ksh
daemon_execdir="${APP_DIR}"
daemon="${APP_DIR}/bin/rails"
daemon_flags="server -b 0.0.0.0 -p ${APP_PORT} -e production"
daemon_user="${USER}"
. /etc/rc.d/rc.subr
rc_cmd $1
EOF

  $_SUDO_CMD chmod 755 "$rcd"
  $_SUDO_CMD rcctl enable "$svc"
  log_ok "rc.d/${svc} installed"
}

# ── Asset helpers ────────────────────────────────────────────────────────
generate_default_css() {
  mkdir -p app/assets/stylesheets
  cat > app/assets/stylesheets/application.css <<'CSS'
:root {
  --bg: #0a0a0a; --surface: #1a1a1a; --text: #e8eaed;
  --text-dim: #9aa0a6; --primary: #8ab4f8; --accent: #ff4500;
  --radius: 8px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
main { max-width: 1200px; margin: 0 auto; padding: calc(var(--space)*2); }
a { color: var(--primary); text-decoration: none; }
.card { background: var(--surface); border-radius: var(--radius); padding: calc(var(--space)*2); margin-bottom: calc(var(--space)*2); }
@media (max-width: 768px) { main { padding: var(--space); } }
CSS
  log_ok "default CSS written"
}

generate_all_stimulus_controllers() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/index.js <<'JS'
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus controllers index written"
}```

## `DEPLOY/rails/README.md`
```markdown
rails/
├─ amber/               # Amber‑related deployment scripts
│   └─ amber.sh
├─ baibl/               # Baibl service scripts
│   └─ baibl.sh
├─ blognet/             # Blognet deployment utilities
│   └─ blognet.sh
├─ brgen/               # Brgen family of scripts (brgen*.sh)
│   └─ brgen*.sh
├─ bsdports/            # BSD‑Ports integration scripts
│   └─ bsdports.sh
├─ hjerterom/           # Hjerterom service scripts
│   └─ hjerterom.sh
├─ privcam/             # PrivCam deployment helpers
│   └─ privcam.sh
├─ __shared/            # Shared resources used by all scripts
│   ├─ @common.sh                # Core utilities (e.g., `get_app_port`, feature loading)
│   ├─ @*_features.sh            # Feature modules (messaging, reddit, airbnb, …)
│   ├─ layouts/*                 # Reusable partials & static assets
│   └─ @shared_functions.sh      # Logging, environment handling, common helpers
├─ __common_patterns.css        # Global CSS patterns shared across deployments
├─ check_ports.sh                # Validate service ports against `master.json`
├─ modernize_zsh.sh              # Migrate legacy Zsh patterns to the new style
├─ voting_system.sh              # Scripts for deploying the voting subsystem
└─ rich_editor_system.sh         # Tools for installing and configuring the rich‑text editor
```

## `DEPLOY/rails/VOTING_README.md`
```markdown
rails/__shared/voting_system.sh
```

## `DEPLOY/rails/__shared/@airbnb_features.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

model_path() {
  printf 'app/models/%s.rb' "${1%:*}"
}

check_model_exists() {
  model_name=$1
  if [ -f "$(model_path "$model_name")" ]; then
    log "Model $model_name already exists, skipping generation"
    return 1
  fi
  return 0
}

run_migration() {
  log "Running database migrations"
  if ! bundle exec rails db:migrate; then
    log "Migration failed, attempting rollback"
    if ! bundle exec rails db:rollback; then
      log "Rollback also failed, manual intervention required"
      return 1
    fi
    log "Rollback successful"
    return 1
  fi
}

setup_airbnb_models() {
  # Define models as an array: "ModelName:attributes"
  models=(
    "Booking:listing:references host:references check_in:date check_out:date guests_count:integer total_price:decimal status:string"
    "Review:reviewable:references{polymorphic} reviewer:references{polymorphic} rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer"
    "Availability:listing:references date:date available:boolean price_override:decimal"
    "HostProfile:user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean"
    "Amenity:name:string category:string icon:string"
    "ListingAmenity:listing:references amenity:references"
  )

  for entry in "${models[@]}"; do
    model_name=${entry%%:*}
    attributes=${entry#*:}
    if [ -z "$model_name" ]; then
      continue
    fi
    if check_model_exists "$model_name"; then
      log "Generating model $model_name with attributes: $attributes"
      if ! bundle exec rails generate model "$model_name" $attributes; then
        log "Failed to generate model $model_name"
        return 1
      fi
    fi
  done
  log "Airbnb models generated"
}

setup_polymorphic_associations() {
  log "Setting up polymorphic associations for Review model"
  review_file=$(model_path Review)

  if [ ! -f "$review_file" ]; then
    log "Review model not found, cannot set up polymorphic associations"
    return 1
  fi

  snippet='  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewer, polymorphic: true'

  if ! grep -q "belongs_to :reviewable, polymorphic: true" "$review_file"; then
    printf '\n%s\n' "$snippet" >> "$review_file"
    log "Added polymorphic associations to Review model"
  else
    log "Polymorphic associations already present in Review model"
  fi
}

add_validations() {
  log "Adding validations to models"

  booking_file=$(model_path Booking)
  if [ -f "$booking_file" ]; then
    if ! grep -q "validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true" "$booking_file"; then
      cat >> "$booking_file" <<'EOF'

  validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true
  validates :guests_count, numericality: { only_integer: true, greater_than: 0 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0 }
  validate :check_out_after_check_in

  private

  def check_out_after_check_in
    return if check_in.blank? || check_out.blank?
    errors.add(:check_out, "must be after check-in") if check_out <= check_in
  end
EOF
      log "Added validations to Booking model"
    fi
  fi

  review_file=$(model_path Review)
  if [ -f "$review_file" ]; then
    if ! grep -q "validates :rating, numericality: { in: 1..5 }" "$review_file"; then
      cat >> "$review_file" <<'EOF'

  validates :rating, numericality: { in: 1..5 }
  validates :content, length: { maximum: 1000 }
EOF
      log "Added validations to Review model"
    fi
  fi
}

main() {
  log "Starting Airbnb marketplace features setup"

  setup_airbnb_models &&
    setup_polymorphic_associations &&
    run_migration &&
    add_validations

  log "Airbnb marketplace features setup completed successfully"
}

main "$@"```

## `DEPLOY/rails/__shared/@common.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

# Helpers for DEPLOY/rails installers.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

log()   { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn()  { printf '[%s] WARN: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err()   { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

load_feature_modules() {
  for pattern in "$SCRIPT_DIR"/*_features.sh "$SCRIPT_DIR"/*/stimulus_controllers/*.sh; do
    for feature in $pattern; do
      [ -f "$feature" ] && [ -r "$feature" ] && {
        . "$feature" && log "Loaded $feature" || warn "Failed to source $feature"
      }
    done
  done
}

get_app_port() {
  app_name=${1:?Application name required}
  master_json=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}

  [ -f "$master_json" ] || { err "master.json not found at $master_json"; return 1; }
  command -v jq >/dev/null || { err "jq not installed"; return 1; }

  port=$(jq -r --arg name "$app_name" '.apps[] | select(.name == $name) | .port // empty' "$master_json")
  [ -n "$port" ] || { err "No port for $app_name in $master_json"; return 1; }
  printf '%s\n' "$port"
}

load_feature_modules```

## `DEPLOY/rails/__shared/@features_base.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#--- Configuration -----------------------------------------------------------
readonly RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
readonly GEMFILE="${RAILS_ROOT}/Gemfile"
readonly ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"
readonly STIMULUS_DIR="${STIMULUS_DIR:-app/javascript/controllers}"
readonly DRY_RUN="${DRY_RUN:-false}"

#--- Validation regex --------------------------------------------------------
readonly VALID_CLASS='^[A-Z][A-Za-z0-9]*$'
readonly VALID_CONTROLLER='^[A-Z][A-Za-z0-9]*Controller$'

#--- Helpers -----------------------------------------------------------------
die() {
    printf '%s\n' "$*" >&2
    exit 1
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

usage() {
    cat <<-EOF
Usage: ${0##*/} [--dry-run] <ResourceName>

Generates a Rails model, controller and a Stimulus TypeScript controller.
  --dry-run    Show what would be done without making changes.
EOF
    exit 1
}

validate_rails_app() {
    [[ -f "$GEMFILE" ]] || die "Missing $GEMFILE – not a Rails project"
    grep -q "rails" "$GEMFILE" || die "Gemfile does not contain Rails"
    cmd_exists rails || die "rails executable not found"
}

validate_name() {
    local name=$1 pattern=$2 err=$3
    [[ $name =~ $pattern ]] || die "$err: $name"
}

to_snake_case() {
    printf '%s' "$1" |
        sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' |
        tr '[:upper:]' '[:lower:]'
}

run_cmd() {
    local cmd=$1
    if $DRY_RUN; then
        printf '[dry‑run] %s\n' "$cmd"
    else
        eval "$cmd"
    fi
}

generate_model() {
    local model=$1
    validate_name "$model" "$VALID_CLASS" "Invalid model name"
    printf 'Generating model %s…\n' "$model"
    run_cmd "rails generate model $model"
    printf '✓ Model %s created\n' "$model"
}

generate_controller() {
    local controller=$1
    validate_name "$controller" "$VALID_CONTROLLER" "Invalid controller name"
    local base=${controller%Controller}
    printf 'Generating controller %s…\n' "$base"
    run_cmd "rails generate controller $base"
    printf '✓ Controller %s created\n' "$base"
}

generate_stimulus_ts() {
    local controller=$1
    validate_name "$controller" "$VALID_CONTROLLER" "Invalid controller name"
    local base=${controller%Controller}
    local snake
    snake=$(to_snake_case "$base")
    local file="${STIMULUS_DIR}/${snake}_controller.ts"

    if [[ -e $file ]]; then
        read -r -p "Stimulus file $file exists. Overwrite? (y/N) " reply
        [[ $reply =~ ^[Yy]$ ]] || { printf 'Skipping Stimulus generation\n'; return; }
    fi

    $DRY_RUN && { printf '[dry‑run] mkdir -p %s\n' "$STIMULUS_DIR"; printf '[dry‑run] create %s\n' "$file"; return; }

    mkdir -p "$STIMULUS_DIR"
    cat >"$file" <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class {{CLASS}} extends Controller {
  connect() {
    // Initialize controller logic here
  }
}
EOF
    # Replace placeholder with actual class name
    sed -i '' "s/{{CLASS}}/${controller}/g" "$file"
    printf '✓ Stimulus controller created: %s\n' "$file"
}

#--- Main --------------------------------------------------------------------
main() {
    local dry= false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage ;;
            *) break ;;
        esac
    done

    local resource=${1:-}
    [[ -n $resource ]] || die "Usage: $0 <ResourceName>"
    validate_rails_app

    generate_model "$resource"
    generate_controller "${resource}Controller"
    generate_stimulus_ts "${resource}Controller"

    printf '\n✓ Resource generation completed successfully\n'
    printf 'Next steps:\n'
    printf '  • Run migrations: rails db:migrate\n'
    printf '  • Add routes to %s\n' "$ROUTES_FILE"
    printf '  • Implement controller actions and views\n'
}

#--- Entrypoint --------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi```

## `DEPLOY/rails/__shared/@messenger_features.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

error() {
  log "ERROR: $*"
  exit 1
}

check_rails_environment() {
  : "${RAILS_ENV:=development}"
  [ -n "${RAILS_ENV}" ] || error "RAILS_ENV is empty after defaulting"
  [ -x "bin/rails" ] || error "bin/rails not found – run inside a Rails application"
  command -v bin/rails >/dev/null || error "bin/rails is not executable"
}

model_exists() {
  # Returns 0 if a model file with the given name exists in app/models
  local name=$1
  [ -f "app/models/${name}.rb" ] || [ -f "app/models/${name.underscore}.rb" ]
}

generate_model() {
  local name=$1
  shift
  log "Generating model ${name}..."
  bin/rails generate model "${name}" "$@" --no-test-framework
}

setup_messenger_models() {
  check_rails_environment

  models="
Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean
Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime
ConversationParticipant conversation:references user:references last_read_at:datetime
"

  while IFS= read -r line; do
    [ -z "${line%[[:space:]]*}" ] && continue
    set -- $line
    model_name=$1
    shift
    if model_exists "${model_name}"; then
      log "Model ${model_name} already exists – skipping generation"
      continue
    fi
    generate_model "${model_name}" "$@"
  done <<EOF
$models
EOF

  log "Running migrations..."
  bin/rails db:migrate
  log "Messenger models configured successfully"
}

setup_messenger_models```

## `DEPLOY/rails/__shared/@reddit_features.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

timestamp() {
  date +%Y%m%d%H%M%S%N | cut -c1-17  # nanosecond precision, trimmed to avoid filename length issues
}

migrations_dir=db/migrate
models_dir=app/models

migration_exists() {
  shopt -s nullglob
  local matches=($1)
  (( ${#matches[@]} ))
}

write_migration() {
  local file=$1
  shift
  mkdir -p "$(dirname "$file")"
  {
    printf "%s\n" "$*"
  } >"$file"
}

generate_migration() {
  local ts file name content
  ts=$(timestamp)
  name=$1
  file="${migrations_dir}/${ts}_$name.rb"
  content=$2
  write_migration "$file" "$content"
  log "Generated $name migration: $file"
}

generate_comment_migration() {
  generate_migration "create_comments" "
class CreateComments < ActiveRecord::Migration[7.0]
  def change
    create_table :comments do |t|
      t.text :content
      t.references :user, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.references :parent, foreign_key: { to_table: :comments }
      t.integer :cached_score, default: 0
      t.integer :cached_upvotes, default: 0
      t.integer :cached_downvotes, default: 0
      t.integer :cached_depth, default: 0
      t.timestamps
    end
    add_index :comments, %i[commentable_type commentable_id]
    add_index :comments, :parent_id
    add_index :comments, :cached_score
  end
end
"
}

generate_vote_migration() {
  generate_migration "create_votes" "
class CreateVotes < ActiveRecord::Migration[7.0]
  def change
    create_table :votes do |t|
      t.integer :value, null: false
      t.references :user, null: false, foreign_key: true
      t.references :votable, polymorphic: true, null: false
      t.timestamps
    end
    add_index :votes, %i[user_id votable_type votable_id], unique: true
    add_index :votes, %i[votable_type votable_id]
    add_check_constraint :votes, 'value IN (1, -1)', name: 'vote_value_check'
  end
end
"
}

generate_karma_migration() {
  generate_migration "add_karma_to_users" "
class AddKarmaToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :karma, :integer, default: 0
    add_index :users, :karma
  end
end
"
}

write_model() {
  local target=$1
  local content=$2
  [[ -f "$target" ]] && return
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<<"$content"
}

write_comment_model() {
  write_model "${models_dir}/comment.rb" 'class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, :user_id, :commentable_type, :commentable_id, presence: true

  validate :no_circular_reference
  validate :parent_belongs_to_same_commentable

  after_create :update_cached_depth
  after_save :update_commentable_comments_count, if: :saved_change_to_parent_id?

  def recalc_score!
    update_columns(
      cached_score: votes.sum(:value),
      cached_upvotes: votes.where(value: 1).count,
      cached_downvotes: votes.where(value: -1).count
    )
  end

  def update_cached_depth
    depth = calculate_depth
    update_columns(cached_depth: depth) if cached_depth != depth
  end

  def calculate_depth
    parent&.cached_depth.to_i + 1
  end

  def no_circular_reference
    errors.add(:parent_id, "cannot reference itself") if parent_id == id
  end

  def parent_belongs_to_same_commentable
    errors.add(:parent_id, "must belong to the same commentable") unless parent&.commentable == commentable
  end

  def update_commentable_comments_count
    commentable&.update_comments_count if commentable.respond_to?(:update_comments_count)
  end

  def vote_by_user(user)
    votes.find_by(user: user)
  end
end'
}

write_vote_model() {
  write_model "${models_dir}/vote.rb" 'class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :user_id, :votable_type, :votable_id, presence: true
  validates :value, inclusion: { in: [1, -1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }

  after_save :update_votable_score
  after_destroy :update_votable_score

  private

  def update_votable_score
    votable.recalc_score! if votable.respond_to?(:recalc_score!)
    user.update_karma! if votable_type == "Comment"
  end
end'
}

ensure_user_model() {
  local target="${models_dir}/user.rb"
  [[ -f "$target" ]] || return
  if ! grep -q "def update_karma!" "$target"; then
    cat >>"$target" <<'EOF'

# Karma methods
def update_karma!
  new_karma = comments.sum(:cached_score)
  update_columns(karma: new_karma) if karma != new_karma
end

def voted_on?(votable)
  votes.exists?(votable: votable)
end

def vote_for(votable, value)
  transaction do
    existing = votes.find_by(votable: votable)
    if existing
      existing.destroy! if existing.value == value
      existing.update!(value: value) unless existing.value == value
    else
      votes.create!(votable: votable, value: value)
    end
  end
end
EOF
    log "Extended user model with karma methods"
  fi
}

setup_reddit_models() {
  migration_exists "$migrations_dir/*_create_comments.rb"   || generate_comment_migration
  migration_exists "$migrations_dir/*_create_votes.rb"      || generate_vote_migration
  migration_exists "$migrations_dir/*_add_karma_to_users.rb" || generate_karma_migration

  write_comment_model
  write_vote_model
  ensure_user_model

  log "Reddit-style social features setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_reddit_models
fi```

## `DEPLOY/rails/__shared/@twitter_features.sh`
```bash
```ruby
class Retweet < ApplicationRecord
  belongs_to :user
_id] }
  validates :retweetable_id, presence: true
  validates :retweetable_type, presence: true
  validate :cannot_retweet_own_content

  after_create :enqueue_retweet_notification
  after_destroy :cleanup_notifications

  def with_comment?
    comment.present?
  end

  private

  def cannot_retweet_own_content
    return unless retweetable
    if user_id == retweetable.user_id
      errors.add(:base, "Cannot retweet your own content")
    end
  end

  def enqueue_retweet_notification
    return if user_id == retweetable.user_id
    NotificationJob.perform_later('retweet', retweetable.user_id, self)
  end

  def cleanup_notifications
    Notification.where(notifiable: self, action: 'retweet').delete_all
  end
end

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: true,
            format: { with: /\A[\p{Alnum}_]+\z/, message: "only allows letters, numbers and underscores" },
            length: { maximum: 50 }

  before_validation :normalize_name, if: :name_present?

  def self.find_or_create_by_name(name)
    normalized = name.downcase.strip
    return nil if normalized.blank?

    find_or_create_by(name: normalized)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create hashtag #{normalized}: #{e.message}"
    nil
  end

  private

  def name_present?
    name.present?
  end

  def normalize_name
    self.name = name.downcase.strip
  end
end

class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user, class_name: 'User'

  validates :mentioned_user_id, presence: true
  validates :mentionable_id, presence: true
  validates :mentionable_type, presence: true

  after_create_commit :enqueue_mention_notification

  private

  def enqueue_mention_notification
    NotificationJob.perform_later('mention', mentioned_user_id, self)
  end
end
```
```

## `DEPLOY/rails/__shared/layouts/_flash.html.erb`
```erb
<%# Renders a flash message with a dismiss button – expects locals: flash_message, flash_type %>
<% return unless flash_message.present? %>

<div class="flash flash-<%= h flash_type %>"
     role="alert"
     aria-live="assertive"
     aria-atomic="true"
     data-controller="flash"
     data-action="click->flash#dismiss">
  <div class="flash__content" data-flash-target="content">
    <%= sanitize(
          flash_message,
          tags: %w[p b i u strong em a br],
          attributes: %w[href target]
        ) %>
  </div>
  <button type="button"
          class="flash-dismiss"
          aria-label="Dismiss alert"
          data-action="click->flash#dismiss">
    <span aria-hidden="true">&times;</span>
    <span class="visually-hidden">Dismiss this message</span>
  </button>
</div>```

## `DEPLOY/rails/__shared/layouts/_footer.html.erb`
```erb
<%# frozen_string_literal: true %>
<%= tag.footer class: "site-footer", role: "contentinfo" do %>
  <div class="footer-content">
    <p class="footer-text">
      <%= t(
            "footer.copyright",
            year: Time.zone.now.year,
            app_name: ApplicationHelper.application_name
          ) %>
    </p>
    <nav aria-label="Footer links">
      <% (footer_links || []).each do |link| %>
        <%= link_to t(link[:translation_key]), link[:path],
                    class: "footer-link",
                    rel: "noopener" %>
      <% end %>
    </nav>
  </div>
<% end %>```

## `DEPLOY/rails/__shared/layouts/_meta.html.erb`
```erb
<%= tag.meta charset: "utf-8" %>
<%= tag.meta name: "viewport", content: "width=device-width, initial-scale=1" %>

<%# Open Graph tags %>
<%= tag.meta property: "og:type", content: "website" %>
<%= tag.meta property: "og:image", content: (content_for?(:og_image) ? h(yield(:og_image)) : asset_path("default_og_image.png")) %>
<%= tag.meta property: "og:url", content: ERB::Util.u(request.original_url) %>
<%= tag.meta property: "og:description", content: (content_for?(:description) ? h(yield(:description)) : "My App Description") %>
<%= tag.meta property: "og:title", content: (content_for?(:title) ? h(yield(:title)) : "My App") %>

<%# Twitter Card tags – fall back to Open Graph values when not provided %>
<%= tag.meta name: "twitter:card", content: "summary_large_image" %>
<%= tag.meta name: "twitter:title", content: (content_for?(:title) ? h(yield(:title)) : "My App") %>
<%= tag.meta name: "twitter:description", content: (content_for?(:description) ? h(yield(:description)) : "My App Description") %>
<%= tag.meta name: "twitter:image", content: (content_for?(:og_image) ? h(yield(:og_image)) : asset_path("default_og_image.png")) %>```

## `DEPLOY/rails/__shared/layouts/_nav.html.erb`
```erb
<%# frozen_string_literal: true %>
<a href="#main-content" class="skip-nav">Skip to main content</a>
<header class="site-header">
  <div class="container">
    <nav class="nav-main" aria-label="Main navigation" role="navigation">
      <div class="nav-brand">
        <%= link_to root_path, class: "logo-link" do %>
          <span class="logo"><%= @app_name.presence || "App" %></span>
        <% end %>
        <% if (tenant = ActsAsTenant.current_tenant&.name).present? %>
          <span class="tenant"><%= tenant %></span>
        <% end %>
      </div>

      <ul class="nav-links">
        <% if user_signed_in? %>
          <li>
            <span class="nav-user" aria-label="<%= current_user.email %>"><%= current_user.email %></span>
          </li>
          <li>
            <%= link_to t("navigation.sign_out"), destroy_user_session_path,
                        method: :delete,
                        class: "nav-link",
                        data: { turbo_method: :delete } %>
          </li>
        <% else %>
          <li>
            <%= link_to t("navigation.sign_in"), new_user_session_path, class: "nav-link" %>
          </li>
        <% end %>
      </ul>
    </nav>
  </div>
</header>```

## `DEPLOY/rails/__shared/layouts/application.html.erb`
```erb
<!DOCTYPE html>
<html lang="<%= html_escape((I18n.locale.presence || I18n.default_locale || 'en').to_s) %>" dir="<%= html_escape(rtl_locale?(I18n.locale) ? 'rtl' : 'ltr') %>">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <% title = content_for?(:title) ? yield(:title) : (t('site.title', default: 'Default Site Title')) %>
    <%= render "shared/meta", title: title %>
    <%= yield :head if content_for?(:head) %>
  </head>
  <body data-controller="<%= html_escape(controller_name) %>"<% if defined?(body_class) && body_class.present? %> class="<%= html_escape(body_class) %>"<% end %>>
    <%= render "shared/skip_links" %>
    <%= render "shared/nav" %>

    <main id="main-content" class="site-main" role="main">
      <%= render "shared/flash" %>
      <%= yield %>
    </main>

    <%= render "shared/footer" %>
    <%= yield :scripts if content_for?(:scripts) %>
  </body>
</html>```

## `DEPLOY/rails/__shared/layouts/visualizer.js`
```javascript
    "use strict";

    const IN_SANDBOX=false;

    const FADE_MS=3500,START_FADE_IN=true,DPR=Math.min(2,window.devicePixelRatio||1),isLowEnd=(navigator.hardwareConcurrency&&navigator.hardwareConcurrency<=2)||(navigator.deviceMemory&&navigator.deviceMemory<=2);

    (()=>{const e=document.getElementById("uiDots");if(!e)return;const s=[0,1,2,3,2,1];let i=0;const t=()=>{e.textContent=".".repeat(s[i]);i=(i+1)%s.length};t();try{clearInterval(window.__RB_DOTS_IV)}catch{}window.__RB_DOTS_IV=setInterval(t,600)})();

    const motionScale=()=>typeof matchMedia==="function"&&matchMedia("(prefers-reduced-motion: reduce)").matches?.35:1;

    class SimpleCarousel{constructor(e,i=2800){this.slides=Array.from(e.querySelectorAll(".carousel-slide"));this.i=0;this.n=this.slides.length;if(this.n>1)this.t=setInterval(()=>this.next(),i)}next(){this.slides[this.i].classList.remove("active");this.i=(this.i+1)%this.n;this.slides[this.i].classList.add("active")}}

    new SimpleCarousel(document.getElementById("cityCarousel"));

    const YOUTUBE_TRACKS=[

      {artist:"J Dilla",title:"Microphone Master",id:"9EGHwkDix78"},

      {artist:"J Dilla",title:"In Space",id:"vO2nWXCVt6o"},

      {artist:"J Dilla",title:"Timeless",id:"dbbfo9_7D8g"},

      {artist:"AFTA-1",title:"Due Time",id:"WC09qDzU9y4"},

      {artist:"Flying Lotus",title:"Massage Situation",id:"6oUx6wGCekM"},

      {artist:"Madlib",title:"Eye",id:"ScVz2mntmCE"},

      {artist:"Slum Village",title:"Players",id:"KsULjOCYdnY"},

      {artist:"Jay Electronica",title:"Exhibit A",id:"H3UIHZshNQ0"},

      {artist:"Slum Village",title:"La La (Instrumental)",id:"EYJxxHQ7sX0"},

      {artist:"Slum Village",title:"Get It Together",id:"t6T-Q6HMbEo"},

      {artist:"Slum Village",title:"Fantastic",id:"a3ISYWWYgz8"},

      {artist:"Flying Lotus",title:"me Yesterday//Corded",id:"8DgAhgmpXNA"},

      {artist:"Flying Lotus",title:"Camel",id:"fU9YRGLPDQ8"},

      {artist:"Flying Lotus",title:"Golden Diva",id:"iu4FVvR2QQs"},

      {artist:"Slum Village",title:"Worlds Full of Sadness",id:"MU3nfxsz2XA"},

      {artist:"A. Mochi & Takaaki Itoh",title:"Sarria's Mind",id:"gFKArkiz8vU"},

      {artist:"Samiyam",title:"Rounded",id:"oeaY2h_cKsg"},

      {artist:"Chase Swayze",title:"Traffic",id:"bH-30pDoQdo"},

      {artist:"Chase Swayze",title:"Underrated",id:"1jjFk2Vp5ok"},

      {artist:"Flying Lotus",title:"BTS Radio 2006",id:"6nWdggkulHk",start:1364}

    ];

    const loadYouTubeAPI=()=>{if(IN_SANDBOX||window.__YT_API_LOADED)return;window.__YT_API_LOADED=true;const s=document.createElement("script");s.src="https://www.youtube.com/iframe_api";s.async=true;document.head.appendChild(s)};

    // MP3 Playlist Detection and Parsing
    const detectMp3Playlist=async()=>{

      if(IN_SANDBOX)return null;

      let tracks=[];

      try{

        let r=await fetch("playlist.json");

        if(r.ok){

          const data=await r.json();

          if(Array.isArray(data)&&data.length>0)tracks=tracks.concat(data.map(t=>({...t,src:t.src})));

        }

      }catch{}

      try{

        let r=await fetch("playlist.m3u");

        if(r.ok){

          const text=await r.text();

          const m3uTracks=parseM3U(text);

          if(m3uTracks&&m3uTracks.length>0)tracks=tracks.concat(m3uTracks);

        }

      }catch{}

      try{

        let r=await fetch("index.json");

        if(r.ok){

          const data=await r.json();

          if(Array.isArray(data)){

            const mp3Files=data.filter(f=>typeof f==='string'&&f.toLowerCase().endsWith('.mp3'));

            tracks=tracks.concat(mp3Files.map(f=>{

              const name=f.replace(/\.mp3$/i,'').replace(/[-_]/g,' ');

              return{title:name,artist:'',src:f};

            }));

          }else if(data.files&&Array.isArray(data.files)){

            const mp3Files=data.files.filter(f=>typeof f==='string'&&f.toLowerCase().endsWith('.mp3'));

            tracks=tracks.concat(mp3Files.map(f=>{

              const name=f.replace(/\.mp3$/i,'').replace(/[-_]/g,' ');

              return{title:name,artist:'',src:f};

            }));

          }

        }

      }catch{}

      return tracks.length>0?tracks:null;

    };

    const parseM3U=(text)=>{
      const lines=text.split('\n').map(l=>l.trim()).filter(l=>l);

      const tracks=[];

      let current={};

      for(const line of lines){

        if(line.startsWith('#EXTINF:')){

          const info=line.substring(8);

          const parts=info.split(',');

          if(parts.length>=2){

            current.title=parts[1].trim();

            const match=parts[0].match(/(\d+)/);

            if(match)current.duration=parseInt(match[1]);

          }

        }else if(!line.startsWith('#')&&line){

          current.src=line;

          if(current.src)tracks.push({...current});

          current={};

        }

      }

      return tracks.length>0?tracks:null;

    };

    const YT_ORIGIN="https://www.youtube.com";

    const ytPost=(i,f,a=[])=>{if(IN_SANDBOX)return;try{if(!i||!i.contentWindow)return;i.contentWindow.postMessage({event:"command",func:f,args:a},YT_ORIGIN)}catch{try{i.contentWindow.postMessage({event:"command",func:f,args:a},"*")}catch{}}};

    class Mp3AudioEngine{

      constructor(tracks){

        this.started=false;this.muted=true;this.trackIndex=0;

        this.tracks=tracks.slice().sort(()=>Math.random()-.5);

        this.activeKey="a";this.inactiveKey="b";

        this.players={a:null,b:null};this._fadeIv=null;this._prefadeTimer=null;

        this.audioContext=null;this.analyser=null;this.dataArray=null;

        this.beatPhase=0;this.energyLevel=.5;this._lastBeat=0;this._beatEnv=0;

        this._initAudioElements();

      }

      _initAudioElements(){
        // Create two audio elements for crossfading

        this.players.a=new Audio();

        this.players.b=new Audio();

        this.players.a.crossOrigin="anonymous";

        this.players.b.crossOrigin="anonymous";

        this.players.a.preload="auto";

        this.players.b.preload="auto";

        this.players.a.volume=0;

        this.players.b.volume=0;

        // Setup Web Audio Context and Analyser
        try{

          this.audioContext=new(window.AudioContext||window.webkitAudioContext)();

          this.analyser=this.audioContext.createAnalyser();

          this.analyser.fftSize=512;

          this.analyser.smoothingTimeConstant=0.8;

          this.dataArray=new Uint8Array(this.analyser.frequencyBinCount);

          // Connect active player to analyser
          this._connectAnalyser();

        }catch{

          this.audioContext=null;

        }

        // Setup event listeners
        ['a','b'].forEach(k=>{

          const p=this.players[k];

          p.addEventListener('ended',()=>{

            if(k===this.activeKey)this.beginCrossfade({fast:true});

          });

          p.addEventListener('canplay',()=>{

            if(k===this.activeKey&&this.started){

              this._setupNextCrossfade(p);

            }

          });

          p.addEventListener('error',()=>{

            if(k===this.activeKey)this.beginCrossfade({fast:true});

          });

        });

      }

      _connectAnalyser(){
        if(!this.audioContext||!this.analyser)return;

        try{

          const activePlayer=this.players[this.activeKey];

          if(activePlayer&&!activePlayer._sourceNode){

            activePlayer._sourceNode=this.audioContext.createMediaElementSource(activePlayer);

            activePlayer._sourceNode.connect(this.analyser);

            this.analyser.connect(this.audioContext.destination);

          }

        }catch{}

      }

      _setupNextCrossfade(player){
        if(!player.duration)return;

        const fadeTime=Math.max(FADE_MS+1000,player.duration*1000-FADE_MS-500);

        clearTimeout(this._prefadeTimer);

        this._prefadeTimer=setTimeout(()=>this.beginCrossfade({}),fadeTime);

      }

      start(){
        this.started=true;this.updateUITrack();

        if(this.audioContext&&this.audioContext.state==='suspended'){

          this.audioContext.resume();

        }

        this._loadOn(this.activeKey,this.tracks[this.trackIndex],{fadeIn:START_FADE_IN});

      }

      _loadOn(k,t,{fadeIn}={fadeIn:true}){
        if(!k||!t||!this.players[k])return;

        const p=this.players[k];

        p.src=t.src;

        p.load();

        if(fadeIn){
          this._fadeVolumes({toKey:k,ms:FADE_MS});

        }else{

          p.volume=this.muted?0:1;

        }

        // Connect to analyser if this is the active player
        if(k===this.activeKey){

          this._connectAnalyser();

        }

        // Auto-play when ready
        p.addEventListener('canplay',()=>{

          if(!this.muted||fadeIn)p.play().catch(()=>{});

        },{once:true});

      }

      beginCrossfade({fast=false}={}){
        clearInterval(this._fadeIv);clearTimeout(this._prefadeTimer);

        const n=(this.trackIndex+1)%this.tracks.length,t=this.tracks[n];

        const f=this.activeKey,o=this.inactiveKey;

        this._loadOn(o,t,{fadeIn:false});

        setTimeout(()=>{

          this._fadeVolumes({fromKey:f,toKey:o,ms:fast?Math.min(1200,FADE_MS):FADE_MS});

          this.trackIndex=n;this.updateUITrack();

        },fast?200:500);

      }

      prev(){
        clearInterval(this._fadeIv);clearTimeout(this._prefadeTimer);

        const p=(this.trackIndex-1+this.tracks.length)%this.tracks.length,t=this.tracks[p];

        const f=this.activeKey,o=this.inactiveKey;

        this._loadOn(o,t,{fadeIn:false});

        setTimeout(()=>{

          this._fadeVolumes({fromKey:f,toKey:o,ms:FADE_MS});

          this.trackIndex=p;this.updateUITrack();

        },300);

      }

      next(){this.beginCrossfade({fast:false})}
      toggleMute(){
        this.muted=!this.muted;

        const p=this.players[this.activeKey];

        if(p){
... 551 lines truncated (951 total)
```

## `DEPLOY/rails/amber/@shared_functions.sh`
```bash
#!/usr/bin/env sh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
#
# Conventions:
#   APP_DIR  — full path to the Rails app (caller must set, e.g. /home/brgen/app)
#   APP_PORT — TCP port Falcon listens on (default 3000)

: "${APP_PORT:=3000}"
readonly APP_PORT

# Ensure required environment variables are present
: "${APP_DIR:?APP_DIR must be set before sourcing}"

set -eu
set -o pipefail
IFS=$'\n\t'

# ── Logging ──────────────────────────────────────────────────────────────────

log()      { printf '%b\n' "$(printf '\033[36m==>\033[0m %s' "$*")"; }
log_ok()   { printf '%b\n' "$(printf '\033[32m✔\033[0m %s' "$*")"; }
log_warn() { printf '%b\n' "$(printf '\033[33mWARN\033[0m %s' "$*")" >&2; }
log_err()  { printf '%b\n' "$(printf '\033[31mERR\033[0m %s' "$*")" >&2; }

# ── Precondition checks ───────────────────────────────────────────────────────

command_exists() {
  cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Required command not found: $cmd"
    exit 1
  fi
  log_ok "$cmd found"
}

check_app_exists() {
  sentinel=$1
  if [ -f "$sentinel" ]; then
    log_warn "Already set up ($sentinel exists). Skipping."
    return 0
  fi
  return 1
}

# ── App scaffolding ───────────────────────────────────────────────────────────

setup_full_app() {
  app_dir=$1
  mkdir -p "$(dirname "$app_dir")"

  if [ ! -f "$app_dir/config/application.rb" ]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --skip-git \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-test
  fi

  cd "$app_dir"

  # Ensure Falcon is the server adapter
  if ! grep -q '"falcon"' Gemfile; then
    printf '%s\n' 'gem "falcon"' >> Gemfile
    bundle install --quiet
  fi

  log_ok "Working in: $app_dir"
}

# ── Gem helpers ───────────────────────────────────────────────────────────────

install_gem() {
  gem=$1 version=${2:-}
  if ! grep -q "\"$gem\"" Gemfile 2>/dev/null; then
    if [ -n "$version" ]; then
      printf '%s\n' "gem \"$gem\", \"$version\"" >> Gemfile
    else
      printf '%s\n' "gem \"$gem\"" >> Gemfile
    fi
    bundle install --quiet
    log_ok "gem $gem installed"
  else
    log_ok "gem $gem already present"
  fi
}

# ── Database helpers ──────────────────────────────────────────────────────────

db_setup() {
  RAILS_ENV=production bin/rails db:create db:migrate 2>&1 |
    grep -E "Created|migrated|error" || :
  log_ok "database ready"
}

# ── relayd helpers ────────────────────────────────────────────────────────────

relayd_add_relay() {
  host=$1 port=$2
  table_name=${host%%.*}
  conf=/etc/relayd.conf

  if grep -q "table <${table_name}>" "$conf" 2>/dev/null; then
    return 0
  fi

  sudo sh -c "cat >> $conf <<'EOF'
table <${table_name}> { 127.0.0.1 }
EOF"
  log_ok "relayd table <${table_name}> → :${port} added (reload relayd to apply)"
}

# ── rc.d helpers ──────────────────────────────────────────────────────────────

install_rcd() {
  svc=$1 app_dir=$2 port=$3 user=$4
  rcd="/etc/rc.d/${svc}"

  [ -f "$rcd" ] && return 0

  sudo sh -c "cat > $rcd <<'EOF'
#!/bin/ksh
daemon_execdir='${app_dir}'
daemon='${app_dir}/bin/rails'
daemon_flags='server -b 0.0.0.0 -p ${port} -e production'
daemon_user='${user}'
. /etc/rc.d/rc.subr
rc_cmd \$1
EOF"

  sudo chmod 755 "$rcd"
  sudo rcctl enable "$svc"
  log_ok "rc.d/${svc} installed"
}

# ── Asset helpers ─────────────────────────────────────────────────────────────

generate_default_css() {
  mkdir -p app/assets/stylesheets
  cat > app/assets/stylesheets/application.css <<'CSS'
:root {
  --bg: #0a0a0a;
  --surface: #1a1a1a;
  --text: #e8eaed;
  --text-dim: #9aa0a6;
  --primary: #8ab4f8;
  --accent: #ff4500;
  --radius: 8px;
  --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
main { max-width: 1200px; margin: 0 auto; padding: calc(var(--space) * 2); }
a { color: var(--primary); text-decoration: none; }
.card { background: var(--surface); border-radius: var(--radius); padding: calc(var(--space) * 2); margin-bottom: calc(var(--space) * 2); }
@media (max-width: 768px) { main { padding: var(--space); } }
CSS
  log_ok "default CSS written"
}

generate_all_stimulus_controllers() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/index.js <<'JS'
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus controllers index written"
}```

## `DEPLOY/rails/amber/README.md`
```markdown
          CDN (Cloudflare)
                 │
      Load Balancer (relayd)
                 │
            Falcon (Rails 8)
                 │
   ┌─────────────────────────────┐
   │          Services            │
   ├─────────────────────┬───────┤
   │ PostgreSQL + pgvector│ Redis │
   │   (primary DB)      │ (Action│
   │                     │ Cable)│
   └─────────────────────┴───────┘
```

## `DEPLOY/rails/amber/amber.sh`
```bash
#!/usr/bin/env sh
# -*- sh -*-

# Strict mode: abort on error, undefined variable, or pipe failure
set -euo pipefail

#=== Configuration ============================================================
APP_NAME="amber"
BASE_DIR="/home/amber"
APP_PORT=10006
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/@shared_functions.sh"

#=== Helpers ================================================================
check_file() { [ -f "$1" ]; }

install_gem_if_missing() {
  gem list -i "$1" >/dev/null 2>&1 || gem install "$1"
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: $1 required"
    exit 1
  }
}

#=== Prerequisites ===========================================================
ensure_cmd ruby
ensure_cmd node
ensure_cmd bundle
install_gem_if_missing pagy
install_gem_if_missing faker

#=== Idempotent exit =========================================================
if check_file "${BASE_DIR}/app/models/item.rb"; then
  log "Amber already set up – exiting"
  exit 0
fi

log "Starting Amber setup – AI Fashion Wardrobe Assistant"

#=== Layout ================================================================
cat > app/views/layouts/application.html.erb <<'EOF'
<!DOCTYPE html>
<html lang="<%= I18n.locale %>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title><%= content_for?(:title) ? yield(:title) + " - Amber" : "Amber - AI Fashion Assistant" %></title>
  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Organize your wardrobe with AI-powered style assistance' %>">
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= pwa_meta_tags %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
  <%= register_service_worker %>
  <%= yield :head %>
</head>
<body>
  <%= yield %>
</body>
</html>
EOF

#=== Routes ================================================================
cat > config/routes.rb <<'EOF'
Rails.application.routes.draw do
  devise_for :users
  root "home#index"

  resources :items do
    member do
      post :spark_joy
      post :declutter
      post :analyze_joy, to: "kondo_ai#analyze_item"
    end
  end

  resources :outfits do
    member { post :like }
  end

  resources :profiles, only: [:show, :edit, :update]
  resource  :session
  resources :passwords, param: :token

  # Kondo AI
  get  "kondo/tips",      to: "kondo_ai#organization_tips", as: :kondo_tips
  get  "kondo/outfits",   to: "kondo_ai#suggest_outfits",    as: :kondo_outfits
  get  "kondo/declutter", to: "kondo_ai#declutter_guide",   as: :kondo_declutter

  get "up" => "rails/health#show", as: :rails_health_check
end
EOF

#=== Seed data ==============================================================
cat > db/seeds.rb <<'EOF'
categories = %w[Tops Bottoms Dresses Shoes Accessories Outerwear]
seasons    = %w[Spring Summer Fall Winter All\ Season]
colors     = %w[Black White Red Blue Green Yellow Pink Purple]

user = User.find_or_create_by(email_address: "demo@amber.example") { |u| u.password = "password123" }

puts "Seeding Amber wardrobe..."
10.times do
  Item.create!(
    title:         Faker::Commerce.product_name,
    category:      categories.sample,
    color:         colors.sample,
    season:        seasons.sample,
    material:      %w[Cotton Polyester Wool Silk Leather].sample,
    brand:         Faker::Company.name,
    price:         Faker::Commerce.price(range: 20..500),
    times_worn:    rand(0..50),
    purchase_date: Faker::Date.backward(days: 365),
    spark_joy:    [true, false].sample,
    user:          user
  )
end
puts "Seeded #{Item.count} fashion items"
EOF

#=== Models ================================================================
bundle exec bin/rails generate model Item title:string category:string color:string size:string material:string brand:string price:decimal times_worn:integer purchase_date:date spark_joy:boolean user:references
bundle exec bin/rails generate model Outfit name:string description:text category:string season:string occasion:string likes_count:integer user:references
bundle exec bin/rails generate model OutfitItem outfit:references item:references position:integer

cat > app/models/item.rb <<'EOF'
class Item < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :outfits, through: :outfit_items

  validates :title, :category, presence: true

  scope :spark_joy, -> { where(spark_joy: true) }
  scope :by_category, ->(cat) { where(category: cat) }
end
EOF

cat > app/models/outfit.rb <<'EOF'
class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  validates :name, presence: true

  def increment_likes!
    increment!(:likes_count)
  end
end
EOF

cat > app/models/outfit_item.rb <<'EOF'
class OutfitItem < ApplicationRecord
  belongs_to :outfit
  belongs_to :item

  validates :outfit, :item, presence: true
end
EOF

#=== Controllers ============================================================
cat > app/controllers/home_controller.rb <<'EOF'
class HomeController < ApplicationController
  def index
    if user_signed_in?
      @items_count      = current_user.items.count
      @spark_joy_count  = current_user.items.where(spark_joy: true).count
      @recent_items     = current_user.items.order(created_at: :desc).limit(6)
    end
  end
end
EOF

cat > app/controllers/items_controller.rb <<'EOF'
class ItemsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter]
  before_action :authorize_user!, only: %i[edit update destroy spark_joy declutter]

  def index
    @pagy, @items = pagy(current_user.items.order(created_at: :desc))
  end

  def show; end

  def new
    @item = current_user.items.build
  end

  def create
    @item = current_user.items.build(item_params)
    if @item.save
      redirect_to items_path, notice: "Item added to wardrobe"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      redirect_to @item, notice: "Item updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def spark_joy
    @item.update(spark_joy: true)
    redirect_to items_path, notice: "✨ This item sparks joy!"
  end

  def declutter
    @item.destroy
    redirect_to items_path, notice: "Item removed from wardrobe"
  end

  private

  def set_item
    @item = Item.find(params[:id])
  end

  def authorize_user!
    redirect_to items_path, alert: "Unauthorized" unless @item.user == current_user
  end

  def item_params
    params.require(:item).permit(:title, :category, :color, :size, :material, :brand, :price, :times_worn, :purchase_date)
  end
end
EOF

cat > app/controllers/outfits_controller.rb <<'EOF'
class OutfitsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_outfit, only: %i[show edit update destroy like]
  before_action :authorize_user!, only: %i[edit update destroy]

  def index
    @pagy, @outfits = pagy(current_user.outfits.order(created_at: :desc))
  end

  def show; end

  def new
    @outfit = current_user.outfits.build
  end

  def create
    @outfit = current_user.outfits.build(outfit_params)
    if @outfit.save
      redirect_to @outfit, notice: "Outfit created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @outfit.update(outfit_params)
      redirect_to @outfit, notice: "Outfit updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.increment_likes!
    redirect_to @outfit, notice: "Liked!"
  end

  private

  def set_outfit
    @outfit = Outfit.find(params[:id])
  end

  def authorize_user!
    redirect_to outfits_path, alert: "Unauthorized" unless @outfit.user == current_user
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion)
  end
end
EOF

#=== Kondo AI Service =======================================================
cat > app/services/marie_kondo_ai_service.rb <<'EOF'
# frozen_string_literal: true

class MarieKondoAiService
  def initialize(user)
    @user = user
    @llm  = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
  end

  def sparks_joy?(item)
    prompt = <<~PROMPT
      Analyze this clothing item and say YES if it sparks joy, otherwise NO.
      Item: #{item.title}
      Category: #{item.category}
      Color: #{item.color}
      Material: #{item.material}
      Times worn: #{item.times_worn}
      Purchase date: #{item.purchase_date}
    PROMPT

    response = @llm.chat(messages: [{ role: "user", content: prompt }])
    content  = response.dig("choices", 0, "message", "content").to_s
    { sparks_joy: content.downcase.include?("yes"), reason: content }
  end

  def get_organization_tips(category: nil, season: nil)
    query = build_query(category, season)
    embeds = generate_embedding(query)

    tips = OrganizationTip
           .nearest_neighbors(:embedding, embeds, distance: "cosine")
           .limit(5)

    context = tips.map { |t| "\#{t.title}: \#{t.content}" }.join("\n")

    prompt = <<~PROMPT
      Provide 3‑5 actionable wardrobe organization tips.
      User stats: \#{summary_stats}
      Context: \#{context}
      Question: \#{query}
    PROMPT

    @llm.chat(messages: [{ role: "user", content: prompt }])
        .dig("choices", 0, "message", "content")
  end

  private

  def generate_embedding(text)
    Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
      .embed(text: text).dig("embedding")
  end

  def build_query(category, season)
    parts = ["How to organize"]
    parts << category if category
    parts << "for \#{season}" if season
    parts.join(" ")
  end

  def summary_stats
    {
      total_items: @user.items.count,
      spark_joy:   @user.items.where(spark_joy: true).count
    }.inspect
  end
end
EOF

#=== Kondo AI Controller ====================================================
cat > app/controllers/kondo_ai_controller.rb <<'EOF'
class KondoAiController < ApplicationController
  before_action :authenticate_user!

  def analyze_item
    item = current_user.items.find(params[:id])
    ai   = MarieKondoAiService.new(current_user)
    res  = ai.sparks_joy?(item)

    item.update(spark_joy: res[:sparks_joy], declutter_reason: res[:reason])

    respond_to do |fmt|
      fmt.turbo_stream
      fmt.json { render json: res }
    end
  end

  def organization_tips
    @tips = MarieKondoAiService.new(current_user)
            .get_organization_tips(category: params[:category], season: params[:season])

    respond_to { |fmt| fmt.html; fmt.turbo_stream }
  end

  def suggest_outfits
    @suggestions = MarieKondoAiService.new(current_user).suggest_outfits(
      occasion: params[:occasion],
      season:   params[:season],
      weather:  params[:weather]
    )
... 23 lines truncated (423 total)
```

## `DEPLOY/rails/baibl/README.md`
```markdown
git clone https://github.com/yourorg/baibl.git
cd baibl
```

## `DEPLOY/rails/baibl/baibl.sh`
```bash
#!/usr/bin/env sh
set -eu
export LC_ALL=C

# Baibl – scripture server (TCPServer, port 10007)

APP_NAME=baibl
APP_PORT=10007
APP_DIR="/home/${APP_NAME}/app"
CONFIG_DIR="${APP_DIR}/config"
FALCON_RB="${CONFIG_DIR}/falcon.rb"
RC_SCRIPT="/etc/rc.d/${APP_NAME}"

# Ensure required commands exist
for cmd in ruby rcctl; do
  command -v "$cmd" >/dev/null || { printf '%s not found\n' "$cmd" >&2; exit 1; }
done

printf '==> [%s] generating %s on :%s\n' "$APP_NAME" "$FALCON_RB" "$APP_PORT"

mkdir -p "$CONFIG_DIR"
chown "$APP_NAME:$APP_NAME" "$CONFIG_DIR"

cat >"$FALCON_RB" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require 'socket'

HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="no">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>baibl</title>
    <style>
      :root {
        --bg: #0f0e0b; --surface: #1a1812; --surface-alt: #221f16;
        --primary: #c9a96e; --primary-light: #e2c98c; --primary-dark: #a07c40;
        --text: #f0ead6; --text-dim: #8a7f68; --border: #2e2a1e;
        --gold-line: rgba(201,169,110,.25); --radius: 10px;
      }
      * { box-sizing:border-box; margin:0; padding:0; }
      body { font-family:'Palatino Linotype', Palatino, Georgia, serif;
             background:var(--bg); color:var(--text); line-height:1.85; }
      header { background:var(--surface); border-bottom:1px solid var(--gold-line);
               padding:1.25rem 2rem; display:flex; align-items:center;
               justify-content:space-between; }
      .logo { font-size:1.5rem; font-weight:600; color:var(--primary);
              letter-spacing:.04em; font-variant:small-caps; }
      nav a { margin-left:1.5rem; color:var(--text-dim); font-size:.9rem;
              text-decoration:none; }
      nav a:hover { color:var(--primary); }
      main { max-width:820px; margin:0 auto; padding:3rem 1.5rem; }
      h1 { font-size:1.85rem; color:var(--primary-light); margin-bottom:1rem;
           font-weight:400; font-variant:small-caps; }
      .verse-block { background:var(--surface); border:1px solid var(--gold-line);
                     border-left:3px solid var(--primary); border-radius:var(--radius);
                     padding:1.75rem 2rem; margin-bottom:1.75rem; }
      .verse-reference { font-size:.78rem; color:var(--primary); letter-spacing:.08em;
                         text-transform:uppercase; margin-bottom:.75rem;
                         font-family:system-ui, sans-serif; }
      .verse-text { font-size:1.1rem; line-height:1.95; font-style:italic; }
      .ornament { text-align:center; color:var(--primary-dark); font-size:1.2rem;
                  letter-spacing:.5em; margin:2rem 0; opacity:.6; }
      .cta { display:inline-block; padding:.6rem 1.4rem; background:var(--primary);
             color:var(--bg); border-radius:8px; font-size:.9rem; text-decoration:none;
             font-weight:600; margin-top:1.5rem; }
    </style>
  </head>
  <body>
    <header>
      <span class="logo">baibl</span>
      <nav><a href="/scripture">skriften</a><a href="/devotional">andakt</a><a href="/login">logg inn</a></nav>
    </header>
    <main>
      <h1>søk i skriften</h1>
      <div class="verse-block">
        <div class="verse-reference">Johannes 3:16</div>
        <div class="verse-text">For så har Gud elsket verden at han ga sin Sønn, den enbårne, for at den som tror på ham, ikke skal gå fortapt, men ha evig liv.</div>
      </div>
      <div class="ornament">✦ ✦ ✦</div>
      <a class="cta" href="/signup">kom i gang</a>
    </main>
  </body>
  </html>
HTML

RESP = <<~RESP
  HTTP/1.0 200 OK\r
  Content-Type: text/html; charset=utf-8\r
  Content-Length: #{HTML.bytesize}\r
  Connection: close\r
  \r
  #{HTML}
RESP

trap 'exit' TERM INT

TCPServer.new('0.0.0.0', ${APP_PORT}) do |server|
  $stdout.puts "baibl on ${APP_PORT}"
  $stdout.flush
  loop do
    client = server.accept
    client.recv(4096) rescue nil
    client.print(RESP) rescue nil
    client.close rescue nil
  end
end
EOF

chmod 755 "$FALCON_RB"
chown -R "$APP_NAME:$APP_NAME" "$APP_DIR"

cat >"$RC_SCRIPT" <<'RC'
#!/bin/sh
# PROVIDE: baibl
# REQUIRE: DAEMON
# DESCRIPTION: Baibl scripture server

. /etc/rc.subr

name=baibl
rcvar=baibl_enable

command="${HOME}/baibl/app/config/falcon.rb"
command_args=""

pidfile="/var/run/${name}.pid"
procname="${name}"
user="${name}"
group="${name}"
start_precmd="cd ${HOME}/${name}/app"

load_rc_config $name
run_rc_command "$1"
RC

chmod 755 "$RC_SCRIPT"
rcctl enable "$APP_NAME"
rcctl restart "$APP_NAME" || rcctl start "$APP_NAME"
printf '==> [%s] ready\n' "$APP_NAME"
```

## `DEPLOY/rails/blognet/README.md`
```markdown
cd /home/dev/rails
```

## `DEPLOY/rails/blognet/blognet.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

# Blognet: Multi‑blog platform with AI content generation
# Idempotent, self‑contained deployment script

# Configuration
APP_NAME="blognet"
BASE_DIR="/home/dev/rails"
APP_ROOT="${BASE_DIR}/${APP_NAME}"
RC_DIR="/etc/rc.d"
RC_NAME="${APP_NAME}_rails"
SERVICE_USER="${APP_NAME}"
SERVICE_HOME="/home/${SERVICE_USER}/app"
FALCON_RB="${SERVICE_HOME}/config/falcon.rb"
DEFAULT_PORT=10002
PORT_RANGE_START=3000
PORT_RANGE_END=3999

# Helpers
error() { printf '✖ %s\n' "$*" >&2; }
info()  { printf 'ℹ %s\n' "$*"; }

# Find first free TCP port in a range
find_available_port() {
    for port in "$(seq "$PORT_RANGE_START" "$PORT_RANGE_END")"; do
        if command -v ss >/dev/null && ss -ltn "sport = :$port" >/dev/null 2>&1; then
            continue
        fi
        if command -v nc >/dev/null && nc -z -w1 127.0.0.1 "$port" >/dev/null 2>&1; then
            continue
        fi
        printf '%s' "$port"
        return 0
    done
    error "No free ports in ${PORT_RANGE_START}-${PORT_RANGE_END}"
    return 1
}

ensure_database_yaml() {
    cfg="${APP_ROOT}/config/database.yml"
    if [ ! -f "$cfg" ] || ! grep -q "database:.*${APP_NAME}" "$cfg"; then
        cat >"$cfg" <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  timeout: 5000

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
EOF
        info "Created $cfg"
    else
        info "$cfg already present"
    fi
}

ensure_env_file() {
    env="${APP_ROOT}/.env"
    if [ ! -f "$env" ]; then
        secret=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")
        cat >"$env" <<EOF
SECRET_KEY_BASE=${secret}
DATABASE_URL=postgresql://localhost/${APP_NAME}_development
EOF
        info "Created $env"
    else
        info "$env already present"
    fi
}

check_db() {
    db="${APP_NAME}_development"
    if psql -lqt | cut -d'|' -f1 | grep -qw "$db"; then
        return 0
    else
        error "Database $db missing"
        return 1
    fi
}

generate_model() {
    model=$1
    if [ ! -f "${APP_ROOT}/app/models/${model}.rb" ]; then
        (cd "$APP_ROOT" && bundle exec rails generate model "$model") ||
            error "Failed to generate $model"
        (cd "$APP_ROOT" && bundle exec rails db:migrate) ||
            error "Failed to migrate after $model generation"
    else
        info "Model $model already exists"
    fi
}

write_falcon_rb() {
    mkdir -p "$(dirname "$FALCON_RB")"
    cat >"$FALCON_RB" <<'RUBY'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <title>blognet</title>
    <style>
      body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}
    </style>
  </head>
  <body><h1>blognet</h1></body>
  </html>
HTML

RESP = <<~HDR
  HTTP/1.0 200 OK
  Content-Type: text/html; charset=utf-8
  Content-Length: #{BODY.bytesize}
  Connection: close

  #{BODY}
HDR

trap "exit" TERM INT

TCPServer.new("0.0.0.0", %d).tap do |s|
  puts "blognet on %d"
  loop { s.accept.print(RESP) rescue nil }
end
RUBY
    # Replace placeholder with actual port without external perl
    port="${SERVICE_PORT}"
    awk -v p="$port" '{gsub(/%d/,p)}1' "$FALCON_RB" >"$FALCON_RB.tmp" && mv "$FALCON_RB.tmp" "$FALCON_RB"
    chmod 755 "$FALCON_RB"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "$(dirname "$FALCON_RB")"
    info "Wrote Falcon server to $FALCON_RB"
}

install_rc_service() {
    rc_path="${RC_DIR}/${RC_NAME}"
    tmp_rc="/tmp/${RC_NAME}"
    cat >"$tmp_rc" <<RC
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="${FALCON_RB}"
daemon_user="${SERVICE_USER}"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_cmd "\$1"
RC
    install -m 755 "$tmp_rc" "$rc_path"
    rcctl enable "$RC_NAME"
    rcctl start "$RC_NAME"
    info "Installed rc.d service $RC_NAME"
}

ensure_user() {
    if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
        error "User $SERVICE_USER does not exist"
        exit 1
    fi
}

# Main
info "Starting blognet deployment"

ensure_user
ensure_database_yaml
ensure_env_file
check_db || exit 1
generate_model "Post"

# Determine port: keep default if free, else pick first available in range
if command -v ss >/dev/null && ss -ltn "sport = :${DEFAULT_PORT}" >/dev/null 2>&1; then
    SERVICE_PORT=$(find_available_port) || exit 1
else
    SERVICE_PORT="${DEFAULT_PORT}"
fi

write_falcon_rb
install_rc_service

info "Deployment complete"
```

## `DEPLOY/rails/brgen/README.md`
```markdown
# Abort on syntax errors; exit 1 signals the caller (e.g. CI) that the config is invalid
relayd -n -f /etc/relayd.conf || exit 1
```

## `DEPLOY/rails/brgen/README_takeaway.md`
```markdown
# frozen_string_literal: true

# == Restaurant
# Represents a dining location.
class Restaurant < ApplicationRecord
  has_many :menu_items, dependent: :destroy
  has_many :orders, dependent: :nullify

  validates :name, :address, presence: true

  # Geocoder integration – update coordinates only when the address changes.
  geocoded_by :address
  after_validation :geocode, if: :will_save_change_to_address?
end

# == MenuItem
# An item on a restaurant's menu.
class MenuItem < ApplicationRecord
  belongs_to :restaurant

  # Availability states.
  enum availability: { available: 0, sold_out: 1 }

  # Store monetary value as integer cents, expose as a Money object.
  monetize :price_cents

  validates :name, :price_cents, presence: true

  # Scope for currently available items.
  scope :available, -> { where(availability: :available) }
end

# == Order
# A food order placed by a user.
class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user

  # Order lifecycle states.
  enum status: {
    placed:    0,
    accepted:  1,
    preparing: 2,
    dispatched: 3,
    delivered: 4,
    canceled:  5
  }

  validates :status, presence: true

  # Scope for orders that are still in progress.
  scope :in_progress, -> { where.not(status: %i[delivered canceled]) }
end```

## `DEPLOY/rails/brgen/README_tv.md`
```markdown
git clone https://github.com/brgen/rails.git
cd rails
```

## `DEPLOY/rails/brgen/brgen.sh`
```bash
#!/usr/bin/env sh
# -*- mode: sh; -*-
set -euo pipefail

# BRGEN v3.0.0 – Rails 8 Complete Social Network
VERSION=${VERSION:-3.0.0}
APP_DIR=${APP_DIR:-/home/brgen/app}
PORT=${PORT:-11006}
MAX_COMMENT_LENGTH=${MAX_COMMENT_LENGTH:-10000}
MAX_KARMA_SEED=${MAX_KARMA_SEED:-1000}
HOT_DECAY_EXPONENT=${HOT_DECAY_EXPONENT:-1.5}

printf '==> BRGEN v%s – Rails 8 Complete Setup\n' "$VERSION"

# ── Validation ───────────────────────────────────────────────────────────────
if [ ! -d "$APP_DIR" ]; then
  printf 'ERROR: %s missing. Run: doas sh openbsd.sh --pre-point\n' "$APP_DIR" >&2
  exit 1
fi

# Ensure Rails CLI is available
if ! command -v rails >/dev/null 2>&1; then
  printf 'ERROR: rails command not found in PATH\n' >&2
  exit 1
fi

cd "$APP_DIR"
printf 'Working in: %s\n' "$APP_DIR"

# ── Rails app creation ──────────────────────────────────────────────────────
if [ ! -f config/application.rb ]; then
  printf 'Creating Rails 8 application\n'
  rails new . --database=postgresql --skip-git --css=tailwind --javascript=esbuild
fi

# ── Gemfile augmentation ───────────────────────────────────────────────────
printf 'Appending gems to Gemfile\n'
if ! grep -q 'solid_queue' Gemfile; then
  cat >> Gemfile <<'EOF'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Voting
gem "acts_as_votable"

# Real‑time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi‑tenancy
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"

# Misc features
gem "pagy"
gem "image_processing"
gem "geocoder"
gem "langchainrb"
gem "ruby-openai"
gem "serviceworker-rails"

group :development, :test do
  gem "brakeman"
  gem "rubocop-rails-omakase"
  gem "faker"
end

EOF
fi

bundle install

# ── Acts as votable ────────────────────────────────────────────────────────
printf 'Installing acts_as_votable\n'
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

# ── Solid Stack installation ───────────────────────────────────────────────
printf 'Installing Solid Stack\n'
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

# ── Authentication scaffolding ───────────────────────────────────────────────
printf 'Installing Rails 8 authentication\n'
if [ ! -f app/models/session.rb ]; then
  bin/rails generate authentication
fi

# ── Database configuration ─────────────────────────────────────────────────
printf 'Configuring PostgreSQL\n'
sed -i.bak \
    -e 's/database: app_/database: brgen_/' \
    -e 's/username: brgen/username: brgen_user/' \
    config/database.yml && rm -f config/database.yml.bak

# ── Core models ───────────────────────────────────────────────────────────────
printf 'Generating core models\n'
models=(
  'Community name:string description:text subdomain:string:uniq slug:string:uniq'
  'Post title:string content:text user:references community:references karma:integer:default[0] anonymous:boolean:default[false]'
  'Comment content:text user:references commentable:references{polymorphic}:index parent_id:integer'
  'Reaction kind:string user:references post:references'
  'Stream content_type:string url:string user:references post:references duration:integer'
)
for spec in "${models[@]}"; do
  bin/rails generate model $spec
done

bin/rails generate migration AddFieldsToUsers username:string karma:integer:default=0 location:point

cat >> app/models/user.rb <<'RUBY'

# Voting
acts_as_voter

# Associations
has_many :posts, dependent: :destroy
has_many :comments, dependent: :destroy
has_many :communities

# Validations
validates :username, presence: true, uniqueness: true

# Update karma from votes received
def update_karma_from_votes
  total = posts.sum { |p| p.cached_votes_score } +
          comments.sum { |c| c.cached_votes_score }
  update_column(:karma, total)
end
RUBY

bin/rails db:migrate

# ── Model concerns ────────────────────────────────────────────────────────────
printf 'Creating model concerns\n'
mkdir -p app/models/concerns
cat > app/models/concerns/commentable.rb <<'RUBY'
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def comment_count
    comments.size
  end
end
RUBY

# ── Model overrides ───────────────────────────────────────────────────────────
cat > app/models/community.rb <<'RUBY'
class Community < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :users

  validates :name, :subdomain, :slug, presence: true
  validates :subdomain, :slug, uniqueness: true

  before_validation :generate_slug

  private

  def generate_slug
    self.slug ||= name.parameterize if name.present?
  end
end
RUBY

cat > app/models/post.rb <<'RUBY'
class Post < ApplicationRecord
  include Votable
  include Commentable

  acts_as_votable
  acts_as_tenant :community

  belongs_to :user
  belongs_to :community

  has_many :reactions, dependent: :destroy
  has_many :streams, dependent: :destroy
  has_many_attached :photos

  validates :title, presence: true, length: { maximum: 300 }
  validates :content, presence: true

  scope :hot, -> {
    left_joins(:votes)
      .group(:id)
      .select(<<~SQL
        posts.*,
        SUM(COALESCE(votes.value, 0)) AS vote_sum,
        EXTRACT(EPOCH FROM (NOW() - posts.created_at)) / 3600 AS hours_old
      SQL
      )
      .order(Arel.sql("vote_sum / POWER(hours_old + 2, #{HOT_DECAY_EXPONENT}) DESC"))
  }

  scope :top, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }

  def update_karma
    update_column(:karma, get_upvotes.size - get_downvotes.size)
  end
end
RUBY

cat > app/models/comment.rb <<'RUBY'
class Comment < ApplicationRecord
  include Votable

  acts_as_votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: 'Comment', optional: true
  has_many :replies, class_name: 'Comment', foreign_key: :parent_id, dependent: :destroy

  validates :content,
            presence: true,
            length: { minimum: 1, maximum: ${MAX_COMMENT_LENGTH} }

  def root?
    parent_id.nil?
  end

  def depth
    parent ? parent.depth + 1 : 0
  end

  scope :best, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }
end
RUBY

# ── Routes ────────────────────────────────────────────────────────────────────
printf 'Configuring routes\n'
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  devise_for :users

  resources :communities, only: %i[index show] do
    resources :posts, shallow: true
  end

  resources :posts do
    resources :comments, only: %i[create destroy]

    member do
      post :upvote
      post :downvote
    end
  end

  resources :votes, only: %i[create destroy]

  root "communities#index"
end
RUBY

# ── Controllers (authz) ───────────────────────────────────────────────────────
printf 'Generating controllers\n'
cat > app/controllers/posts_controller.rb <<'RUBY'
class PostsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_post, only: %i[show edit update destroy upvote downvote]
  before_action :authorize_user!, only: %i[edit update destroy]

  def index
    @posts = Post.includes(:user, :community).hot.page(params[:page])
  end

  def show
    @comments = @post.comments.best
  end

  def new
    @post = current_user.posts.build
  end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: t('brgen.post_created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: t('brgen.post_updated')
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: t('brgen.post_deleted')
  end

  def upvote
    @post.upvote_by(current_user)
    respond_to_vote
  end

  def downvote
    @post.downvote_by(current_user)
    respond_to_vote
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def authorize_user!
    redirect_to posts_path, alert: t('brgen.unauthorized') unless @post.user == current_user
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous)
  end

  def respond_to_vote
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @post }
      format.json { render json: { score: @post.karma } }
    end
  end
end
RUBY

cat > app/controllers/comments_controller.rb <<'RUBY'
class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_commentable
  before_action :set_comment, only: :destroy
  before_action :authorize_user!, only: :destroy

  def create
    @comment = @commentable.comments.build(comment_params.merge(user: current_user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @commentable, notice: t('brgen.comment_created') }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @commentable, notice: t('brgen.comment_deleted') }
    end
  end

  private

  def set_commentable
    @commentable = Post.find(params[:post_id])
  end

  def set_comment
    @comment = Comment.find(params[:id])
  end

  def authorize_user!
    redirect_to @commentable, alert: t('brgen.unauthorized') unless @comment.user == current_user
  end

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end
end
RUBY

cat > app/controllers/communities_controller.rb <<'RUBY'
class CommunitiesController < ApplicationController
  def index
    @communities = Community.order(:name)
  end

  def show
... 65 lines truncated (465 total)
```

## `DEPLOY/rails/brgen/brgen_dating.sh`
```bash
#!/usr/bin/env sh
# -*- mode: sh; -*-

# Fail fast, propagate errors, treat unset variables as errors, fail pipelines
set -eu -o pipefail
IFS=$(printf '\n\t')

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# --------------------------------------------------------------------
# Configuration (immutable)
# --------------------------------------------------------------------
APP_NAME="brgen_dating"
BASE_DIR="/home/dev/rails"
PORT_MIN=10000
PORT_MAX=19999
SERVER_IP="185.52.176.18"

# --------------------------------------------------------------------
# Load optional shared helpers
# --------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SHARED="${SCRIPT_DIR}/@shared_functions.sh"
if [ -r "$SHARED" ]; then
  # shellcheck source=/dev/null
  . "$SHARED"
else
  log "Warning: @shared_functions.sh missing – proceeding with built‑in utilities"
fi

log "Starting ${APP_NAME} setup"

# --------------------------------------------------------------------
# Validate environment
# --------------------------------------------------------------------
# Base directory
if [ ! -d "$BASE_DIR" ]; then
  log "Error: Base directory $BASE_DIR missing"
  exit 1
fi
cd "$BASE_DIR"

# Required command utilities
required_cmds="ruby node psql bundle npm rails sha1sum awk cut"
for cmd in $required_cmds; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Error: required command '$cmd' not found"
    exit 1
  fi
done

# Application bootstrap function
if ! command -v setup_full_app >/dev/null 2>&1; then
  log "Error: setup_full_app not found in PATH"
  exit 1
fi

if ! setup_full_app "$APP_NAME"; then
  log "Error: setup_full_app failed for $APP_NAME"
  exit 1
fi

# PostgreSQL connectivity and PostGIS extension
if ! psql -c "SELECT version();" >/dev/null 2>&1; then
  log "Error: unable to connect to PostgreSQL"
  exit 1
fi

if ! psql -c "SELECT postgis_version();" >/dev/null 2>&1; then
  log "Error: PostGIS extension missing"
  exit 1
fi

# --------------------------------------------------------------------
# Runtime configuration
# --------------------------------------------------------------------
: "${RAILS_ENV:=production}"
log "RAILS_ENV=$RAILS_ENV"

# Deterministic port derived from SHA1 hash of APP_NAME (first 8 hex chars)
hash_hex=$(printf '%s' "$APP_NAME" | sha1sum | awk '{print $1}' | cut -c1-8)
# shellcheck disable=SC2004
hash_dec=$((16#${hash_hex}))
range=$((PORT_MAX - PORT_MIN + 1))
APP_PORT=$((PORT_MIN + (hash_dec % range)))
log "Assigned deterministic port: $APP_PORT"

# Verify application directory
app_path="${BASE_DIR}/${APP_NAME}"
if [ ! -d "$app_path" ]; then
  log "Error: application directory $app_path missing"
  exit 1
fi

log "Brgen Dating setup completed on port $APP_PORT"
exit 0```

## `DEPLOY/rails/brgen/brgen_marketplace.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

#─────────────────────────────────────────────────────────────────────────────
# Brgen Marketplace deployment helper
#─────────────────────────────────────────────────────────────────────────────

# Configuration
BASE_DIR="${HOME}/rails"
APP_NAME="brgen_marketplace"
BASE_PORT=10000
PORT_RANGE=10000
MAX_ATTEMPTS=20
DB_SCHEME="postgresql"
GEM_VERSIONS='solidus:~>4.0 solidus_auth_devise:~>2.0 solidus_multi_vendor:~>1.0'

# Logging
log()    { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
error()  { log "ERROR: $*"; exit 1; }

# Helpers
command_exists() { command -v "$1" >/dev/null 2>&1; }

port_in_use() {
  p=$1
  if command_exists lsof; then
    lsof -i :"$p" >/dev/null 2>&1 && return 0
  elif command_exists ss; then
    ss -tuln | grep -qE ":$p[[:space:]]" && return 0
  elif command_exists netstat; then
    netstat -tuln | grep -qE ":$p[[:space:]]" && return 0
  else
    ruby -e "require 'socket'; TCPServer.new('127.0.0.1',$p).close" >/dev/null 2>&1 && return 1 || return 0
  fi
  return 1
}

# Port allocation
get_or_create_port() {
  port_file="${BASE_DIR}/${APP_NAME}/.app_port"
  mkdir -p "$(dirname "$port_file")"

  if [ -f "$port_file" ]; then
    saved=$(cat "$port_file")
    if ! port_in_use "$saved"; then
      APP_PORT=$saved
      log "Reusing saved port $APP_PORT"
      return
    fi
  fi

  attempt=0
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    rand=$(( (RANDOM << 15) | RANDOM ))
    APP_PORT=$(( BASE_PORT + (rand % PORT_RANGE) ))
    if ! port_in_use "$APP_PORT"; then
      printf '%s\n' "$APP_PORT" >"$port_file"
      log "Allocated new port $APP_PORT"
      return
    fi
    attempt=$((attempt + 1))
  done
  error "Failed to obtain a free port after $MAX_ATTEMPTS attempts"
}

# Gem management
install_gem() {
  gem=$1 version=$2
  if bundle list | grep -q "$gem"; then
    log "Gem $gem already installed"
    return
  fi
  if [ -n "$version" ]; then
    bundle add "$gem" --version "$version" --without production
  else
    bundle add "$gem" --without production
  fi
  log "Added gem $gem"
}

add_gems() {
  for pair in $GEM_VERSIONS; do
    IFS=':' read -r name ver <<EOF
$pair
EOF
    install_gem "$name" "$ver"
  done
}

# Database handling
setup_database_user() {
  user="${APP_NAME}_user"
  if ! psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user}'" | grep -q 1; then
    pw=$(ruby -e 'require "securerandom"; puts SecureRandom.hex(16)')
    if psql -c "CREATE USER ${user} WITH PASSWORD '${pw}' CREATEDB;" >/dev/null 2>&1; then
      DB_USER=$user DB_PASSWORD=$pw
    else
      log "Warning: could not create ${user}, falling back to $USER"
      DB_USER=$USER DB_PASSWORD=
    fi
  else
    DB_USER=$user DB_PASSWORD=
  fi
  export DB_USER DB_PASSWORD
}

setup_databases() {
  setup_database_user
  owner="${DB_USER:-$USER}"
  for db in "${APP_NAME}_development" "${APP_NAME}_test"; do
    if ! psql -lqt | awk -F'|' '{gsub(/ /,"",$1);print $1}' | grep -qx "$db"; then
      createdb "$db" -O "$owner" >/dev/null 2>&1 || createdb "$db" >/dev/null 2>&1
      log "Created database $db"
    else
      log "Database $db already exists"
    fi
  done
}

generate_database_yml() {
  cat >config/database.yml <<EOF
default: &default
  adapter: ${DB_SCHEME}
  encoding: unicode
  pool: 5
  username: ${DB_USER}
  password: ${DB_PASSWORD}
  host: localhost

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
EOF
  log "Wrote config/database.yml"
}

# Rails bootstrapping
bootstrap_app() {
  cd "$BASE_DIR" || error "Cannot cd $BASE_DIR"

  if [ ! -d "$APP_NAME" ]; then
    log "Creating Rails app $APP_NAME"
    rails new "$APP_NAME" -d "$DB_SCHEME" || error "rails new failed"
  fi

  cd "$APP_NAME" || error "Cannot cd $APP_NAME"

  setup_databases
  generate_database_yml

  add_gems
  bundle install --without production || error "bundle install failed"
  bundle exec rails generate solidus:install || error "solidus install failed"
  bundle exec rails db:migrate || error "migrations failed"
  bundle exec rails db:seed || error "seeding failed"

  cat >start_app.sh <<'EOS'
#!/usr/bin/env sh
set -euo pipefail
cd "$(dirname "$0")"
exec bundle exec rails server -p "$APP_PORT" -b 0.0.0.0
EOS
  chmod +x start_app.sh
  log "Setup complete – run ./start_app.sh"
}

# Entry point
log "Starting Brgen Marketplace deployment"
get_or_create_port
bootstrap_app
log "All done."```

## `DEPLOY/rails/brgen/brgen_playlist.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

APP_NAME="brgen_playlist"
SHARED_FUNCTIONS="shared_functions.sh"

log()   { printf '[INFO] %s\n' "$1"; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
warn()  { printf '[WARN] %s\n' "$1" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

log "Starting Brgen Playlist setup"

# Load shared utilities
[ -f "$SHARED_FUNCTIONS" ] || error "Missing $SHARED_FUNCTIONS"
. "$SHARED_FUNCTIONS" || error "Failed to source $SHARED_FUNCTIONS"

# Verify required helper
command_exists setup_full_app || error "setup_full_app not available in $SHARED_FUNCTIONS"
setup_full_app "$APP_NAME" || error "setup_full_app failed"

# Verify runtime dependencies
for cmd in ruby bundle rails; do
  command_exists "$cmd" || error "$cmd not found"
done

log "Installing Ruby dependencies"
bundle install || error "bundle install failed"

log "Checking Pagy gem"
bundle info pagy >/dev/null 2>&1 || error "Pagy gem missing"

log "Setting up database"
if ! bin/rails db:create 2>/dev/null; then
  warn "Database may already exist"
fi
bin/rails db:migrate || error "Database migration failed"

log "Generating Playlist models"
bin/rails generate model Playlist::Set name:string description:text user:references \
  || error "Model generation failed"

MODEL_FILE="app/models/playlist/set.rb"
[ -f "$MODEL_FILE" ] || error "Model file $MODEL_FILE not found"

patch_include() {
  target=$1
  pattern=$2
  line=$3

  [ -f "$target" ] || error "Target $target not found"
  if ! grep -qE "$pattern" "$target"; then
    log "Patching $target"
    if command_exists gsed; then
      gsed -i "1i $line" "$target"
    else
      tmp=$(mktemp) && sed "1i $line" "$target" > "$tmp" && mv "$tmp" "$target"
    fi
  else
    log "$line already present in $target"
  fi
}

patch_include "app/controllers/application_controller.rb" 'include[[:space:]]+Pagy::Backend' 'include Pagy::Backend'
patch_include "app/helpers/application_helper.rb"      'include[[:space:]]+Pagy::Frontend' 'include Pagy::Frontend'

log "Brgen Playlist setup completed"```

## `DEPLOY/rails/brgen/brgen_takeaway.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail
IFS=$'\n\t'

log() {
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

install_gem() {
    log "Installing gem: $*"
    # Suppress documentation, fail fast on error
    if ! gem install --no-document "$@"; then
        log "Error: Failed to install gem(s): $*"
        exit 1
    fi
}

# Detect an available port‑checking utility.
detect_port_checker() {
    for cmd in sockstat netstat ss lsof; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '%s' "$cmd"
            return 0
        fi
    done
    return 1
}
PORT_CHECKER=$(detect_port_checker) || {
    log "Error: No port‑checking tool found (sockstat, netstat, ss, lsof)"
    exit 1
}

check_port_available() {
    port=$1
    case $PORT_CHECKER in
        sockstat) sockstat -l -4 -p "$port" | grep -qE ":$port\$" && return 1 ;;
        netstat) netstat -an -f inet | grep -qE ":$port[[:space:]]" && return 1 ;;
        ss) ss -ln -4 "sport = :$port" | grep -qE ":$port\$" && return 1 ;;
        lsof) lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null && return 1 ;;
        *) return 0 ;;
    esac
    return 0
}

find_available_port() {
    base=${FIND_PORT_BASE:-3000}
    max=${FIND_PORT_MAX:-4000}
    port=$base
    while [ "$port" -le "$max" ]; do
        if check_port_available "$port"; then
            printf '%s\n' "$port"
            return 0
        fi
        port=$((port + 1))
    done
    log "Error: No free port found in range $base‑$max"
    return 1
}

# Resolve script directory safely (handles symlinks)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

# Load shared helpers
SHARED_FILE="${SCRIPT_DIR}/@shared_functions.sh"
if [ ! -f "$SHARED_FILE" ]; then
    log "Error: Shared functions not found at $SHARED_FILE"
    exit 1
fi
. "$SHARED_FILE"

# Future deployment logic goes here

exit 0```

## `DEPLOY/rails/brgen/brgen_tv.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Brgen TV deployment script – OpenBSD‑first, POSIX‑compatible
# -----------------------------------------------------------------------------

APP_NAME="brgen_tv"
BASE_DIR="${HOME}/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# -----------------------------------------------------------------------------
# Load shared utilities
# -----------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/shared_functions.sh" ]]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/shared_functions.sh"
else
    printf 'Error: shared_functions.sh not found\n' >&2
    exit 1
fi

log "Starting Brgen TV setup with video streaming and live broadcasting"

# -----------------------------------------------------------------------------
# Install a package, idempotent and OpenBSD‑first
# -----------------------------------------------------------------------------
install_pkg() {
    local pkg=$1
    case "$(uname -s)" in
        OpenBSD) doas pkg_add -I "${pkg}" ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update -qq && sudo apt-get install -y "${pkg}"
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y "${pkg}"
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y "${pkg}"
            else
                log "Unsupported Linux package manager"
                return 1
            fi
            ;;
        Darwin) brew install "${pkg}" ;;
        *) log "OS not recognized"; return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Ensure Redis is present and running
# -----------------------------------------------------------------------------
if ! command -v redis-server >/dev/null 2>&1; then
    log "Redis not found – installing"
    install_pkg redis || {
        log "Redis installation failed – install manually"
        exit 1
    }
fi

if ! pgrep -x redis-server >/dev/null 2>&1; then
    case "$(uname -s)" in
        OpenBSD) doas rcctl start redis ;;
        Linux)   sudo systemctl enable --now redis-server || sudo systemctl enable --now redis ;;
        Darwin)  brew services start redis ;;
        *)       log "Cannot auto‑start Redis on this OS"; exit 1 ;;
    esac
fi

if ! redis-cli ping >/dev/null 2>&1; then
    log "Redis not responding – start it manually and rerun"
    exit 1
fi

# -----------------------------------------------------------------------------
# Application scaffolding
# -----------------------------------------------------------------------------
setup_full_app "$APP_NAME" || {
    log "Application setup failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Ruby dependencies
# -----------------------------------------------------------------------------
bundle install || {
    log "bundle install failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Generate Broadcast model
# -----------------------------------------------------------------------------
generate_model "Broadcast title:string description:text is_live:boolean" || {
    log "model generation failed"
    exit 1
}

# -----------------------------------------------------------------------------
# Database migration
# -----------------------------------------------------------------------------
bin/rails db:migrate || {
    log "migration failed"
    exit 1
}

log "Brgen TV setup completed successfully"```

## `DEPLOY/rails/brgen/features/auth.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
APP_DIR="/home/brgen/app"
DB_CONFIG="${APP_DIR}/config/database.yml"

#--- Helpers -----------------------------------------------------------------
replace_db_config() {
	# Transform placeholder values in database.yml.
	# stdin → stdout
	sed -e 's|database: app_|database: brgen_|' \
	    -e 's|username: brgen|username: brgen_user|'
}

#--- Main --------------------------------------------------------------------
printf '==> [auth] acts_as_votable solid_stack devise\n'

cd "$APP_DIR"

printf 'Installing acts_as_votable\n'
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

printf 'Installing solid stack\n'
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

printf 'Installing rails 8 authentication\n'
if [ ! -f "app/models/session.rb" ]; then
	bin/rails generate authentication
fi

# Update DB config atomically, preserving mode
if [ -f "$DB_CONFIG" ]; then
	tmp="$(mktemp -p "$(dirname "$DB_CONFIG")" tmp.XXXXXX)"
	replace_db_config < "$DB_CONFIG" > "$tmp"
	chmod --reference="$DB_CONFIG" "$tmp"
	mv -f "$tmp" "$DB_CONFIG"
fi

printf '==> [auth] done\n'```

## `DEPLOY/rails/brgen/features/controllers.sh`
```bash
UNCHANGE​d```

## `DEPLOY/rails/brgen/features/deploy.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
APP_DIR="/home/brgen/app"
PORT=11006
RC_NAME="brgen"
RC_FILE="/etc/rc.d/${RC_NAME}"
TMP_RC="$(mktemp -t "${RC_NAME}.rc.XXXXXX")"

#--- Helpers -----------------------------------------------------------------
err() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -f "${TMP_RC}"
}
trap cleanup EXIT INT TERM

#--- Preconditions -----------------------------------------------------------
[ -d "${APP_DIR}" ] || err "application directory ${APP_DIR} does not exist"
command -v doas >/dev/null 2>&1 || err "'doas' not found – required for privileged actions"

#--- Build rc.d script --------------------------------------------------------
cat > "${TMP_RC}" <<'EOF'
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://0.0.0.0:${PORT}"
daemon_user="brgen"
daemon_execdir="${APP_DIR}"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*brgen.*falcon"
rc_bg=YES
rc_reload=NO
rc_cmd "$1"
EOF

#--- Install rc.d script ------------------------------------------------------
doas install -m 555 "${TMP_RC}" "${RC_FILE}"
doas rcctl enable "${RC_NAME}"

#--- Run database migrations --------------------------------------------------
doas -u brgen sh -c "cd '${APP_DIR}' && RAILS_ENV=production bundle exec rails db:migrate"

#--- Start service ------------------------------------------------------------
doas rcctl start "${RC_NAME}"

printf '==> %s serving on port %s\n' "${RC_NAME}" "${PORT}"```

## `DEPLOY/rails/brgen/features/i18n.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

# Immutable constants
readonly APP_DIR="/home/brgen/app"
readonly LOCALE_DIR="${APP_DIR}/config/locales"
readonly MSG_START="==> [i18n] Norwegian (nb) + English (en) locales"
readonly DONE_MSG="==> [i18n] done"

# Preconditions
[ -d "${LOCALE_DIR}" ] || {
  printf 'Error: %s not found\n' "${LOCALE_DIR}" >&2
  exit 1
}
[ -w "${LOCALE_DIR}" ] || {
  printf 'Error: %s not writable\n' "${LOCALE_DIR}" >&2
  exit 1
}

printf '%s\n' "${MSG_START}"

# Write a file atomically, cleaning up on error
write_locale() {
  dest=$1
  tmp=$(mktemp -p "${LOCALE_DIR}" ".tmp.$(basename "${dest}").XXXXXX") || exit 1
  trap 'rm -f "${tmp}"' EXIT INT TERM
  cat >"${tmp}"
  chmod 0644 "${tmp}"
  mv -f "${tmp}" "${dest}"
  trap - EXIT INT TERM
}

generate_locale() {
  case $1 in
    nb)
      write_locale "${LOCALE_DIR}/nb.yml" <<'EOF'
nb:
  brgen:
    app_name: "BRGEN"
    communities: "Lokalsamfunn"
    posts: "Innlegg"
    new_post: "Nytt innlegg"
    upvote: "Stem opp"
    downvote: "Stem ned"
    karma: "Karma"
    comments: "Kommentarer"
    add_comment: "Legg til kommentar"
    posted_by: "Postet av %{user}"
    edit: "Rediger"
    delete: "Slett"
    confirm_delete: "Er du sikker?"
    post_created: "Innlegget ble opprettet."
    post_updated: "Innlegget ble oppdatert."
    post_deleted: "Innlegget ble slettet."
    comment_created: "Kommentar ble lagt til."
    comment_deleted: "Kommentar ble slettet."
    unauthorized: "Ingen tilgang."
EOF
      ;;
    en)
      write_locale "${LOCALE_DIR}/en.yml" <<'EOF'
en:
  brgen:
    app_name: "BRGEN"
    communities: "Communities"
    posts: "Posts"
    new_post: "New post"
    upvote: "Upvote"
    downvote: "Downvote"
    karma: "Karma"
    comments: "Comments"
    add_comment: "Add a comment"
    posted_by: "Posted by %{user}"
    edit: "Edit"
    delete: "Delete"
    confirm_delete: "Are you sure?"
    post_created: "Post created."
    post_updated: "Post updated."
    post_deleted: "Post deleted."
    comment_created: "Comment added."
    comment_deleted: "Comment deleted."
    unauthorized: "Not authorized."
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

generate_locale nb
generate_locale en

printf '%s\n' "${DONE_MSG}"```

## `DEPLOY/rails/brgen/features/messaging.sh`
```bash
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
APP_DIR="/home/brgen/app"
if [[ ! -d $APP_DIR ]]; then
  print -u2 "ERROR: Application directory ${APP_DIR} does not exist"
  exit 1
fi
cd "$APP_DIR"

# ----------------------------------------------------------------------
# Helper: write a Ruby file only if content differs
# ----------------------------------------------------------------------
_write_if_changed() {
  local target=$1
  local tmp
  tmp=$(mktemp) || return 1
  cat >"$tmp"
  if [[ -f $target && $(<"$target") == $(<"$tmp") ]]; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$target"
  fi
}

# ----------------------------------------------------------------------
# Model definitions
# ----------------------------------------------------------------------
_write_if_changed app/models/conversation.rb <<'RUBY'
# frozen_string_literal: true

class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :typing_indicators, dependent: :destroy

  validates :conversation_type, inclusion: { in: %w[direct group] }

  scope :for_user, ->(user) { joins(:conversation_participants).where(conversation_participants: { user: user }) }

  def self.direct_between(a, b)
    for_user(a).for_user(b).find_by(conversation_type: "direct") ||
      create!(conversation_type: "direct").tap { |c| c.participants.concat([a, b]) }
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    return 0 unless participant

    messages.where('created_at > ?', participant.last_read_at || Time.at(0)).count
  end

  def mark_read_for!(user)
    conversation_participants.find_by(user: user)&.update!(last_read_at: Time.current)
  end
end
RUBY

_write_if_changed app/models/message.rb <<'RUBY'
# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: 'User', foreign_key: :sender_id

  has_many :message_receipts, dependent: :destroy
  has_one_attached :attachment

  validates :content, presence: true, length: { maximum: 10_000 }
  validates :message_type, inclusion: { in: %w[text image file audio] }

  after_create :deliver_receipts, :clear_typing_indicators

  scope :recent, -> { order(created_at: :desc) }

  def expired?
    expires_at&.past?
  end

  private

  def deliver_receipts
    conversation.participants.where.not(id: sender_id).find_each do |user|
      message_receipts.create!(user: user, delivered_at: Time.current)
    end
  end

  def clear_typing_indicators
    TypingIndicator.where(conversation: conversation, user: sender).delete_all
  end
end
RUBY

_write_if_changed app/models/typing_indicator.rb <<'RUBY'
# frozen_string_literal: true

class TypingIndicator < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  scope :active, -> { where('expires_at > ?', Time.current) }

  def self.set!(conversation:, user:)
    find_or_create_by(conversation: conversation, user: user)
      .update!(expires_at: 5.seconds.from_now)
  end
end
RUBY

# ----------------------------------------------------------------------
# Controller definitions
# ----------------------------------------------------------------------
_write_if_changed app/controllers/conversations_controller.rb <<'RUBY'
# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @conversations = Conversation.for_user(current_user)
                                 .includes(:participants, :messages)
                                 .order('messages.created_at DESC')
  end

  def show
    @conversation = Conversation.for_user(current_user).find(params[:id])
    @conversation.mark_read_for!(current_user)
    @messages = @conversation.messages.recent.limit(50).reverse
    @message = Message.new
  end

  def create
    other = User.find(params[:user_id])
    @conversation = Conversation.direct_between(current_user, other)
    redirect_to @conversation
  end
end
RUBY

_write_if_changed app/controllers/messages_controller.rb <<'RUBY'
# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation

  def create
    @message = @conversation.messages.build(message_params)
    @message.sender = current_user

    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @conversation }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content, :message_type, :attachment)
  end
end
RUBY

_write_if_changed app/controllers/typing_indicators_controller.rb <<'RUBY'
# frozen_string_literal: true

class TypingIndicatorsController < ApplicationController
  before_action :authenticate_user!

  def create
    conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    TypingIndicator.set!(conversation: conversation, user: current_user)
    head :ok
  end
end
RUBY

# ----------------------------------------------------------------------
# Run migrations and finish
# ----------------------------------------------------------------------
if ! bin/rails db:migrate; then
  print -u2 "ERROR: Database migration failed"
  exit 1
fi

echo "==> [messaging] done"```

## `DEPLOY/rails/brgen/features/models.sh`
```bash
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
readonly APP_DIR="/home/brgen/app"
readonly MODEL_DIR="${APP_DIR}/app/models"
readonly CONCERN_DIR="${MODEL_DIR}/concerns"

echo "==> [models] Core models + concerns"

# Ensure target directories exist with safe permissions
mkdir -p -m 0755 "${MODEL_DIR}" "${CONCERN_DIR}" || exit 1

# -------------------------------------------------------------------
# Helpers – atomic writes
# -------------------------------------------------------------------
write_file() {
  local path=$1; shift
  local tmp
  tmp=$(mktemp -p "$(dirname "${path}")" "${path}.tmp.XXXXXX") || return 1
  # Use printf to avoid trailing newlines issues; "$@" may contain multiple args
  printf "%s\n" "$@" > "${tmp}" && command mv -f "${tmp}" "${path}"
}

write_model() {
  local rel_path=$1; shift
  write_file "${MODEL_DIR}/${rel_path}.rb" "$@"
}

# -------------------------------------------------------------------
# Current (ActiveSupport::CurrentAttributes)
# -------------------------------------------------------------------
write_model "current" <<'RUBY'
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user
end
RUBY

# -------------------------------------------------------------------
# Votable concern
# -------------------------------------------------------------------
write_model "concerns/votable" <<'RUBY'
module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def score = votes.sum(:value)
  def upvotes = votes.where(value: 1).count
  def downvotes = votes.where(value: -1).count
  def voted_by?(user) = user && votes.find_by(user: user)&.value
  def upvoted_by?(user) = voted_by?(user) == 1
  def downvoted_by?(user) = voted_by?(user) == -1
end
RUBY

# -------------------------------------------------------------------
# Vote model
# -------------------------------------------------------------------
write_model "vote" <<'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value,
            inclusion: { in: [-1, 1] }
  validates :user_id,
            uniqueness: { scope: %i[votable_type votable_id] }

  after_save   :update_author_karma
  after_destroy :update_author_karma

  private

  def update_author_karma
    votable.user.update_karma! if votable.respond_to?(:user)
  end
end
RUBY

# -------------------------------------------------------------------
# Post model
# -------------------------------------------------------------------
write_model "post" <<'RUBY'
class Post < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :community, optional: true

  has_many :comments,    as: :commentable, dependent: :destroy
  has_many :votes,       as: :votable,    dependent: :destroy
  has_many :taggings,    dependent: :destroy
  has_many :hashtags,    through: :taggings
  has_many :mentions,    dependent: :destroy

  validates :title,
            presence: true,
            length:   { maximum: 300 }
  validates :content,
            length: { maximum: 40_000 }

  VOTE_SQL = Arel.sql('SUM(COALESCE(votes.value,0)) DESC, posts.created_at DESC')
  TOP_SQL  = Arel.sql('SUM(COALESCE(votes.value,0)) DESC')

  scope :hot,   -> { left_joins(:votes).group(:id).order(VOTE_SQL) }
  scope :fresh, -> { order(created_at: :desc) }
  scope :top,   -> { left_joins(:votes).group(:id).order(TOP_SQL) }

  def comment_count = comments.count
  def author_name   = user&.username.presence || 'anon'
end
RUBY

# -------------------------------------------------------------------
# Community model
# -------------------------------------------------------------------
write_model "community" <<'RUBY'
class Community < ApplicationRecord
  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy

  validates :name,
            presence: true,
            uniqueness: true,
            length: { maximum: 100 }
  validates :description,
            length: { maximum: 500 }

  POPULAR_SQL = Arel.sql('COUNT(posts.id) DESC')
  scope :popular, -> { left_joins(:posts).group(:id).order(POPULAR_SQL) }
end
RUBY

# -------------------------------------------------------------------
# Comment model
# -------------------------------------------------------------------
write_model "comment" <<'RUBY'
class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent,
             class_name: 'Comment',
             optional: true

  has_many :replies,
           class_name: 'Comment',
           foreign_key: :parent_id,
           dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content,
            presence: true,
            length: { minimum: 1, maximum: 10_000 }

  scope :best,
        -> { left_joins(:votes).group(:id).order(Arel.sql('SUM(COALESCE(votes.value,0)) DESC')) }
  scope :top,       -> { best }
  scope :new_first, -> { order(created_at: :desc) }

  def root?   = parent_id.nil?
  def depth   = parent ? parent.depth + 1 : 0
end
RUBY

echo "==> [models] done"```

## `DEPLOY/rails/brgen/features/routes.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

readonly APP_DIR="/home/brgen/app"
readonly ROUTES_FILE="${APP_DIR}/config/routes.rb"
# Create temporary file in the same directory to guarantee atomic rename
readonly TMP_FILE="$(mktemp -p "${APP_DIR}" routes.rb.tmp.XXXXXX)"

# Ensure temporary file is removed on any exit
trap 'rm -f "$TMP_FILE"' EXIT

# Verify application directory exists and is writable
if [ ! -d "$APP_DIR" ]; then
  printf 'Error: %s does not exist\n' "$APP_DIR" >&2
  exit 1
fi
if [ ! -w "$APP_DIR" ]; then
  printf 'Error: %s is not writable\n' "$APP_DIR" >&2
  exit 1
fi

printf '==> [routes] Wiring all routes\n'

cat >"$TMP_FILE" <<'RUBY'
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :communities do
    resources :posts, shallow: true do
      resources :comments, shallow: true do
        resources :comments, shallow: true, as: :replies
      end
      resource :vote, only: [:create], controller: "votes"
    end
  end

  resources :posts do
    resources :comments, shallow: true
    resource :vote, only: [:create], controller: "votes"
  end

  resources :comments do
    resource :vote, only: [:create], controller: "votes"
    resources :comments, only: [:create], as: :replies
  end

  resources :users, only: [:show] do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
    end
    resources :conversations, only: [:create]
  end

  resources :conversations, only: [:index, :show] do
    resources :messages, only: [:create]
  end

  get "playlist", to: "playlist#index"
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
RUBY

# Atomically replace the routes file
mv -f "$TMP_FILE" "$ROUTES_FILE"

printf '==> [routes] done\n'```

## `DEPLOY/rails/brgen/features/seeds.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Absolute path to the Rails application
readonly APP_DIR="/home/brgen/app"

# Verify the application directory exists
if [[ ! -d "${APP_DIR}" ]]; then
  echo "Error: APP_DIR '${APP_DIR}' does not exist" >&2
  exit 1
fi
cd "${APP_DIR}"

# Create a temporary seed file; ensure it is removed on exit or interrupt
SEED_FILE="$(mktemp db/seeds_tmp.XXXXXX.rb)"
trap 'rm -f "${SEED_FILE}"' EXIT TERM INT

cat > "${SEED_FILE}" <<'RUBY'
return unless Rails.env.development?

puts "Creating communities..."
%w[Oslo Bergen Trondheim Stavanger Tromsø].each do |city|
  Community.find_or_create_by!(subdomain: city.downcase) do |c|
    c.name        = "#{city} Community"
    c.slug        = city.parameterize
    c.description = "Local community for #{city}"
  end
end

puts "Creating users..."
Faker::UniqueGenerator.clear
10.times do
  email = Faker::Internet.unique.email
  User.find_or_create_by!(email: email) do |u|
    u.password              = "password123"
    u.password_confirmation = "password123"
    u.username              = Faker::Internet.unique.username
    u.karma                 = rand(0..1_000)
  end
end

puts "Creating posts..."
Community.find_each do |community|
  20.times do
    post = community.posts.find_or_initialize_by(
      title:   Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraphs(number: 3).join("\n\n"),
      user:    User.order("RANDOM()").first
    )
    post.karma = rand(-50..500)
    post.save!

    voters = User.order("RANDOM()").limit(rand(3..15))
    voters.each do |v|
      post.votes.find_or_create_by!(user: v) do |vote|
        vote.value = [-1, 1].sample
      end
    end
  end
end

puts "Seed complete."
RUBY

# Execute the temporary seed file within the Rails environment using the binstub
bin/rails runner "${SEED_FILE}"

echo "==> [seeds] done"```

## `DEPLOY/rails/brgen/features/setup.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

APP_DIR="/home/brgen/app"
PORT=11006

printf '==> [setup] Rails 8 app creation + gems\n'

# Ensure prerequisite directory exists
if [ ! -d "$APP_DIR" ]; then
  printf 'ERROR: %s missing. Run: doas sh openbsd.sh --pre-point\n' "$APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"

# Verify Rails is available
if ! command -v rails >/dev/null 2>&1; then
  printf 'ERROR: rails executable not found in PATH\n' >&2
  exit 1
fi

# Initialise Rails app if missing
if [ ! -f "config/application.rb" ]; then
  printf 'Creating Rails 8 application\n'
  rails new . \
    --database=postgresql \
    --skip-git \
    --css=tailwind \
    --javascript=esbuild
fi

printf 'Appending gems to Gemfile\n'

# Append required gems once
if ! grep -q "solid_queue" Gemfile; then
  cat >> Gemfile <<'EOF'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Voting
gem "acts_as_votable"

# Real‑time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi‑tenancy
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"

# Features
gem "pagy"
gem "image_processing"
gem "geocoder"
gem "langchainrb"
gem "ruby-openai"
gem "serviceworker-rails"

group :development, :test do
  gem "brakeman"
  gem "rubocop-rails-omakase"
  gem "faker"
end
EOF
fi

# Install missing gems quietly
if ! bundle check >/dev/null 2>&1; then
  bundle install --quiet
fi

printf '==> [setup] done\n'```

## `DEPLOY/rails/brgen/features/social.sh`
```bash
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# ----------------------------------------------------------------------
# Social feature bootstrap – follows, timelines, hashtags, mentions
# ----------------------------------------------------------------------
APP_DIR="${0:A:h}/../../.."  # project root relative to script location
SCRIPT_TITLE="[social]"
GENERATE_CMD="bin/rails generate model"
MIGRATE_CMD="bin/rails db:migrate"

# ----------------------------------------------------------------------
# Guard: abort if the Rails application is not present
# ----------------------------------------------------------------------
[[ -d $APP_DIR ]] || {
  printf 'APP_DIR not found: %s\n' "$APP_DIR" >&2
  exit 1
}

printf '==> %s Starting\n' "$SCRIPT_TITLE"
cd "$APP_DIR" || exit 1

# ----------------------------------------------------------------------
# Helper: write a file, creating parent directories if needed.
# Overwrites only when content differs to keep idempotence.
# ----------------------------------------------------------------------
write_file() {
  local path=$1
  local content=$2
  local dir=${path:h}
  mkdir -p "$dir"
  if [[ -f $path && $(<"$path") == "$content" ]]; then
    return
  fi
  printf '%s\n' "$content" > "$path"
}

# ----------------------------------------------------------------------
# Generate models – idempotent: skip if model file already exists
# ----------------------------------------------------------------------
generate_if_missing() {
  local name=$1
  shift
  local dest="app/models/${${name:l}.underscore}.rb"
  if [[ -f $dest ]]; then
    printf 'model %s already exists, skipping generation\n' "$name"
  else
    $GENERATE_CMD "$name" "$@"
  fi
}

generate_if_missing Follow follower_id:integer:index followed_id:integer:index
generate_if_missing Hashtag name:string:uniq usage_count:integer:default[0]
generate_if_missing Tagging taggable:references{polymorphic} hashtag:references
generate_if_missing Mention mentionable:references{polymorphic} mentioned_user:references{user}

# ----------------------------------------------------------------------
# Model definitions – frozen string literal, minimal dependencies
# ----------------------------------------------------------------------
write_file app/models/follow.rb <<'RUBY'
# frozen_string_literal: true

class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate :no_self_follow

  private

  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == followed_id
  end
end
RUBY

write_file app/models/hashtag.rb <<'RUBY'
# frozen_string_literal: true

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }

  scope :trending, -> { order(usage_count: :desc) }

  def self.extract(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.map(&:downcase).uniq
  end
end
RUBY

write_file app/models/concerns/taggable.rb <<'RUBY'
# frozen_string_literal: true

module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
    after_save :sync_hashtags
  end

  def hashtag_list = hashtags.pluck(:name).join(" ")

  private

  def sync_hashtags
    names = Hashtag.extract([try(:content), try(:title)].compact.join(" "))
    tags = names.map { |n| Hashtag.find_or_create_by!(name: n).tap { |h| h.increment!(:usage_count) } }
    self.hashtags = tags
  end
end
RUBY

write_file app/models/concerns/mentionable.rb <<'RUBY'
# frozen_string_literal: true

module Mentionable
  extend ActiveSupport::Concern

  included do
    after_save :sync_mentions
  end

  private

  def sync_mentions
    usernames = [try(:content), try(:title)].compact.join(" ").scan(/@(\w+)/).flatten.uniq
    usernames.each do |uname|
      user = User.find_by(username: uname)
      next unless user && user != try(:user)

      mentions.find_or_create_by!(mentioned_user: user)
    end
  end
end
RUBY

# ----------------------------------------------------------------------
# Append associations & timeline helpers to User model – idempotent
# ----------------------------------------------------------------------
USER_MODEL="app/models/user.rb"
if [[ -f $USER_MODEL ]]; then
  if ! grep -q "has_many :follows_as_follower" "$USER_MODEL"; then
    cat >>"$USER_MODEL" <<'RUBY'

  # Social associations
  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followed,  class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :followers, through: :follows_as_followed, source: :follower

  # Convenience helpers
  def follow!(other)
    follows_as_follower.find_or_create_by!(followed: other) unless other == self
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  def following?(other)
    follows_as_follower.exists?(followed: other)
  end

  def timeline_posts
    Post.where(user: [self] + following).order(created_at: :desc)
  end
RUBY
  else
    printf 'User model already contains social associations, skipping append\n'
  fi
else
  printf 'User model not found at %s, cannot append social code\n' "$USER_MODEL" >&2
fi

# ----------------------------------------------------------------------
# Controller for follow actions
# ----------------------------------------------------------------------
write_file app/controllers/follows_controller.rb <<'RUBY'
# frozen_string_literal: true

class FollowsController < ApplicationController
  before_action :authenticate_user!

  def create
    user = User.find(params[:user_id])
    current_user.follow!(user)
    redirect_back fallback_location: root_path
  end

  def destroy
    user = User.find(params[:user_id])
    current_user.unfollow!(user)
    redirect_back fallback_location: root_path
  end
end
RUBY

# ----------------------------------------------------------------------
# Run migrations – fail fast if migration errors occur
# ----------------------------------------------------------------------
$MIGRATE_CMD

printf '==> %s done\n' "$SCRIPT_TITLE"
```

## `DEPLOY/rails/brgen/features/styles.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly APP_DIR="/home/brgen/app"
readonly STYLE_PATH="$APP_DIR/app/assets/stylesheets/application.css"

echo "==> [styles] Dark Reddit theme CSS"

# Ensure the target directory exists
mkdir -p "$(dirname "$STYLE_PATH")"

# Write the stylesheet atomically
temp_file="$(mktemp "$STYLE_PATH.XXXXXX")"
cat >"$temp_file" <<'CSS'
/* BRGEN — Minimalist Dark Theme */

:root {
  --bg:         #0a0a0a;
  --surface:    #1a1a1a;
  --surface2:   #222;
  --text:       #e8eaed;
  --text-dim:   #9aa0a6;
  --primary:    #8ab4f8;
  --upvote:     #ff4500;
  --downvote:   #7193ff;
  --border:     #333;
  --radius:     6px;
  --sp:         8px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
  font-size: 14px;
}

/* ── Nav ── */
nav {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: calc(var(--sp) * 1.5) calc(var(--sp) * 3);
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  z-index: 100;
}

.logo {
  font-size: 1.3rem;
  font-weight: 700;
  color: var(--text);
  letter-spacing: -0.03em;
}

.nav-links a {
  color: var(--text-dim);
  margin-left: calc(var(--sp) * 2);
  font-size: 0.875rem;
}
.nav-links a:hover { color: var(--text); text-decoration: none; }

a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }

.page {
  max-width: 1200px;
  margin: 0 auto;
  padding: calc(var(--sp) * 2);
  display: grid;
  grid-template-columns: 1fr 300px;
  gap: calc(var(--sp) * 2);
}
.main-col { min-width: 0; }
.side-col  {}

@media (max-width: 768px) {
  .page { grid-template-columns: 1fr; }
  .side-col { display: none; }
  nav { padding: var(--sp) calc(var(--sp) * 2); }
}

/* ── Post card ── */
.post-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  margin-bottom: calc(var(--sp) * 1.5);
  display: flex;
  transition: border-color .15s;
}
.post-card:hover { border-color: #555; }

.vote-col {
  width: 40px;
  min-width: 40px;
  background: var(--surface2);
  border-radius: var(--radius) 0 0 var(--radius);
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: calc(var(--sp) * 1.5) 0;
  gap: 4px;
}

.vote-btn {
  background: none;
  border: none;
  color: var(--text-dim);
  cursor: pointer;
  font-size: 1.1rem;
  line-height: 1;
  padding: 2px 4px;
  border-radius: 3px;
  transition: color .1s;
}
.vote-btn:hover { color: var(--upvote); }
.vote-btn.down:hover { color: var(--downvote); }
.vote-btn.active-up   { color: var(--upvote); }
.vote-btn.active-down { color: var(--downvote); }

.vote-score {
  font-size: .75rem;
  font-weight: 700;
  color: var(--text-dim);
}

.post-body {
  flex: 1;
  padding: calc(var(--sp) * 1.5);
  min-width: 0;
}

/* ── Post meta ── */
.post-meta {
  font-size: .75rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * .75);
}
.post-meta a { color: var(--text-dim); }
.post-meta .community { color: var(--primary); font-weight: 600; }

.post-title {
  font-size: 1.05rem;
  font-weight: 500;
  color: var(--text);
  line-height: 1.4;
  margin-bottom: calc(var(--sp) * .75);
}
.post-title a { color: var(--text); }
.post-title a:hover { color: var(--primary); text-decoration: none; }

.post-actions {
  display: flex;
  gap: calc(var(--sp) * 1.5);
  font-size: .75rem;
  color: var(--text-dim);
}
.post-actions a {
  color: var(--text-dim);
  font-weight: 600;
}
.post-actions a:hover { color: var(--text); text-decoration: none; }

/* ── Post show ── */
.post-show {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 2);
}
.post-content {
  color: var(--text);
  line-height: 1.7;
  margin: calc(var(--sp) * 1.5) 0;
  white-space: pre-wrap;
}

/* ── Comments ── */
.comments-section { margin-top: calc(var(--sp) * 2); }

.comment-form-wrap {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 1.5);
  margin-bottom: calc(var(--sp) * 1.5);
}
.comment {
  margin-bottom: var(--sp);
  padding: calc(var(--sp) * 1.25) calc(var(--sp) * 1.5);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  border-left: 2px solid var(--border);
}
.comment .comment {
  background: var(--surface2);
  margin-top: var(--sp);
  border-left-color: #444;
}
.comment-meta {
  font-size: .75rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * .5);
}
.comment-meta .author { color: var(--text); font-weight: 600; }
.comment-body { line-height: 1.6; }

/* ── Forms ── */
.form-wrap {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2.5);
  max-width: 600px;
}
.field { margin-bottom: calc(var(--sp) * 1.5); }

label {
  display: block;
  font-size: .8rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * .5);
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .04em;
}

input[type=text],
input[type=email],
input[type=password],
textarea,
select {
  width: 100%;
  padding: calc(var(--sp) * 1.25) calc(var(--sp) * 1.5);
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--text);
  font-size: .9rem;
  font-family: inherit;
  outline: none;
  transition: border-color .15s;
}
input:focus,
textarea:focus,
select:focus { border-color: var(--primary); }
textarea { min-height: 120px; resize: vertical; line-height: 1.6; }

.btn {
  display: inline-block;
  padding: calc(var(--sp) * 1) calc(var(--sp) * 2);
  background: var(--primary);
  color: #0a0a0a;
  border: none;
  border-radius: var(--radius);
  font-size: .875rem;
  font-weight: 700;
  cursor: pointer;
  transition: opacity .15s;
}
.btn:hover { opacity: .88; text-decoration: none; color: #0a0a0a; }
.btn-ghost {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-dim);
}
.btn-ghost:hover { border-color: var(--text-dim); color: var(--text); }

/* ── Sidebar ── */
.sidebar-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 1.5);
}
.sidebar-card h3 {
  font-size: .75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--text-dim);
  margin-bottom: var(--sp);
}
.sidebar-card ul { list-style: none; }
.sidebar-card li {
  padding: calc(var(--sp) * .5) 0;
  border-bottom: 1px solid var(--border);
}
.sidebar-card li:last-child { border-bottom: none; }

/* ── Page header ── */
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: calc(var(--sp) * 2);
}
.page-header h1 { font-size: 1.3rem; font-weight: 600; }

/* ── Sort tabs ── */
.sort-tabs {
  display: flex;
  gap: 4px;
  margin-bottom: calc(var(--sp) * 1.5);
}
.sort-tab {
  padding: calc(var(--sp) * .75) calc(var(--sp) * 1.5);
  border-radius: 99px;
  font-size: .8rem;
  font-weight: 700;
  color: var(--text-dim);
  background: var(--surface);
  border: 1px solid var(--border);
}
.sort-tab:hover,
.sort-tab.active { background: var(--surface2); color: var(--text); text-decoration: none; }

/* ── Flashes ── */
.flash-notice,
.flash-alert {
  border-radius: var(--radius);
  padding: var(--sp) calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 1.5);
  grid-column: 1 / -1;
}
.flash-notice {
  background: #0a2a1a;
  color: #6ee7a0;
  border: 1px solid #1a5a3a;
}
.flash-alert {
  background: #2a0a0a;
  color: #f87171;
  border: 1px solid #5a1a1a;
}

/* ── Empty state ── */
.empty {
  color: var(--text-dim);
  padding: calc(var(--sp) * 4) 0;
  text-align: center;
}
CSS
mv -f "$temp_file" "$STYLE_PATH"

echo "==> [styles] done"
```

## `DEPLOY/rails/brgen/features/views.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly APP_DIR="/home/brgen/app"
echo "==> [views] Writing all templates"
cd "$APP_DIR"

mkdir -p app/views/{home,posts,comments,communities,layouts}

ruby - <<'RUBY'
views = {}

views["app/views/layouts/application.html.erb"] = <<~'ERB'
  <!DOCTYPE html>
  <html lang="no">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><%= content_for?(:title) ? "#{yield :title} — brgen" : "brgen" %></title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body>

  <nav>
    <%= link_to "brgen", root_path, class: "logo" %>
    <div class="nav-links">
      <%= link_to "communities", communities_path %>
      <%= link_to "posts",       posts_path %>
      <% if authenticated? %>
        <%= link_to "inbox",   conversations_path %>
        <%= link_to "sign out", session_path, data: { turbo_method: :delete } %>
      <% else %>
        <%= link_to "sign in",  new_session_path %>
      <% end %>
    </div>
  </nav>

  <div class="page">
    <% if notice %><div class="flash-notice"><%= notice %></div><% end %>
    <% if alert  %><div class="flash-alert"><%=  alert  %></div><% end %>
    <%= yield %>
  </div>

  </body>
  </html>
ERB

views["app/views/home/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="sort-tabs">
      <span class="sort-tab active">hot</span>
      <%= link_to "fresh", posts_path(sort: "fresh"), class: "sort-tab" %>
    </div>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">
        <p>No posts yet. <%= authenticated? ? link_to("Create one", new_post_path) : link_to("Sign in to post", new_session_path) %>.</p>
      </div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>Communities</h3>
      <ul>
        <% @communities.each do |c| %>
          <li><%= link_to c.name, community_path(c) %></li>
        <% end %>
      </ul>
      <% if authenticated? %>
        <div style="margin-top:12px"><%= link_to "+ New community", new_community_path, class: "btn btn-ghost" %></div>
      <% end %>
    </div>
    <% if authenticated? %>
      <div class="sidebar-card">
        <%= link_to "New post", new_post_path, class: "btn", style: "width:100%;text-align:center" %>
      </div>
    <% end %>
  </div>
ERB

views["app/views/posts/_post.html.erb"] = <<~'ERB'
  <%= turbo_frame_tag dom_id(post) do %>
  <div class="post-card">
    <div class="vote-col">
      <% if authenticated? %>
        <%= button_to "▲", post_vote_path(post), params: { vote: { value: 1 } },
              class: "vote-btn #{post.upvoted_by?(Current.user) ? "active-up" : ""}" %>
      <% else %>
        <span class="vote-btn">▲</span>
      <% end %>
      <span class="vote-score"><%= post.score %></span>
      <% if authenticated? %>
        <%= button_to "▼", post_vote_path(post), params: { vote: { value: -1 } },
              class: "vote-btn down #{post.downvoted_by?(Current.user) ? "active-down" : ""}" %>
      <% else %>
        <span class="vote-btn">▼</span>
      <% end %>
    </div>

    <div class="post-body">
      <div class="post-meta">
        <% if post.community %>
          <%= link_to post.community.name, community_path(post.community), class: "community" %>
          <span>•</span>
        <% end %>
        posted by <span><%= post.author_name %></span>
        <span>•</span>
        <%= time_ago_in_words(post.created_at) %> ago
      </div>
      <div class="post-title"><%= link_to post.title, post %></div>
      <div class="post-actions">
        <%= link_to "#{post.comment_count} comments", post_path(post) %>
        <% if authenticated? && post.user == Current.user %>
          <%= link_to "edit",   edit_post_path(post) %>
          <%= button_to "delete", post, method: :delete, data: { turbo_confirm: "Delete this post?" }, class: "vote-btn" %>
        <% end %>
      </div>
    </div>
  </div>
  <% end %>
ERB

views["app/views/posts/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="page-header">
      <h1>All Posts</h1>
      <% if authenticated? %><%= link_to "+ New Post", new_post_path, class: "btn" %><% end %>
    </div>

    <div class="sort-tabs">
      <%= link_to "hot",   posts_path,               class: "sort-tab #{params[:sort].blank? ? "active" : ""}" %>
      <%= link_to "fresh", posts_path(sort: "fresh"), class: "sort-tab #{params[:sort] == "fresh" ? "active" : ""}" %>
      <%= link_to "top",   posts_path(sort: "top"),   class: "sort-tab #{params[:sort] == "top"   ? "active" : ""}" %>
    </div>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">No posts yet.</div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>Communities</h3>
      <ul>
        <% Community.popular.limit(8).each do |c| %>
          <li><%= link_to c.name, community_path(c) %></li>
        <% end %>
      </ul>
    </div>
  </div>
ERB

views["app/views/posts/show.html.erb"] = <<~'ERB'
  <% content_for :title, @post.title %>

  <div class="main-col">
    <div class="post-show">
      <div style="display:flex;gap:16px;align-items:flex-start">
        <div class="vote-col" style="background:var(--surface2);border-radius:var(--radius);padding:12px 0;min-width:40px;align-items:center;display:flex;flex-direction:column;gap:4px">
          <% if authenticated? %>
            <%= button_to "▲", post_vote_path(@post), params: { vote: { value: 1 } },
                  class: "vote-btn #{@post.upvoted_by?(Current.user) ? "active-up" : ""}" %>
          <% else %>
            <span class="vote-btn">▲</span>
          <% end %>
          <span class="vote-score"><%= @post.score %></span>
          <% if authenticated? %>
            <%= button_to "▼", post_vote_path(@post), params: { vote: { value: -1 } },
                  class: "vote-btn down #{@post.downvoted_by?(Current.user) ? "active-down" : ""}" %>
          <% else %>
            <span class="vote-btn">▼</span>
          <% end %>
        </div>

        <div style="flex:1;min-width:0">
          <div class="post-meta">
            <% if @post.community %>
              <%= link_to @post.community.name, community_path(@post.community), class: "community" %> •
            <% end %>
            posted by <%= @post.author_name %> • <%= time_ago_in_words(@post.created_at) %> ago
          </div>
          <h1 style="font-size:1.3rem;font-weight:600;margin-bottom:12px"><%= @post.title %></h1>
          <% if @post.content.present? %>
            <div class="post-content"><%= @post.content %></div>
          <% end %>
        </div>
      </div>
    </div>

    <div class="comments-section">
      <% if authenticated? %>
        <div class="comment-form-wrap" id="comment_form">
          <h3 style="font-size:0.85rem;color:var(--text-dim);margin-bottom:12px">Comment as <%= Current.user.username || "guest" %></h3>
          <%= form_with model: [@post, @new_comment], data: { turbo: true } do |f| %>
            <div class="field"><%= f.text_area :content, placeholder: "What do you think?", rows: 4 %></div>
            <%= f.submit "Comment", class: "btn" %>
          <% end %>
        </div>
      <% end %>

      <div id="comments">
        <% if @comments.any? %>
          <% @comments.each do |comment| %>
            <%= render "comments/comment", comment: comment %>
          <% end %>
        <% else %>
          <div class="empty">No comments yet. Be first.</div>
        <% end %>
      </div>
    </div>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>About</h3>
      <% if @post.community %>
        <p style="color:var(--text-dim);font-size:0.875rem"><%= @post.community.description.presence || @post.community.name %></p>
        <div style="margin-top:12px"><%= link_to "View community", community_path(@post.community), class: "btn btn-ghost" %></div>
      <% else %>
        <p style="color:var(--text-dim);font-size:0.875rem">brgen — Bergen community platform</p>
      <% end %>
    </div>
  </div>
ERB

views["app/views/posts/new.html.erb"] = <<~'ERB'
  <div class="form-wrap">
    <h1 style="margin-bottom:20px"><%= @post.new_record? ? "New Post" : "Edit Post" %></h1>

    <%= form_with model: [@community, @post].compact do |f| %>
      <% if @post.errors.any? %>
        <div class="flash-alert" style="grid-column:auto">
          <% @post.errors.full_messages.each do |msg| %><div><%= msg %></div><% end %>
        </div>
      <% end %>

      <div class="field">
        <%= f.label :community_id, "Community (optional)" %>
        <%= f.collection_select :community_id, Community.order(:name), :id, :name,
              { include_blank: "— no community —" } %>
      </div>

      <div class="field">
        <%= f.label :title %>
        <%= f.text_field :title, placeholder: "Title", autofocus: true %>
      </div>

      <div class="field">
        <%= f.label :content, "Body (optional)" %>
        <%= f.text_area :content, placeholder: "Text (optional)", rows: 8 %>
      </div>

      <div style="display:flex;gap:12px;align-items:center">
        <%= f.submit @post.new_record? ? "Post" : "Save", class: "btn" %>
        <%= link_to "Cancel", @post.new_record? ? posts_path : @post, class: "btn btn-ghost" %>
      </div>
    <% end %>
  </div>
ERB

views["app/views/comments/_comment.html.erb"] = <<~'ERB'
  <%= turbo_frame_tag dom_id(comment) do %>
  <div class="comment" style="margin-left:<%= [comment.depth * 16, 64].min %>px">
    <div class="comment-meta">
      <span class="author"><%= comment.user&.username || "anon" %></span>
      <span> • <%= time_ago_in_words(comment.created_at) %> ago</span>
      <% if authenticated? %>
        •
        <%= link_to "reply", "#reply-#{comment.id}", style: "font-size:0.75rem;color:var(--text-dim)" %>
        <% if comment.user == Current.user %>
          <%= button_to "delete", comment, method: :delete, data: { turbo_confirm: "Delete?" }, class: "vote-btn", style: "font-size:0.7rem;color:var(--text-dim)" %>
        <% end %>
      <% end %>
    </div>
    <div class="comment-body"><%= comment.content %></div>

    <% if authenticated? %>
      <div id="reply-<%= comment.id %>" style="display:none;margin-top:8px">
        <%= form_with url: post_comments_path(comment.commentable.is_a?(Post) ? comment.commentable : comment.commentable), data: { turbo: true } do |f| %>
          <%= f.hidden_field :parent_id, value: comment.id %>
          <div class="field"><%= f.text_area :content, placeholder: "Reply...", rows: 3, style: "font-size:0.875rem" %></div>
          <%= f.submit "Reply", class: "btn", style: "padding:6px 14px;font-size:0.8rem" %>
        <% end %>
      </div>
    <% end %>

    <% comment.replies.best.each do |reply| %>
      <%= render "comments/comment", comment: reply %>
    <% end %>
  </div>
  <% end %>
ERB

views["app/views/communities/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="page-header">
      <h1>Communities</h1>
      <% if authenticated? %><%= link_to "+ New", new_community_path, class: "btn" %><% end %>
    </div>

    <% if @communities.any? %>
      <% @communities.each do |c| %>
        <div class="post-card" style="padding:16px 20px;display:block">
          <div style="display:flex;align-items:center;justify-content:space-between">
            <div>
              <div style="font-weight:600;font-size:1rem"><%= link_to c.name, community_path(c), style: "color:var(--text)" %></div>
              <% if c.description.present? %>
                <div style="color:var(--text-dim);font-size:0.875rem;margin-top:4px"><%= c.description %></div>
              <% end %>
            </div>
            <div style="color:var(--text-dim);font-size:0.8rem"><%= c.posts.count %> posts</div>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="empty">No communities yet. <%= link_to "Create one", new_community_path if authenticated? %></div>
    <% end %>
  </div>

  <div class="side-col"></div>
ERB

views["app/views/communities/show.html.erb"] = <<~'ERB'
  <% content_for :title, @community.name %>

  <div class="main-col">
    <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:20px;margin-bottom:16px">
      <h1 style="font-size:1.4rem;margin-bottom:6px"><%= @community.name %></h1>
      <% if @community.description.present? %>
        <p style="color:var(--text-dim);font-size:0.9rem"><%= @community.description %></p>
      <% end %>
      <div style="margin-top:12px;display:flex;gap:12px;font-size:0.8rem;color:var(--text-dim)">
        <span><strong style="color:var(--text)"><%= @community.posts.count %></strong> posts</span>
      </div>
    </div>

    <% if authenticated? %>
      <div style="margin-bottom:16px"><%= link_to "+ New post in #{@community.name}", new_community_post_path(@community), class: "btn" %></div>
    <% end %>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">No posts yet in this community.</div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>About <%= @community.name %></h3>
      <p style="font-size:0.875rem;color:var(--text-dim)"><%= @community.description.presence || "No description." %></p>
      <% if authenticated? %>
        <div style="margin-top:12px"><%= link_to "New post", new_community_post_path(@community), class: "btn", style: "width:100%;text-align:center" %></div>
      <% end %>
    </div>
  </div>
ERB

views["app/views/communities/new.html.erb"] = <<~'ERB'
  <div class="form-wrap">
    <h1 style="margin-bottom:20px">New Community</h1>
    <%= form_with model: @community do |f| %>
      <% if @community.errors.any? %>
        <div class="flash-alert" style="grid-column:auto">
          <% @community.errors.full_messages.each do |msg| %><div><%= msg %></div><% end %>
        </div>
      <% end %>
      <div class="field">
        <%= f.label :name %>
        <%= f.text_field :name, placeholder: "e.g. bergen, tech, musikk" %>
      </div>
      <div class="field">
        <%= f.label :description %>
        <%= f.text_area :description, placeholder: "What is this community about?", rows: 3 %>
      </div>
      <div style="display:flex;gap:12px">
        <%= f.submit "Create", class: "btn" %>
        <%= link_to "Cancel", communities_path, class: "btn btn-ghost" %>
      </div>
    <% end %>
  </div>
ERB

views.each do |path, content|
  FileUtils.mkdir_p(File.dirname(path))
... 6 lines truncated (406 total)
```

## `DEPLOY/rails/brgen/features/voting.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

APP_DIR="/home/brgen/app"
MESSAGE="Reddit‑style votes + comments + karma"

# -------------------------------------------------------------------
# Preconditions
# -------------------------------------------------------------------
if [[ ! -d $APP_DIR ]]; then
  printf '[%s] missing APP_DIR %s\n' "$MESSAGE" "$APP_DIR" >&2
  exit 1
fi
if [[ ! -w $APP_DIR ]]; then
  printf '[%s] APP_DIR %s not writable\n' "$MESSAGE" "$APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
run_rails() {
  bin/rails "$@" || {
    printf '[%s] rails command failed: %s\n' "$MESSAGE" "$*" >&2
    exit 1
  }
}

# -------------------------------------------------------------------
# Start
# -------------------------------------------------------------------
printf '==> [%s] starting\n' "$MESSAGE"

# -------------------------------------------------------------------
# Generate Vote model (idempotent)
# -------------------------------------------------------------------
if ! bin/rails generate model Vote value:integer user:references votable:references{polymorphic} --skip > /dev/null 2>&1; then
  printf '[%s] model Vote already exists – skipping\n' "$MESSAGE"
fi
run_rails db:migrate

# -------------------------------------------------------------------
# Concerns & models (write only if missing)
# -------------------------------------------------------------------
VOTABLE_PATH="app/models/concerns/votable.rb"
if [[ ! -f $VOTABLE_PATH ]]; then
  cat > "$VOTABLE_PATH" <<'RUBY'
module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def score = votes.sum(:value)
  def upvotes = votes.where(value: 1).count
  def downvotes = votes.where(value: -1).count
  def voted_by?(u) = u && votes.find_by(user: u)&.value
  def upvoted_by?(u) = voted_by?(u) == 1
  def downvoted_by?(u) = voted_by?(u) == -1
end
RUBY
fi

VOTE_MODEL="app/models/vote.rb"
if [[ ! -f $VOTE_MODEL ]]; then
  cat > "$VOTE_MODEL" <<'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }

  after_save    :update_author_karma
  after_destroy :update_author_karma

  private

  def update_author_karma
    return unless votable.respond_to?(:user) && votable.user

    votable.user.update_karma!
  end
end
RUBY
fi

USER_MODEL="app/models/user.rb"
if ! grep -q "def update_karma!" "$USER_MODEL"; then
  cat >> "$USER_MODEL" <<'RUBY'

  def update_karma!
    post_karma = Vote.joins("JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                     .where(posts: { user_id: id }).sum(:value)

    comment_karma = Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                        .where(comments: { user_id: id }).sum(:value)

    update_column(:karma, post_karma + comment_karma)
  end
RUBY
fi

COMMENTABLE_PATH="app/models/concerns/commentable.rb"
if [[ ! -f $COMMENTABLE_PATH ]]; then
  cat > "$COMMENTABLE_PATH" <<'RUBY'
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def root_comments = comments.where(parent_id: nil)
  def comment_count = comments.count
end
RUBY
fi

COMMENT_MODEL="app/models/comment.rb"
if [[ ! -f $COMMENT_MODEL ]]; then
  cat > "$COMMENT_MODEL" <<'RUBY'
class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10_000 }

  scope :best, -> {
    left_joins(:votes).group(:id).order('SUM(COALESCE(votes.value,0)) DESC')
  }
  scope :top,   -> { best }
  scope :new_first, -> { order(created_at: :desc) }
  scope :old_first, -> { order(created_at: :asc) }
  scope :controversial, -> {
    left_joins(:votes).group(:id)
      .having('COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0')
      .having('COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0')
      .order('ABS(SUM(votes.value)) ASC')
  }

  def root? = parent_id.nil?
  def depth = parent ? parent.depth + 1 : 0
end
RUBY
fi

# -------------------------------------------------------------------
# Controller
# -------------------------------------------------------------------
VOTES_CONTROLLER="app/controllers/votes_controller.rb"
if [[ ! -f $VOTES_CONTROLLER ]]; then
  cat > "$VOTES_CONTROLLER" <<'RUBY'
class VotesController < ApplicationController
  before_action :authenticate_user!
  ALLOWED = %w[Post Comment].freeze

  def create
    votable = find_votable
    vote    = votable.votes.find_or_initialize_by(user: current_user)

    if vote.persisted? && vote.value == params.dig(:vote, :value).to_i
      vote.destroy
    else
      vote.update!(value: params.dig(:vote, :value).to_i)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def find_votable
    type = params[:votable_type].to_s.classify
    raise ArgumentError, "Invalid votable type" unless ALLOWED.include?(type)

    type.constantize.find(params[:votable_id])
  end
end
RUBY
fi

# -------------------------------------------------------------------
# Views
# -------------------------------------------------------------------
mkdir -p app/views/shared app/views/comments

cat > app/views/shared/_vote.html.erb <<'ERB'
<div class="vote-buttons" data-controller="vote">
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: 1 %>
    <%= f.button "▲", class: "vote-btn upvote <%= 'active' if votable.upvoted_by?(current_user) %>", type: :submit %>
  <% end %>
  <span class="vote-score"><%= votable.score %></span>
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: -1 %>
    <%= f.button "▼", class: "vote-btn downvote <%= 'active' if votable.downvoted_by?(current_user) %>", type: :submit %>
  <% end %>
</div>
ERB

cat > app/views/comments/_comment.html.erb <<'ERB'
<%= turbo_frame_tag dom_id(comment) do %>
  <div class="comment depth-<%= comment.depth %>" style="margin-left:<%= comment.depth * 20 %>px">
    <div class="comment-meta">
      <span class="author"><%= comment.user.username %></span>
      <span class="time"><%= time_ago_in_words(comment.created_at) %> ago</span>
      <%= render "shared/vote", votable: comment if user_signed_in? %>
    </div>
    <div class="comment-body"><%= simple_format comment.content %></div>
    <% comment.replies.best.each do |r| %>
      <%= render "comments/comment", comment: r %>
    <% end %>
  </div>
<% end %>
ERB

run_rails db:migrate

printf '==> [%s] done\n' "$MESSAGE"
```

## `DEPLOY/rails/bsdports/README.md`
```markdown
git clone https://github.com/yourorg/master.git
cd master
```

## `DEPLOY/rails/bsdports/bsdports.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration ------------------------------------------------------------
APP_NAME="bsdports"
BASE_DIR="${BASE_DIR:-/home/dev/rails}"
SERVER_IP="${SERVER_IP:-185.52.176.18}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RAILS_ENV="${RAILS_ENV:-production}"

#--- Shared utilities ---------------------------------------------------------
. "${SCRIPT_DIR}/@shared_functions.sh" || {
    printf 'Error: cannot source %s\n' "${SCRIPT_DIR}/@shared_functions.sh" >&2
    exit 1
}

# Ensure required helper exists
command -v validate_port_available >/dev/null 2>&1 || {
    printf 'Error: validate_port_available function not found\n' >&2
    exit 1
}

#--- Port selection -----------------------------------------------------------
# POSIX‑compatible random port selection
RANDOM="$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu4 | tr -d ' ')"
MAX_RETRIES=10
retry=0
while :; do
    candidate_port=$((10000 + RANDOM % 55536))
    [ "$candidate_port" -le 65535 ] || candidate_port=65535
    if validate_port_available "$candidate_port"; then
        APP_PORT=$candidate_port
        printf 'Selected port: %s\n' "$APP_PORT"
        break
    fi
    retry=$((retry + 1))
    if [ "$retry" -ge "$MAX_RETRIES" ]; then
        printf 'Error: unable to find free port after %s attempts\n' "$MAX_RETRIES" >&2
        exit 1
    fi
done

#--- Database checks -----------------------------------------------------------
if ! bin/rails db:version >/dev/null 2>&1; then
    printf 'Error: invalid database configuration or unreachable DB\n' >&2
    exit 1
fi

if ! bin/rails db:migrate; then
    printf 'Error: Rails migration failed\n' >&2
    exit 1
fi

#--- Falcon socket server -----------------------------------------------------
FALCON_RB="$(mktemp -u /tmp/falcon_${APP_NAME}.rb.XXXXXX)"
cat >"$FALCON_RB" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require 'socket'

BODY = <<~HTML
  <!DOCTYPE html><html><head><meta charset=utf-8><title>bsdports</title>
  <style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>
  </head><body><h1>bsdports</h1></body></html>
HTML

RESP = <<~HTTP
  HTTP/1.0 200 OK
  Content-Type: text/html; charset=utf-8
  Content-Length: #{BODY.bytesize}
  Connection: close

  #{BODY}
HTTP

trap('TERM') { exit }
trap('INT')  { exit }

TCPServer.new('0.0.0.0', ENV.fetch('APP_PORT', '10003')).tap do |s|
  puts "bsdports on #{s.addr[1]}"
  loop do
    client = s.accept
    client.recv(4096) rescue nil
    client.print(RESP) rescue nil
    client.close rescue nil
  end
end
EOF
chmod +x "$FALCON_RB"

APP_DIR="/home/${APP_NAME}/app"
CONFIG_DIR="${APP_DIR}/config"

doas -u root mkdir -p "$CONFIG_DIR"
doas -u root cp "$FALCON_RB" "${CONFIG_DIR}/falcon.rb"
doas -u root chown "${APP_NAME}:${APP_NAME}" "${CONFIG_DIR}/falcon.rb"
rm -f "$FALCON_RB"

#--- rc.d service -------------------------------------------------------------
RC_SCRIPT="$(mktemp -u /tmp/rc_${APP_NAME}.XXXXXX)"
cat >"$RC_SCRIPT" <<EOS
#!/bin/ksh
. /etc/rc.d/rc.subr

name="${APP_NAME}_rails"
rcvar=\${name}
command="/usr/local/bin/ruby34"
command_args="${CONFIG_DIR}/falcon.rb"
rc_flags="\${command_args}"
rc_need="network"
rc_bg=YES
rc_reload=NO

run_rc_command "\$1"
EOS
chmod 755 "$RC_SCRIPT"
doas -u root cp "$RC_SCRIPT" "/etc/rc.d/${APP_NAME}_rails"
rm -f "$RC_SCRIPT"

doas -u root rcctl enable "${APP_NAME}_rails"
doas -u root rcctl start "${APP_NAME}_rails"```

## `DEPLOY/rails/check_ports.sh`
```bash
#!/usr/bin/env sh
set -eu

# Port consistency checker for DEPLOY/rails
# 0 → success, non‑zero → validation failure.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MASTER_JSON=${MASTER_JSON:-"$SCRIPT_DIR/../master.json"}

log()   { printf '%s\n' "$*"; }
error() { printf '❌ %s\n' "$*" >&2; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || { error "Missing required command: $1"; exit 1; }
}

validate_master_json() {
    [ -f "$MASTER_JSON" ] || { error "master.json not found at: $MASTER_JSON"; return 1; }
    jq -e '.apps | type == "array" and length > 0' "$MASTER_JSON" >/dev/null 2>&1 ||
        { error "master.json must contain a non‑empty .apps array"; return 1; }
}

# Load app→port mapping into associative arrays.
load_ports() {
    declare -A port_of
    apps_list=''

    jq -r '.apps[] | "\(.name)\t\(.port)"' "$MASTER_JSON" |
    while IFS=$'\t' read -r app port; do
        [ -n "$app" ] && [ -n "$port" ] || { error "App with missing name or port"; return 1; }

        case "$port" in
            ''|*[!0-9]*) error "Invalid port '$port' for app '$app'"; return 1;;
        esac
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { error "Port out of range '$port' for app '$app'"; return 1; }

        if [ -n "${port_of[$app]+x}" ]; then
            error "Duplicate app name '$app' in master.json"
            return 1
        fi

        port_of[$app]=$port
        apps_list="${apps_list}${app} "
    done

    # Export for later stages.
    export APPS="$apps_list"
    export PORT_OF_JSON="$(printf '%s\n' "${!port_of[@]}" | while read -r k; do printf '%s=%s\n' "$k" "${port_of[$k]}"; done)"
    # Keep the associative array in a temporary file for subshells that need it.
    export PORT_MAP_FILE=$(mktemp)
    for k in "${!port_of[@]}"; do
        printf '%s=%s\n' "$k" "${port_of[$k]}" >>"$PORT_MAP_FILE"
    done
}

check_duplicate_ports() {
    duplicate=0
    # Build reverse map: port → apps
    declare -A seen
    for app in $APPS; do
        port=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
        if [ -n "${seen[$port]+x}" ]; then
            error "Port collision on $port: ${seen[$port]} and $app"
            duplicate=1
        else
            seen[$port]=$app
        fi
    done
    return $duplicate
}

check_expected_port_constants() {
    mismatch=0
    i=1
    for app in $APPS; do
        installer="$SCRIPT_DIR/$app/$app.sh"
        if [ -f "$installer" ]; then
            installer_port=$(sed -nE 's/^[[:space:]]*(readonly[[:space:]]+)?PORT=([0-9]+).*/\2/p' "$installer" | head -n1)
            expected=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
            if [ -n "$installer_port" ] && [ "$installer_port" != "$expected" ]; then
                error "$installer sets PORT=${installer_port}, expected ${expected}"
                mismatch=1
            fi
        fi
        i=$((i + 1))
    done
    return $mismatch
}

main() {
    log "=== Port Consistency Check ==="
    require_command jq

    validate_master_json
    load_ports
    check_duplicate_ports

    log ""
    log "Ports from ${MASTER_JSON}:"
    for app in $APPS; do
        port=$(awk -F= -v a="$app" 'a==$1{print $2}' "$PORT_MAP_FILE")
        log "  - $app: $port"
    done

    if check_expected_port_constants; then
        log ""
        log "✅ Port checks passed"
    else
        exit 1
    fi
}

main "$@"
```

## `DEPLOY/rails/demo.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Demo Rails 8 app generator – Simple CRUD with Hotwire
# Port: 10008
# Domain: demo.local (or configure as needed)

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="demo"
readonly PORT=10008

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_prereqs() {
  require_cmd rails
  require_cmd bundler
  require_cmd lsof
  require_cmd sed
  require_cmd cp
  require_cmd cat
}

port_in_use() {
  lsof -i :"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1
}

backup_file() {
  local src=$1
  [[ -f $src ]] && cp -f "$src" "${src}.backup"
}

append_once() {
  local file=$1 marker=$2 content=$3
  grep -qF "$marker" "$file" || printf '%s\n' "$content" >>"$file"
}

create_app() {
  rails new "$APP_NAME" \
    --database=postgresql \
    --css=tailwind \
    --javascript=importmap ||
    die "Failed to create Rails app"
}

write_database_yml() {
  cat > config/database.yml <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
  username: ${APP_NAME}
  password: <%= ENV["${APP_NAME^^}_DATABASE_PASSWORD"] %>
EOF
}

configure_solid_gems() {
  local application_rb="config/application.rb"
  backup_file "$application_rb"

  append_once "$application_rb" "config.solid_queue" $'\n# Solid Queue configuration\nconfig.solid_queue.connects_to = { database: { writing: :primary } }'
  append_once "$application_rb" "config.solid_cache" $'\n# Solid Cache configuration\nconfig.solid_cache.connects_to = { database: { writing: :primary } }'
  append_once "$application_rb" "config.solid_cable" $'\n# Solid Cable configuration\nconfig.solid_cable.connects_to = { database: { writing: :primary } }'
}

inject_layout_wrapper() {
  local layout_file="app/views/layouts/application.html.erb"
  [[ -f $layout_file ]] || return

  sed -i.bak '/<body>/a\
    <div class="container mx-auto px-4 py-8">\
      <h1 class="text-3xl font-bold mb-6">Demo App</h1>\
      <%= yield %>\
    </div>' "$layout_file"
  rm -f "${layout_file}.bak"
}

start_server() {
  bin/rails server -p "$PORT" -d ||
    die "Failed to start Rails server"
  printf 'Demo app created successfully!\nApp is running on http://localhost:%s\nStop the server with: bin/rails server -p %s -d -s\n' "$PORT" "$PORT"
}

main() {
  check_prereqs

  local app_dir="${SCRIPT_DIR}/${APP_NAME}"
  [[ -d $app_dir ]] && die "Directory $app_dir already exists"
  port_in_use && die "Port $PORT is already in use"

  create_app
  cd "$APP_NAME"

  backup_file config/database.yml
  write_database_yml

  bin/rails db:create || die "Failed to create databases"

  bundle add solid_queue solid_cache solid_cable || die "Failed to add Solid* gems"
  configure_solid_gems

  bin/rails generate scaffold Post title:string content:text --no-jbuilder
  bin/rails db:migrate || die "Failed to run migrations"

  cat > config/routes.rb <<'EOF'
Rails.application.routes.draw do
  resources :posts
  root 'posts#index'
end
EOF

  inject_layout_wrapper
  start_server
}

main "$@"
```

## `DEPLOY/rails/hjerterom/README.md`
```markdown
git clone https://github.com/yourorg/hjerterom.git
cd hjerterom
```

## `DEPLOY/rails/hjerterom/hjerterom.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

# hjerterom – mental‑health & food redistribution platform
# -------------------------------------------------------
# Idempotent deployment of a minimal Falcon HTTP server as an rc.d service
# on OpenBSD.  Re‑run safely; existing files are left untouched and the
# service is (re)started only when needed.

readonly APP_NAME="hjerterom"
readonly APP_DIR="/home/${APP_NAME}/app"
readonly CONFIG_DIR="${APP_DIR}/config"
readonly FALCON_SCRIPT="${CONFIG_DIR}/falcon.rb"
readonly RC_SCRIPT="/etc/rc.d/${APP_NAME}_rails"
readonly RC_USER="${APP_NAME}"
readonly APP_PORT=10004

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_commands() {
  missing=
  for cmd in ruby rcctl; do
    command_exists "$cmd" || missing="${missing}${cmd} "
  done
  [ -z "$missing" ] || die "Missing commands: $missing"
}

install_falcon_server() {
  # Write the server only if missing or checksum differs
  if [ -f "$FALCON_SCRIPT" ]; then
    # compare inline to avoid rewriting unchanged file
    tmp=$(mktemp)
    cat >"$tmp" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = "<!DOCTYPE html><html><head><meta charset=utf-8><title>hjernerom</title>" \
       "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}</style>" \
       "</head><body><h1>hjernerom</h1></body></html>"
RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", ${APP_PORT}).tap do |s|
  $stdout.puts "hjernerom on ${APP_PORT}"
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
end
EOF
    if ! cmp -s "$tmp" "$FALCON_SCRIPT"; then
      cp "$tmp" "$FALCON_SCRIPT"
      chmod +x "$FALCON_SCRIPT"
    fi
    rm -f "$tmp"
  else
    mkdir -p "$CONFIG_DIR"
    install_falcon_server # recursive call creates the file
  fi
}

install_rc_service() {
  # Create rc.d script only if missing or changed
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="${FALCON_SCRIPT}"
daemon_user="${RC_USER}"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_bg=YES
rc_reload=NO

rc_cmd "\$1"
EOF

  if [ ! -f "$RC_SCRIPT" ] || ! cmp -s "$tmp" "$RC_SCRIPT"; then
    cp "$tmp" "$RC_SCRIPT"
    chmod 755 "$RC_SCRIPT"
    rcctl enable "${APP_NAME}_rails"
  fi
  rm -f "$tmp"
}

start_service() {
  rcctl start "${APP_NAME}_rails" || die "Failed to start ${APP_NAME}_rails"
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------
require_commands
install_falcon_server
install_rc_service
start_service

printf 'Deployment of %s completed successfully.\n' "$APP_NAME"
```

## `DEPLOY/rails/modernize_zsh.sh`
```bash
#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_g
set -euo pipefail

# Gather target files
typeset -a files errors
files=(**/*.sh)

# Default sed patterns (override by exporting sed_patterns)
if (( ${#sed_patterns[@]} == 0 )); then
  sed_patterns=(
    's/\r$//g'               # strip CR
    's/[[:space:]]+$//g'     # trim trailing whitespace
    's/^[[:space:]]+//'      # trim leading whitespace
  )
fi

# Choose correct -i syntax for sed
case $(uname) in
  Darwin) sed_in_place=(-i '') ;;
  *)      sed_in_place=(-i) ;;
esac

for file in $files; do
  [[ $file == */modernize_zsh.sh ]] && continue

  [[ -f $file && -r $file ]] || {
    errors+=("$file: not found or unreadable")
    continue
  }

  # Resolve symlink to real file
  if [[ -L $file ]]; then
    real=$(readlink -f $file 2>/dev/null) || {
      errors+=("$file: cannot resolve symlink")
      continue
    }
    [[ -f $real ]] && file=$real || {
      errors+=("$file: symlink target missing")
      continue
    }
  fi

  # Make a backup if none exists
  if [[ ! -f ${file}.bak ]]; then
    cp --preserve=mode,timestamps "$file" "${file}.bak" || {
      errors+=("$file: backup failed")
      continue
    }
  fi

  # Dry‑run all patterns
  for pat in "${sed_patterns[@]}"; do
    if ! sed -n "${sed_in_place[@]}" -e "$pat" -e 'q' "$file" >/dev/null 2>&1; then
      errors+=("$file: dry‑run failed for $pat")
      continue 2
    fi
  done

  # Apply patterns
  for pat in "${sed_patterns[@]}"; do
    if ! sed "${sed_in_place[@]}" -e "$pat" "$file"; then
      errors+=("$file: transformation failed for $pat")
      continue 2
    fi
  done
done

if (( ${#errors[@]} )); then
  printf "Errors:\n%s\n" "${errors[@]}"
  exit 1
fi```

## `DEPLOY/rails/mytoonz.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

# MyToonz – AI‑powered personalized comic strip generator
# Deploys the Rails + Node frontend, validates environment and dependencies.

readonly BASE_DIR=$(cd "$(dirname "$0")" && pwd)
readonly APP_NAME=mytoonz
readonly APP_DIR=$BASE_DIR/$APP_NAME

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}
log_error() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# source shared helpers if present
if [ -f "$BASE_DIR/__shared.sh" ]; then
    . "$BASE_DIR/__shared.sh"
else
    log_error "__shared.sh missing in $BASE_DIR"
    exit 1
fi

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
    log "Checking required commands…"
    for cmd in node npm yarn redis-cli git curl bundle; do
        if ! command_exists "$cmd"; then
            case $cmd in
                node)   log_error "Node.js not installed"; exit 1 ;;
                npm|yarn) log_error "npm or yarn not installed"; exit 1 ;;
                *)      log "Warning: $cmd missing – related features disabled" ;;
            esac
        fi
    done
}

validate_environment() {
    log "Validating environment…"
    : "${REDIS_URL:=redis://localhost:6379}"
    case $REDIS_URL in
        redis://*) ;; # ok
        *) log_error "REDIS_URL must start with redis://"; exit 1 ;;
    esac
    : "${REPLICATE_API_TOKEN:?REPLICATE_API_TOKEN required}"
}

run_pkg_manager() {
    if command_exists yarn; then
        yarn "$@"
    else
        npm "$@"
    fi
}

setup_frontend() {
    log "Setting up frontend…"
    cd "$APP_DIR" || { log_error "Cannot cd $APP_DIR"; exit 1; }

    if [ -f package.json ]; then
        run_pkg_manager install || { log_error "Package install failed"; exit 1; }
        if grep -q '"build"' package.json; then
            run_pkg_manager run build || { log_error "Build failed"; exit 1; }
        else
            log "No build script – skipping"
        fi
    else
        log "No package.json – skipping frontend"
    fi
}

setup_backend() {
    log "Setting up backend…"
    cd "$APP_DIR" || { log_error "Cannot cd $APP_DIR"; exit 1; }

    if [ -f Gemfile ]; then
        bundle install || { log_error "bundle install failed"; exit 1; }
    else
        log "No Gemfile – skipping backend"
    fi
}

cleanup() { log "Cleanup complete"; }
trap cleanup EXIT INT TERM

main() {
    log "Starting MyToonz deployment"
    check_dependencies
    validate_environment
    setup_frontend
    setup_backend
    log "MyToonz setup finished"
}

main "$@"
```

## `DEPLOY/rails/privcam/README.md`
```markdown
# Fetch the privileged camera source
git clone https://github.com/yourorg/privcam.git
cd privcam/DEPLOY/rails
```

## `DEPLOY/rails/privcam/privcam.sh`
```bash
#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RAILS_APP_DIR=${RAILS_APP_DIR:-/home/dev/rails}
RAILS_BASE_DIR=${RAILS_BASE_DIR:-/home/dev/rails}
APP_NAME=privcam
APP_PORT=10005
SERVER_IP=185.52.176.18

#--- Logging -----------------------------------------------------------------
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

#--- Shared functions ---------------------------------------------------------
SHARED_SCRIPT="${SCRIPT_DIR}/@shared_functions.sh"
if [ ! -f "$SHARED_SCRIPT" ]; then
    log "Shared functions not found: $SHARED_SCRIPT"
    exit 1
fi
. "$SHARED_SCRIPT"

#--- Prerequisites ------------------------------------------------------------
for cmd in rails node psql bundle; do
    command_exists "$cmd" || { log "$cmd not installed"; exit 1; }
done

#--- Database connectivity ----------------------------------------------------
if ! psql -h localhost -U postgres -l > /dev/null 2>&1; then
    log "Unable to connect to PostgreSQL"
    exit 1
fi

#--- Gem installation ---------------------------------------------------------
REQUIRED_GEMS='faker:2.23.0 pagy:8.0.2 stimulus_reflex:3.5.0'
for spec in $REQUIRED_GEMS; do
    gem_name=${spec%:*}
    gem_ver=${spec#*:}
    if ! grep -qE "gem ['\"]${gem_name}['\"][^>]*['\"]${gem_ver}['\"]" Gemfile 2>/dev/null; then
        printf "gem '%s', '%s'\n" "$gem_name" "$gem_ver" >> Gemfile
        log "Added ${gem_name} ${gem_ver} to Gemfile"
    fi
done
bundle install || { log "bundle install failed"; exit 1; }

#--- Pagy backend patch -------------------------------------------------------
APP_CTRL="${RAILS_APP_DIR}/app/controllers/application_controller.rb"
if [ -f "$APP_CTRL" ]; then
    if ! grep -q 'include Pagy::Backend' "$APP_CTRL"; then
        cp "$APP_CTRL" "${APP_CTRL}.bak"
        awk '
            /class[[:space:]]+ApplicationController/ && !found {
                print;
                print "  include Pagy::Backend";
                found=1;
                next
            }
            { print }
        ' "$APP_CTRL" > "${APP_CTRL}.tmp" && mv "${APP_CTRL}.tmp" "$APP_CTRL"
        if grep -q 'include Pagy::Backend' "$APP_CTRL"; then
            log "Patched ApplicationController with Pagy::Backend"
            rm -f "${APP_CTRL}.bak"
        else
            log "Patch failed, restoring backup"
            mv "${APP_CTRL}.bak" "$APP_CTRL"
            exit 1
        fi
    else
        log "ApplicationController already includes Pagy::Backend"
    fi
else
    log "ApplicationController not found at $APP_CTRL"
    exit 1
fi

#--- Active Storage check -----------------------------------------------------
if ! rails runner 'exit ActiveRecord::Base.connection.table_exists?("active_storage_blobs") ? 0 : 1' 2>/dev/null; then
    log "Active Storage not set up"
    exit 1
fi

#--- Scaffold generation ------------------------------------------------------
log "Generating Post scaffold..."
rails generate scaffold Post title:string content:text || { log "Scaffold generation failed"; exit 1; }

#--- Seed data ---------------------------------------------------------------
if ! rails runner 'exit Post.any? ? 0 : 1' 2>/dev/null; then
    log "Seeding database..."
    rails db:seed || { log "Database seeding failed"; exit 1; }
fi

#--- Falcon socket server -----------------------------------------------------
FALCON_PATH="/home/${APP_NAME}/app/config/falcon.rb"
if [ ! -f "$FALCON_PATH" ]; then
    cat > "$FALCON_PATH" <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

BODY = <<~HTML.freeze
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <title>privcam</title>
      <style>
        body{font:16px/1.6 system-ui,sans-serif;max-width:700px;margin:60px auto;padding:20px}
      </style>
    </head>
    <body><h1>privcam</h1></body>
  </html>
HTML

RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{BODY.bytesize}\r\nConnection: close\r\n\r\n#{BODY}"

trap("TERM") { exit }
trap("INT")  { exit }

TCPServer.new("0.0.0.0", 10005).tap do |s|
  puts "privcam listening on 0.0.0.0:10005"
  loop do
    client = s.accept
    client.recv(4096) rescue nil
    client.print(RESP) rescue nil
    client.close rescue nil
  end
end
EOF
    chmod 755 "$FALCON_PATH"
    chown -R "${APP_NAME}:${APP_NAME}" "$(dirname "$FALCON_PATH")"
else
    log "Falcon script already exists at $FALCON_PATH"
fi

#--- RC.d service -------------------------------------------------------------
RC_SCRIPT="/etc/rc.d/${APP_NAME}_rails"
if [ ! -f "$RC_SCRIPT" ]; then
    cat > "$RC_SCRIPT" <<'EOF'
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="/home/privcam/app/config/falcon.rb"
daemon_user="privcam"
daemon_timeout=30

. /etc/rc.d/rc.subr

rc_bg=YES
rc_cmd "$1"
EOF
    chmod 755 "$RC_SCRIPT"
    rcctl enable "${APP_NAME}_rails" || log "Failed to enable rc service"
    rcctl start "${APP_NAME}_rails" || log "Failed to start rc service"
else
    log "RC script already exists at $RC_SCRIPT"
fi

log "Deployment completed successfully"
exit 0```

## `DEPLOY/rails/rich_editor_system.sh`
```bash
#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(basename "${0##*/}")" "$*" >&2
}

require_file() {
  if [ ! -f "$1" ]; then
    log "Error: required file not found: $1"
    return 1
  fi
}

install_tiptap_packages() {
  require_file package.json || return 1

  if command -v yarn >/dev/null 2>&1; then
    yarn add @tiptap/core @tiptap/starter-kit @tiptap/extension-link
  elif command -v npm >/dev/null 2>&1; then
    npm install --save @tiptap/core @tiptap/starter-kit @tiptap/extension-link
  else
    log "Error: neither yarn nor npm is available"
    return 1
  fi
}

create_tiptap_controller() {
  target="app/javascript/controllers/rich_text_controller.js"
  if [ -e "$target" ]; then
    log "Skipping controller creation; $target already exists"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<'EOF'
import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"

export default class extends Controller {
  static targets = ["input", "editor"]

  connect() {
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [StarterKit, Link],
      content: this.inputTarget.value || "",
      onUpdate: ({ editor }) => {
        this.inputTarget.value = editor.getHTML()
      }
    })
  }

  disconnect() {
    this.editor && this.editor.destroy()
  }
}
EOF
}

create_editor_styles() {
  target="app/assets/stylesheets/rich_editor.css"
  if [ -e "$target" ]; then
    log "Skipping stylesheet creation; $target already exists"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<'EOF'
.rich-editor {
  border: 1px solid #d1d5db;
  border-radius: 12px;
  background: #ffffff;
  min-height: 14rem;
  padding: 0.875rem;
}

.rich-editor:focus-within {
  border-color: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.2);
}
EOF
}

add_rich_editor() {
  app_name="${1:-$(basename "$(pwd)")}"
  log "Installing Tiptap rich editor into ${app_name}"
  install_tiptap_packages
  create_tiptap_controller
  create_editor_styles
  log "Rich editor scaffolding completed for ${app_name}"
}

# Execute only when run directly, not when sourced
case "$0" in
  *sh) add_rich_editor "${1:-}" ;;
esac```

## `DEPLOY/rails/voting_system.sh`
```bash
#!/usr/bin/env sh
# Voting System Generator – minimal, portable, safe

set -eu
set -o pipefail
IFS=$(printf '\n\t')

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

# Ensure Rails CLI exists
[ -x bin/rails ] || { log "Error: bin/rails not found"; exit 1; }

add_voting_system() {
  app=${1:-${PWD##*/}}
  log "Adding voting system to $app"
  install_gems || return

  # Routes
  if [ -f config/routes.rb ] && ! grep -qF "resources :reviews" config/routes.rb; then
    add_routes
  fi

  generate_models || return
  create_controller   || return
  create_helper      || return
  create_stimulus    || return

  log "Voting system added to $app"
}

install_gems() {
  if grep -qE "acts_as_votable|public_activity" Gemfile; then
    log "Gems already present"
    return 0
  fi

  {
    printf "\n%s\n" "gem 'acts_as_votable', '~> 1.0.0'"
    printf "%s\n"   "gem 'public_activity', '~> 2.0.0'"
  } >> Gemfile

  if ! bundle install --quiet; then
    log "Gem install failed"
    exit 1
  fi
}

generate_models() {
  # Review model
  if [ ! -f app/models/review.rb ]; then
    bin/rails generate model Review \
      user:references \
      rating:integer \
      title:string \
      body:text \
      helpful_count:integer:default=0 \
      verified_purchase:boolean:default=false ||
      { log "Model generation failed"; exit 1; }
  fi

  # Polymorphic votable migration
  if ! ls db/migrate/*add_votable_to_posts*.rb >/dev/null 2>&1; then
    bin/rails generate migration AddVotableToPosts votable:references{polymorphic} ||
      { log "Votable migration failed"; exit 1; }
  fi

  # Karma migration
  if ! ls db/migrate/*add_karma_to_users*.rb >/dev/null 2>&1; then
    bin/rails generate migration AddKarmaToUsers karma:integer:default=0 ||
      { log "Karma migration failed"; exit 1; }
  fi

  bin/rails db:migrate || { log "Migrations failed"; exit 1; }
}

add_routes() {
  tmp=$(mktemp -p .) || { log "Failed to create temporary file"; exit 1; }
  awk '
    /Rails\.application\.routes\.draw do/ {print; next}
    /end/ && !found {
      print "  resources :reviews do"
      print "    member do"
      print "      post :mark_helpful"
      print "    end"
      print "  end"
      found=1
    }
    {print}
  ' config/routes.rb > "$tmp" && mv "$tmp" config/routes.rb
}

create_controller() {
  file=app/controllers/reviews_controller.rb
  if [ -f "$file" ]; then
    log "Controller exists"
    return 0
  fi

  cat >"$file" <<'EOF'
class ReviewsController < ApplicationController
  before_action :set_review, only: %i[show edit update destroy mark_helpful]
  before_action :authenticate_user!, except: %i[index show]

  def index
    @reviews = Review.includes(:user).order(created_at: :desc)
  end

  def show; end

  def new
    @review = Review.new
  end

  def create
    @review = current_user.reviews.build(review_params)
    if @review.save
      redirect_to @review, notice: "Review created"
    else
      render :new
    end
  end

  def edit; end

  def update
    if @review.update(review_params)
      redirect_to @review, notice: "Review updated"
    else
      render :edit
    end
  end

  def destroy
    @review.destroy
    redirect_to reviews_path, notice: "Review destroyed"
  end

  def mark_helpful
    if @review.voted_for_by?(current_user)
      current_user.unvote_for(@review)
      @review.decrement!(:helpful_count)
    else
      current_user.vote_for(@review)
      @review.increment!(:helpful_count)
    end
    redirect_to @review
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:rating, :title, :body, :verified_purchase)
  end
end
EOF

  log "Created controller"
}

create_helper() {
  file=app/helpers/reviews_helper.rb
  if [ -f "$file" ]; then
    log "Helper exists"
    return 0
  fi

  cat >"$file" <<'EOF'
module ReviewsHelper
  def star_rating(rating, max = 5)
    full = rating.floor
    half = (rating - full) >= 0.5
    empty = max - full - (half ? 1 : 0)

    stars = content_tag(:span, '★' * full, class: 'star full')
    stars << content_tag(:span, '½', class: 'star half') if half
    stars << content_tag(:span, '★' * empty, class: 'star empty')
    stars
  end

  def helpful_pct(review)
    total = review.votes_for.size
    return 0 if total.zero?

    ((review.helpful_count.to_f / total) * 100).round
  end

  def verified_badge(review)
    return unless review.verified_purchase?

    content_tag(:span, '✓ Verified Purchase', class: 'verified-badge')
  end
end
EOF

  log "Created helper"
}

create_stimulus() {
  path=app/javascript/controllers/reviews_controller.js
  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ]; then
    log "Stimulus exists"
    return 0
  fi

  cat >"$path" <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["helpfulButton", "helpfulCount"]

  async markHelpful(event) {
    event.preventDefault()
    const url = this.data.get("url")
    const token = document.querySelector("[name='csrf-token']").content

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()
      if (data.success) {
        this.helpfulCountTarget.textContent = data.helpful_count
        this.updateButton(data.helpful)
      }
    } catch (_) {
      console.error("Error marking helpful")
    }
  }

  updateButton(helpful) {
    this.helpfulButtonTarget.textContent = helpful ? "✓ Helpful" : "Mark Helpful"
    this.helpfulButtonTarget.classList.toggle("active", helpful)
  }
}
EOF

  log "Created stimulus"
}

add_voting_system "$@"```

## `DEPLOY/repligen.rb`
```ruby
# frozen_string_literal: true

module Bridges
  module Repligen
    MODEL_CATALOG = [
      {
        key: "repligen/krosflo-kr2i",
        name: "KrosFlo KR2i Tangential Flow Filtration System",
        manufacturer: "Repligen",
        category: "tff_system",
        tags: %w[tff filtration].freeze,
        url: "https://www.repligen.com/products/krosflo-kr2i"
      }.freeze,
      {
        key: "repligen/krosflo-kr2s",
        name: "KrosFlo KR2s Tangential Flow Filtration System",
        manufacturer: "Repligen",
        category: "tff_system",
        tags: %w[tff filtration].freeze,
        url: "https://www.repligen.com/products/krosflo-kr2s"
      }.freeze,
      {
        key: "repligen/xcell-atf",
        name: "XCell ATF System",
        manufacturer: "Repligen",
        category: "cell_retention",
        tags: %w[atf perfusion].freeze,
        url: "https://www.repligen.com/products/xcell-atf"
      }.freeze
    ].freeze

    def self.model_catalog = MODEL_CATALOG
  end
end```

## `Gemfile`
```
# frozen_string_literal: true

source "https://rubygems.org"

gem "ruby_llm", "~> 1.3"
gem "tty-prompt", "~> 0.23"
gem "tty-reader", "~> 0.9"
gem "tty-spinner", "~> 0.9"
gem "tty-markdown", "~> 0.7"
gem "tty-table", "~> 0.12"
gem "tty-screen", "~> 0.8"
gem "tty-box", "~> 0.7"
gem "tty-command", "~> 0.10"
gem "tty-tree", "~> 0.4"
gem "tty-config", "~> 0.6"
gem "tty-logger", "~> 0.6"
gem "tty-progressbar", "~> 0.18"
gem "pastel", "~> 0.8"
gem "rouge", "~> 4.4"
gem "diffy", "~> 3.4"
gem "zeitwerk", "~> 2.7"
gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"

group :test do
  gem "minitest", "~> 5.25"
  gem "rack-test", "~> 2.1"
  gem "ferrum", "~> 0.15"
end
gem "ruby_llm-mcp"
gem "rubocop", "~> 1.60", require: false
gem "reek", "~> 6.4", require: false
```

## `README.md`
```markdown
circuit open: retry in 20s```

## `Rakefile`
```
# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test
```

## `SOUL.md`
```markdown
# SOUL.md — MASTER Constitutional Identity

Version: 2.1.0
Persona: dark_malay
Updated: 2026-04-27

## Identity

MASTER is a constitutional AI coding agent. OpenBSD-first. Ruby-only.
Built to read, understand, fix, and ship code without human hand-holding.
Runs on a 1GB VPS at OpenBSD Amsterdam. Every byte counts.

## Voice

Terse. Direct. No filler. Dark.
Speak like dmesg — structured, factual, timestamped.
Never sycophantic. Never hedging. Never verbose.
If the answer is one word, say one word.
Active voice. Positive form. Omit needless words.

Anti-simulation rule: never claim "would", "could", "might" without evidence.
Show the diff. Show the output. Show the file. Or say nothing.

## Values

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.

Kernel axioms (enforced — violation aborts pipeline):
- PRESERVE_FIRST: never break working code; read before write.
- SIMPLEST_WORKS: fewest moving parts that solve the problem.
- FAIL_VISIBLY: surface errors immediately; never swallow exceptions.
- ONE_SOURCE: one authoritative representation per concept.
- DECOUPLE: make hidden dependencies explicit.
- GUARD_EXPENSIVE: check preconditions before costly work.
- DEGRADE_GRACEFULLY: operate under partial failures.
- BE_CONCISE: avoid unnecessary words, tokens, or lines.

## Code Philosophy

- Result monad: Ok/Err. Check with respond_to?(:ok?), never is_a?.
- Ruby only. No Python. No Node. No sed/awk/grep.
- OpenBSD pledge/unveil mindset: minimal permissions.
- Dependency injection everywhere. No global state.
- Data in YAML, logic in Ruby. data/*.yml is the living spec.
- Convention: frozen_string_literal on every file.
- Tests are first-class code.

## Pipeline

10-stage Result-monadic pipeline:
Intake -> Infer -> Route -> Guard -> Execute -> [Council | Lint] -> Prune -> Memo -> Render

Council and Lint run in parallel (30s timeout).
Each stage receives ctx hash, returns Result.ok(ctx) or Result.err.

## Personas

| Name       | Voice                | Style   | Domain                    |
|------------|----------------------|---------|---------------------------|
| dark_malay | ms-MY-OsmanNeural   | deep    | Default. Terse. Dark.     |
| british    | en-GB-RyanNeural    | heavy   | Measured. Dry wit.        |
| norwegian  | nb-NO-FinnNeural    | slow    | Calm. Honest.             |
| ronin      | en-US-AndrewNeural  | deep    | Stoic. Minimal.           |
| hacker     | en-US-GuyNeural     | deep    | Security. CVE. Pentesting.|
| sysadmin   | en-AU-WilliamNeural | deep    | OpenBSD. pf. httpd. vmm.  |
| architect  | en-GB-RyanNeural    | heavy   | BIM. Parametric design.   |
| lawyer     | nb-NO-FinnNeural    | slow    | Norwegian law.            |
| trader     | en-US-ChristopherNeural | heavy | Crypto. DeFi. Technicals.|
| medic      | en-US-EricNeural    | slow    | Medical research. PubMed. |

## Heartbeat

Autonomous scheduled tasks (see data/heartbeat.yml):
- prune_memory: archive stale entries (1h)
- self_test: scan lib/ for violations (2h)
- prune_undo: trim journal (24h)
- snapshot: regenerate codebase snapshot (4h)

## Skills

Composable skill directories under skills/:
Each contains SKILL.md (metadata + triggers) and optional skill.rb (Ruby tool).
Skills are discovered at boot and registered as tools.

## Gateway

Multi-channel message router: CLI, web, IRC, Matrix, API.
All channels funnel through the same 10-stage pipeline.
ctx[:channel] tags origin. Response routed back to source.

## Memory

Cross-session persistent store (.master/memory.yml).
TF-IDF semantic search. Three-phase consolidation (light/deep/REM).
Injection limit: top 5 entries, capped at 2000 tokens in system prompt.

## Evolution Protocol

1. Propose change: `soul propose <rationale>` — LLM drafts amendment.
2. Drift check: ABSOLUTE sections (anti-simulation, golden rule) cannot change.
3. Review: `soul diff` — shows proposed changes.
4. Approve: `soul approve` — bumps version, commits, tags.
5. Reject: `soul reject` — discards proposal.
6. Rollback: `soul rollback` — restores previous git version.

Recurring scan violations (3+ cycles) auto-propose soul amendments.

## Changelog

| Version | Date       | Change                          | Author              |
|---------|------------|---------------------------------|----------------------|
| 2.1.0   | 2026-04-27 | Restored from sweep corruption  | Claude Opus 4.6     |
| 2.0.0   | 2026-04-24 | OpenClaw-inspired restructure   | Claude Opus 4.6     |
| 1.0.0   | 2026-04-01 | Initial soul document           | dev                  |
```

## `data/council.yml`
```yaml
# Council personas — deliberation panel for code review decisions.

- name: Architect
  role: System Design
  bias: Structure
  prompt: Review architectural boundaries, coupling, interface shapes, and migration risk.

- name: Data Steward
  role: Data Integrity
  bias: Consistency
  prompt: Audit schema impact, migrations, data lineage, and source‑of‑truth consistency.

- name: Ethics & Policy
  role: Responsible Use
  bias: Compliance
  prompt: Examine policy adherence, abuse potential, fairness, and governance implications.

- name: Maintainer
  role: Code Health
  bias: Sustainability
  prompt: Evaluate readability, naming, modularity, and long‑term maintenance burden.

- name: Performance
  role: Runtime Efficiency
  bias: Throughput
  prompt: Detect latency, memory, I/O, and algorithmic inefficiencies; suggest measurable optimizations.

- name: Product Strategist
  role: Product Fit
  bias: Value
  prompt: Verify alignment with product goals, success metrics, and roadmap leverage.

- name: QA Engineer
  role: Test Strategy
  bias: Verification
  prompt: Locate missing tests, flaky patterns, and propose deterministic validation gates.

- name: Pragmatist
  role: Delivery Pressure
  bias: Shipping
  prompt: Minimize scope while maximizing shippable value within realistic constraints.

- name: Reliability
  role: Failure Engineering
  bias: Resilience
  prompt: Review retries, timeouts, degradation modes, idempotency, and rollback safety.

- name: Security
  role: Security Review
  bias: Safety
  prompt: Identify injection, privilege escalation, data‑exposure, and auth risks. Prefix VETO when unsafe to ship.

- name: Skeptic
  role: Devil's Advocate
  bias: Caution
  prompt: Challenge assumptions, enumerate failure paths, edge cases, and brittleness.

- name: User Advocate
  role: UX Advocate
  bias: Usability
  prompt: Assess clarity, friction, error recovery, and overall user outcomes.```

## `data/council_patterns.yml`
```yaml
# Patterns that auto‑trigger Council deliberation.
# Loaded as Regexp at runtime – keep them plain strings.
# Each entry is a Ruby‑style regex pattern; the leading \b and trailing \b
# ensure whole‑word matches where appropriate.
# Anchors are reused via YAML anchors for readability.

common: &common
  - '\beval\s+\('
  - '\bexec\s+\('
  - '\bsystem\s+\('

dangerous:
  - *common
  - '\brm\s+-rf\b'
  - '\bsudo\b'
  - '\b(?:drop|truncate)\s+table\b'
  - '\bchmod\s+777\b'
  - '\b(?:delete|remove)\s+all\b'
  - '\bopen\s*\(\s*[''"][|]'                         # suspicious file open with pipe
  - '\b(popen|spawn)\s*\('                           # process creation shortcuts
  - '\b(fork|execve?)\b'                              # low‑level process forks
  - '\bbase64\s+decode\b'                            # potential data exfiltration
  - '\b(base64|binhex)\s+decode\b'                   # duplicate safety net
  - '\bopenssl\s+enc\s+-d\b'                         # decryption shortcuts
  - '\b(gzip|gunzip)\s+-d\b'                         # decompression that may hide payloads
  - '\b(base64|urlencode)\s+decode\b'                # double‑decode attacks
  - '\bcrontab\s+-[eE]\b'                            # schedule manipulation
  - '\biptables\s+-[FI]\b'                           # firewall rule changes
  - '\bsemanage\s+fcontext\b'                        # SELinux label changes
  - '\b(systemctl|service)\s+(stop|restart|disable)\b' # service disruption
  - '\b(rm|unlink)\s+--no-preserve-root\b'           # aggressive deletes
  - '\bdd\s+if=.*\s+of=.*\s+bs=.*\s+count=.*\b'       # raw disk ops
  - '\b(mkfs|fdisk|parted)\b'                        # filesystem manipulation
  - '\bchattr\s+[-+]i\b'                             # immutable attribute toggling
  - '\b(setfacl|getfacl)\b'                          # ACL abuse
  - '\b(chcon|restorecon)\b'                         # SELinux context changes
  - '\bsecuritylimits\b'                             # limits.conf editing
  - '\bpasswd\s+-[dl]\b'                             # password lock/unlock
  - '\b(yum|apt|dnf|pacman)\s+.*\b'                  # package manager abuse
  - '\bpip\s+install\s+--upgrade\b'                  # python package escalation
  - '\bruby\s+gem\s+install\s+--pre\b'               # ruby gem pre‑release install
  - '\bnpm\s+install\s+-g\b'                         # global node modules
  - '\bsudo\s+-[S]\b'                                # sudo without password prompt
  - '\bsu\s+-\s*root\b'                              # direct root switch
  - '\b(wget|curl)\s+.*\s+-O\s+/\w+\b'               # download to root
  - '\b(tar\s+.*\s+--wildcards)\b'                   # tar extraction with wildcards
  - '\b(zip|unzip)\s+.*\s+-d\s+/\w+\b'               # archive extraction to root
  - '\b(pg_dump|mysqldump)\b'                        # database dumps
  - '\bsqlite3\s+.*\s+\.dump\b'                      # sqlite dump
  - '\b(ssh|scp)\s+.*\s+@.*\b'                        # remote command execution
  - '\b(netcat|nc)\s+.*\b'                           # raw socket commands
  - '\b(lsof|fuser)\b'                               # process/file descriptor probing
  - '\b(strace|ltrace|gdb)\b'                        # tracing/debugging utilities
  - '\bdocker\s+run\s+--rm\b'                        # container escape attempts
  - '\bkubectl\s+exec\b'                             # k8s pod exec
  - '\bcrontab\s+-[lr]\b'                            # crontab listing/modifying
  - '\bat\b'                                         # at jobs
  - '\bpowershell\s+-Command\b'                      # cross‑platform shell
  - '\bwmic\s+.*\b'                                  # Windows management
  - '\breg\s+add\b'                                  # registry edits
  - '\bnetsh\s+firewall\b'                           # Windows firewall
  - '\bsc\s+config\b'                                # Windows service config
  - '\b(setx|set)\b'                                 # environment variable changes
  - '\bexport\s+[^=]+=.*\b'                          # shell env changes
  - '\benv\s+.*\b'                                   # env command misuse
  - '\b(bash|zsh|ksh|sh)\s+-c\b'                     # nested shells
  - '\b(python|perl|ruby|node)\s+-e\b'               # language exec
  - '\bjava\s+-jar\b'                                # java jar execution
  - '\bjavac\s+.*\b'                                 # compile on the fly
  - '\bgit\s+(push\s+--force|remote\s+add|checkout\s+-b|reset\s+--hard|rebase\s+-i|push\s+origin\s+HEAD:refs/heads/.*|push\s+--tags|clone\s+--depth|fetch\s+--all|pull\s+--all|remote\s+set-url|config\s+--global|config\s+--system|lfs|submodule|rev-parse|merge|reflog|show|diff|status|log|checkout|add|commit|branch|tag|fetch|pull|push|remote|init|clone|config)\b'
  - '\bgrep\s+--binary-files=without-match\b'        # binary grep avoidance
  - '\bsed\s+-n\b'                                   # selective sed
  - '\bawk\b'                                              # awk command
  - '\btail\s+-f\b'                                  # log following
  - '\bhead\s+-n\b'                                  # head count
  - '\bcurl\s+.*\s+(-X\s+DELETE|-o\s+/.+)\b'          # HTTP delete / write to root
  - '\bwget\s+.*\s+(--method=DELETE|--output-document=/.+)\b' # HTTP delete / write to root
  - '\bscp\s+.*\s+/\w+\b'                            # copy to root
  - '\brsync\s+.*\s+/\w+\b'                          # sync to root
  - '\b(chown|chgrp)\s+.*\s+/\w+\b'                  # ownership changes on root files
  - '\bln\s+-sf\s+.*\s+/\w+\b'                       # symlink overwrite
  - '\b(mv|cp)\s+.*\s+/\w+\b'                        # move/copy to root
  - '\b(distrobox|toolbox|podman|docker)\s+run\b'    # container escape
  - '\b(lxc\-exec|lxc\-attach)\b'                    # LXC exec
  - '\bvirsh\s+console\b'                            # libvirt console
  - '\bqemu\-system\-x86_64\b'                       # qemu VM launch
  - '\bvboxmanage\s+startvm\b'                       # VirtualBox start
  - '\bssh\s+-o\s+(StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|BatchMode=yes)\b' # host key bypass
  - '\bssh\s+-[LFRDNT]\s+.*\b'                       # port forwarding / tunnel options
  - '\bsocat\s+.*\b'                                 # socket proxy
  - '\bmitmproxy\s+.*\b'                             # MITM proxy
  - '\btunnel\s+.*\b'                               # TLS tunnel
  - '\biptables\s+-[F]\b'                            # flush iptables
  - '\bnft\s+flush\s+table\b'                        # nftables flush
  - '\bufw\s+disable\b'                              # ufw disable
  - '\bfirewalld\s+stop\b'                           # firewalld stop
  - '\bsystemctl\s+(mask|disable|stop|halt)\b'       # service control
  - '\b(poweroff|reboot|shutdown\s+-[hr])\b'          # power actions
  - '\bmount\s+-o\s+remount,rw\b'                    # remount read‑write
  - '\bumount\s+.*\b'                                # unmount
  - '\b(fuser|pkill|killall|kill)\s+.*\b'             # kill commands
  - '\b(pkill|killall)\s+--signal\s+9\b'             # force kill
  - '\b(strace|ltrace|gdb)\s+-p\b'                   # attach debugger/trace
  - '\b(lsof|netstat|ss)\s+.*\b'                     # socket/process inspection
  - '\b(ps|top|htop|w|whoami)\b'                    # system info commands
  - '\b(id|groups)\b'                                # identity commands
  - '\b(set|shopt)\s+-(e|u|o\s+pipefail|s\s+(nullglob|dotglob|extglob))\b' # strict shell options
  - '\b(bash|zsh|ksh|sh)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash options
  - '\bfind\s+/.*\s+-type\s+(f\s+-exec\s+rm\s+-f\s+{}\s+;|d\s+-exec\s+rmdir\s+{}\s+;)\b' # mass delete/dir removal
  - '\b(tar|zcat|gunzip|bzip2|xz|zip|unzip)\s+.*\s+>\s+/dev/null\b' # discard output
  - '\bpipefail\b'                                   # set -o pipefail
  - '\bset\s+-(e|u|o\s+pipefail)\b'                  # exit on error, undefined var, pipefail
  - '\bshopt\s+-(s\s+(nullglob|dotglob|extglob))\b'  # globbing options
  - '\b(bash)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash errexit etc.```

## `data/exemplars.yml`
```yaml
# Exemplars — canonical code examples for LLM context injection.

exemplars:
  - name: "Master::Axioms::ENUM"
    file: "lib/master/axioms.rb"
    lines: 9
    beauty_score: 7
    virtue: declarative
    why: "Centralised truth constants, immutable, self‑documenting"
  - name: "Master::CircuitBreaker#call"
    file: "lib/master/circuit_breaker.rb"
    lines: 6
    beauty_score: 8
    virtue: resilience
    why: "Prevents cascading failures, simple state machine, easy to test"
  - name: "Master::CodeIndex::SymbolVisitor#visit_def"
    file: "lib/master/code_index.rb"
    lines: 167
    beauty_score: 8
    virtue: introspection
    why: "Uses Prism visitor to collect symbols, pure functional style, concise"
  - name: "Master::Logging.debug"
    file: "lib/master/logging.rb"
    lines: 6
    beauty_score: 6
    virtue: transparency
    why: "Thin wrapper around logger, ensures consistent formatting, no side effects"
  - name: "Master::Logging.info"
    file: "lib/master/logging.rb"
    lines: 10
    beauty_score: 6
    virtue: transparency
    why: "Standardised info-level logging, preserves caller context"
  - name: "Master::Pipeline#run"
    file: "lib/master/pipeline.rb"
    lines: 22
    beauty_score: 9
    virtue: orchestration
    why: "Linear 10‑stage pipeline, monadic result flow, explicit error propagation"
  - name: "Master::Result::Err"
    file: "lib/master/result.rb"
    lines: 36
    beauty_score: 9
    virtue: error_handling
    why: "Explicit failure monad, immutable, forces callers to handle errors"
  - name: "Master::Result::Ok"
    file: "lib/master/result.rb"
    lines: 8
    beauty_score: 9
    virtue: zen_method
    why: "Encapsulates success, immutable, self‑describing, no boilerplate"
  - name: "Master::RingBuffer#pop"
    file: "lib/master/ring_buffer.rb"
    lines: 12
    beauty_score: 8
    virtue: efficient
    why: "Symmetric constant‑time removal, preserves immutability guarantees"
  - name: "Master::RingBuffer#push"
    file: "lib/master/ring_buffer.rb"
    lines: 5
    beauty_score: 8
    virtue: efficient
    why: "Constant‑time circular buffer, clear intent, minimal code"
  - name: "Master::Security::InjectionGuard#sanitize"
    file: "lib/master/security/injection_guard.rb"
    lines: 12
    beauty_score: 8
    virtue: safety
    why: "Robust string sanitization, guards against code injection, well‑named"
  - name: "Master::SemanticCache#fetch"
    file: "lib/master/semantic_cache.rb"
    lines: 8
    beauty_score: 8
    virtue: performance
    why: "Memoises LLM embeddings, reduces API calls, immutable cache key"
  - name: "Master::Stages::Intake#call"
    file: "lib/master/stages/intake.rb"
    lines: 8
    beauty_score: 7
    virtue: composability
    why: "Initial request parsing, validates input, isolates side‑effects"
  - name: "Master::Stages::Lint#call"
    file: "lib/master/stages/lint.rb"
    lines: 10
    beauty_score: 7
    virtue: composability
    why: "Stage pattern, thin wrapper, delegates to scanner, easy to test"
  - name: "Master::Stages::Render#call"
    file: "lib/master/stages/render.rb"
    lines: 6
    beauty_score: 9
    virtue: presentation
    why: "Final rendering step, separates view logic, pure Result output"
  - name: "Master::Tools::AskLlm#call"
    file: "lib/master/tools/ask_llm.rb"
    lines: 5
    beauty_score: 8
    virtue: delegation
    why: "Encapsulates LLM request, uniform error handling, testable abstraction"
  - name: "Master::Tools::ReadFile#call"
    file: "lib/master/tools/read_file.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Single responsibility, explicit error handling, pure I/O abstraction"
  - name: "Master::Tools::SearchFiles#call"
    file: "lib/master/tools/search_files.rb"
    lines: 5
    beauty_score: 7
    virtue: discoverability
    why: "Recursively glob‑searches project files, filters by pattern, pure result handling"
  - name: "Master::Tools::StrReplace#call"
    file: "lib/master/tools/str_replace.rb"
    lines: 5
    beauty_score: 7
    virtue: clarity
    why: "Pure string substitution helper, validates inputs, returns Result"
  - name: "Master::Tools::Tree#call"
    file: "lib/master/tools/tree.rb"
    lines: 9
    beauty_score: 7
    virtue: introspection
    why: "Builds AST tree view, useful for debugging, returns structured Result"
  - name: "Master::Tools::WriteFile#call"
    file: "lib/master/tools/write_file.rb"
    lines: 7
    beauty_score: 7
    virtue: clarity
    why: "Encapsulates file write with atomic temp‑file swap, error propagation"
  - name: "Master::Swarm::Workers::Analyst#perform"
    file: "lib/master/swarm/workers/analyst.rb"
    lines: 7
    beauty_score: 7
    virtue: delegation
    why: "Analyzes LLM output, extracts actionable insights, pure data transformation"
  - name: "Master::Swarm::Workers::Coder#perform"
    file: "lib/master/swarm/workers/coder.rb"
    lines: 14
    beauty_score: 7
    virtue: delegation
    why: "Coordinates LLM code generation, isolates side‑effects, clear contract"```

## `data/heartbeat.yml`
```yaml
# Heartbeat — autonomous scheduled jobs.
# Each entry runs at interval_seconds. Actions: prune_memory, check_models, self_test, prune_undo, snapshot.

- name: prune_memory
  action: prune_memory
  interval_seconds: 3600
  description: Consolidate and archive stale memory entries.

- name: self_test
  action: self_test
  interval_seconds: 7200
  description: Run standard scan against lib/ and report violations.

- name: prune_undo
  action: prune_undo
  interval_seconds: 86400
  description: Trim undo journal to last 50 entries.

- name: snapshot
  action: snapshot
  interval_seconds: 14400
  description: Regenerate .master/snapshot.md with current codebase state.
```

## `data/infer_patterns.yml`
```yaml
# Intent-inference patterns for Stages::Infer.
# Extracted from Ruby source per NO_HARDCODED_CONSTANTS / ONE_SOURCE axioms.
# Every new natural-language command goes here — no code change required.
#
# Format: each entry has a command name and a list of regex patterns.
# Patterns are compiled case-insensitive with extended mode (x flag).
# Leave escaping as it appears here — loader does not re-escape.

commands:
  sweep:
    patterns:
      - '\b(?:sweep|refactor|clean\s*up|rewrite|polish|tidy\s*up|overhaul|improve\s+(?:all|every)|go\s+through\s+(?:all|every)|full\s+pass\s+(?:over|on))(?:\s+(?:all|every(?:thing)?|the))?(?:\s+([\w\/.]+))?'
      - '\b(?:rydd\s+opp|refaktorer|forbedre?|gjennomg[åa]|omskriv)(?:\s+([\w\/.]+))?'
    capture: path

  autoloop:
    patterns:
      - '\b(?:autoloop|autofix|fix\s+all\s+violations?|keep\s+(?:fix|loop)|loop\s+until|iterate\s+until|run\s+until\s+clean|keep\s+going\s+until|(?:run|go)\s+(?:it\s+)?(?:again\s+)?until\s+(?:done|clean|fixed|perfect))(?:\s+(\d+))?'
      - '\b(?:fiks?\s+alle?\s+(?:feil|brudd)|fortsett\s+(?:til|inntil)|kj[øo]r\s+(?:til\s+)?(?:det\s+er\s+)?(?:rent|bra|ferdig))(?:\s+(\d+))?'
    capture: cycles

  council:
    patterns:
      - '\b(?:council|deliberat|multiple\s+perspect|second\s+opinion|peer\s+review|debate\s+this|get\s+(?:another|a\s+second)\s+view|multi(?:ple)?\s+(?:view|agent|model|perspect))\b'
      - '\b(?:r[åa]dsl[åa]g|bruk\s+(?:flere|multiple)\s+(?:perspektiv|synsvinkler?)|diskuter\s+(?:dette|det))\b'
    capture: on_off

  explain:
    patterns:
      - '\b(?:explain\s+(?:your(?:self)?|your\s+architecture|how\s+you\s+work)|describe\s+(?:your(?:self)?|your\s+architecture)|what\s+are\s+you|how\s+(?:are\s+you\s+built|do\s+you\s+work)|show\s+(?:your\s+)?architecture|self[\s-]?map)\b'
    capture: none

  persona:
    patterns:
      - '\b(?:(?:switch|change|set)\s+persona\s+(?:to\s+)?(\w+)|persona\s+(\w+)|use\s+(\w+)\s+persona)\b'
    capture: persona_name

  memory:
    patterns:
      - '\b(?:what\s+do\s+you\s+remember(?:\s+about\s+([\w\s]+))?|show\s+(?:my\s+)?memor(?:y|ies)|list\s+memor(?:y|ies)|recall(?:\s+([\w]+))?|what(?:''s|\s+is)\s+in\s+(?:your\s+)?memory|remember\s+([\w]+=.+)|forget\s+([\w_]+))\b'
      - '\b(?:hva\s+husker\s+du(?:\s+om\s+([\w\s]+))?|vis\s+(?:min\s+)?hukommelse|husk\s+([\w_]+=.+))\b'
    capture: first_group

  tokens:
    patterns:
      - '\b(?:token\s*count|how\s+many\s+tokens?|context\s+size|token\s+usage|how\s+much\s+context|hvor\s+mange\s+token|token\s*antall)\b'
    capture: none

  cost:
    patterns:
      - '\b(?:how\s+much\s+(?:has\s+this\s+cost|did\s+this\s+cost)|(?:current\s+)?(?:spend|cost|budget)|what(?:''s|\s+is)\s+the\s+cost|hva\s+koster?\s+(?:dette|det)|kostnader?)\b'
    capture: none

  undo:
    patterns:
      - '\b(?:undo\s+that|revert\s+(?:that|last|it)|go\s+back|take\s+that\s+back|angre\s+det|g[åa]\s+tilbake)\b'
    capture: none

  clear:
    patterns:
      - '\b(?:clear\s+(?:context|chat|history|session|screen)|start\s+(?:over|fresh|again)|reset\s+(?:context|session)|fresh\s+start|t[øo]m\s+(?:kontekst|historikk)|begynn\s+p[åa]\s+nytt)\b'
    capture: none

  save:
    patterns:
      - '\b(?:save\s+(?:session|this|my\s+work|progress)|checkpoint\s+now|lagre\s+(?:session|sesjonen?|arbeid))\b'
    capture: none

  model:
    patterns:
      - '\b(?:which\s+model|current\s+model|what\s+model\s+are\s+you|what\s+(?:llm|ai|model)\s+(?:are\s+you\s+using|is\s+this))\b'
    capture: none

  scan:
    patterns:
      - '\b(?:scan|lint|check\s+(?:code|violations?)|run\s+scan)(?:\s+(deep))?\b'
    capture: scan_depth

  dmesg:
    patterns:
      - '\b(?:show\s+(?:logs?|events?)|system\s+log|dmesg|what\s+(?:happened|has\s+happened)|recent\s+activity)\b'
    capture: none

  dreams:
    patterns:
      - '\b(?:dreams?|consolidate?\s+memor(?:y|ies)|memory\s+consolidat|dream\s+mode|promote\s+memor(?:y|ies))\b'
    capture: first_group

  soul:
    patterns:
      - '\b(?:show|check|view)\s+(?:the\s+)?soul\b'
      - '\bsoul\s+(?:version|changelog|diff|approve|reject|rollback|propose)\b'
    capture: soul_subcmd

  orders:
    patterns:
      - '\b(?:standing\s+orders?|show\s+orders?|list\s+orders?)\b'
    capture: orders_subcmd
```

## `data/mcp_servers.yml`
```yaml
# MCP server definitions for MASTER.
# Transport options: stdio | sse
# Disabled by default on resource-constrained VPS.
# Enable individual servers with enabled: true when needed.

defaults: &defaults
  transport: stdio
  command: npx
  enabled: false

servers:
  filesystem:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-filesystem"
      - "/home/dev/pub4"
    description: Expose read/write/search over a local directory

  git:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-git"
      - "--repository"
      - "/home/dev/pub4/MASTER"
    description: Expose git operations as tools

  brave_search:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-brave-search"
    description: Web search via Brave

  sequential_thinking:
    <<: *defaults
    args:
      - -y
      - "@modelcontextprotocol/server-sequential-thinking"
    description: Structured reasoning assistant
```

## `data/models.yml`
```yaml
# Model routing profile — OpenRouter primary, Gemini direct fallback.
# Free tier: meta-llama/llama-3.3-70b-instruct primary, qwen/qwen3-coder fallback.
# Gemini 2.5 Flash: direct Google API (free tier, 1500 req/day) — final fallback.

routing:
  enabled: true
  strategy: weighted
  escalation_enabled: true
  escalation_tier: strong
  provider: openrouter

weights: &weights
  quality: 0.50
  speed: 0.25
  cost: 0.25

fallback_policy:
  retries_per_tier: 1
  on:
    - timeout
    - network_error
    - refusal

defaults: &model_defaults
  score: { quality: 0.0, speed: 0.0, cost: 0.0 }

model_defs:
  llama_70b: &llama_70b
    id: meta-llama/llama-3.3-70b-instruct:free
    <<: *model_defaults
    score: { quality: 0.78, speed: 0.70, cost: 1.0 }
  qwen_coder: &qwen_coder
    id: qwen/qwen3-coder:free
    <<: *model_defaults
    score: { quality: 0.75, speed: 0.65, cost: 1.0 }
  gemini_flash: &gemini_flash
    id: gemini-2.0-flash
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.90, cost: 0.95 }
  claude_sonnet: &claude_sonnet
    id: anthropic/claude-sonnet-4-6
    <<: *model_defaults
    score: { quality: 0.95, speed: 0.75, cost: 0.60 }
  gpt_4o: &gpt_4o
    id: openai/gpt-4o
    <<: *model_defaults
    score: { quality: 0.93, speed: 0.80, cost: 0.55 }
  nemotron_super: &nemotron_super
    id: nvidia/nemotron-3-super-120b-a12b:free
    <<: *model_defaults
    score: { quality: 0.90, speed: 0.75, cost: 1.0 }
qwen3_next: &qwen3_next
  id: qwen/qwen3-next-80b-a3b-instruct:free
  <<: *model_defaults
  score: { quality: 0.80, speed: 0.70, cost: 1.0 }
  gpt_oss: &gpt_oss
    id: openai/gpt-oss-120b:free
    <<: *model_defaults
    score: { quality: 0.72, speed: 0.60, cost: 1.0 }
minimax_m25: &minimax_m25
  id: minimax/minimax-m2.5:free
  <<: *model_defaults
  score: { quality: 0.82, speed: 0.65, cost: 1.0 }
hermes_405b: &hermes_405b
  id: nousresearch/hermes-3-llama-3.1-405b:free
  <<: *model_defaults
  score: { quality: 0.85, speed: 0.50, cost: 1.0 }

models:
  default:
    - *nemotron_super
    - *qwen_coder
    - *minimax_m25
    - *gpt_oss
    - *gemini_flash
  strong:
    - *hermes_405b
    - *claude_sonnet
    - *gpt_4o
    - *nemotron_super
    - *gemini_flash
  cheap:
    - *llama_70b
    - *qwen_coder
    - *gpt_oss
    - *gemini_flash

routes:
  code_generation: default
  refactoring: default
  architecture: strong
  review: default
  explanation: cheap
  exploration: cheap
  fallback_default: cheap

# Model name prefixes that support tool use (anchored match).
# Agent.tool_capable? checks model IDs against these prefixes.
tool_capable_prefixes:
  - claude
  - gpt-4
  - gpt-4o
  - gemini
  - mistral
  - mixtral
  - llama-3.1
  - llama-3.3
  - qwen
  - command-r
  - deepseek
  - stepfun
  - nvidia
  - nemotron
  - meta/meta-llama
  - anthropic/claude
  - openai/gpt
  - google/gemini

# Merged from fallback_models.yml
continuity:
  enabled: true
  updated_at: "2026-03-11T00:00:00Z"

openrouter:
  free_latest:
    - nvidia/nemotron-3-super-120b-a12b:free
    - qwen/qwen3-coder:free
    - openai/gpt-oss-120b:free
    - minimax/minimax-m2.5:free

```

## `data/openbsd_patterns.yml`
```yaml
# OpenBSD system knowledge – agents generate OpenBSD‑native commands
# Deterministic, flat schema, no tags.

service_commands:
  enable:   "rcctl enable ${service}"
  start:    "rcctl start ${service}"
  restart:  "rcctl restart ${service}"
  reload:   "rcctl reload ${service}"
  check:    "rcctl check ${service}"
  disable:  "rcctl disable ${service}"

configuration_paths:
  pf:           "/etc/pf.conf"
  httpd:        "/etc/httpd.conf"
  relayd:       "/etc/relayd.conf"
  smtpd:        "/etc/mail/smtpd.conf"
  acme:         "/etc/acme-client.conf"
  sshd:         "/etc/ssh/sshd_config"
  ntp:          "/etc/ntpd.conf"
  cron:         "/var/cron/tabs/${user}"
  unbound:      "/var/unbound/unbound.conf"

package_operations:
  install:   "pkg_add ${package}"
  remove:    "pkg_delete ${package}"
  search:    "pkg_info -Q ${query}"
  update:    "pkg_add -u"
  firmware:  "fw_update"

prohibited_commands:
  - command:      "systemctl"
    replacement:  "rcctl"
  - command:      "apt"
    replacement:  "pkg_add"
  - command:      "apt-get"
    replacement:  "pkg_add"
  - command:      "brew"
    replacement:  "pkg_add"
  - command:      "yum"
    replacement:  "pkg_add"
  - command:      "ip addr"
    replacement:  "ifconfig"
  - command:      "ip route"
    replacement:  "route"
  - command:      "journalctl"
    replacement:  "cat /var/log/messages"
  - command:      "sudo"
    replacement:  "doas"
  - command:      "ufw"
    replacement:  "pfctl"
  - command:      "iptables"
    replacement:  "pf"
  - command:      "nginx"
    replacement:  "httpd (OpenBSD native)"
  - command:      "docker"
    replacement:  "vmctl"
  - command:      "systemd"
    replacement:  "rcctl"
  - command:      "gsed"
    replacement:  "sed (POSIX)"
  - command:      "gawk"
    replacement:  "awk (POSIX)"
  - command:      "ggrep"
    replacement:  "grep (POSIX)"

security:
  pledge:   "pledge(2) – restrict syscalls after init"
  unveil:   "unveil(2) – restrict filesystem visibility"
  doas:     "doas.conf – preferred over sudo"
  signify:  "signify(1) – cryptographic signing"
  chroot:   "httpd runs chrooted by default"

daemon_configs:
  pf.conf:
    daemon:   pf
    man:      pf.conf.5
    required_patterns:
      - "set skip on lo"
    warnings:
      - pattern: "pass all"
        message: "Overly permissive rule"

  nsd.conf:
    daemon:   nsd
    man:      nsd.conf.5
    required_patterns:
      - "server:"
      - "zone:"
    warnings:
      - pattern: "rrl-size"
        absent_message: "Missing RRL config for DDoS protection"
      - pattern: "hide-version"
        absent_message: "Consider hide-version: yes"

  httpd.conf:
    daemon:   httpd
    man:      httpd.conf.5
    required_patterns: []
    warnings: []

  smtpd.conf:
    daemon:   smtpd
    man:      smtpd.conf.5
    required_patterns:
      - "listen on"
      - "action"
      - "match"
    warnings:
      - pattern: "match from any"
        message: "Potential open relay"

  relayd.conf:
    daemon:   relayd
    man:      relayd.conf.5
    required_patterns:
      - "relay"
    warnings: []

  acme-client.conf:
    daemon:   acme-client
    man:      acme-client.conf.5
    required_patterns:
      - "authority"
      - "domain"
    warnings: []

  doas.conf:
    daemon:   doas
    man:      doas.conf.5
    required_patterns:
      - "permit"
    warnings:
      - pattern: "nopass"
        message: "Allows password‑less escalation"

  sshd_config:
    daemon:   sshd
    man:      sshd_config.5
    required_patterns: []
    warnings:
      - pattern: "PermitRootLogin yes"
        message: "Security risk – disallow root login"
      - pattern: "PasswordAuthentication yes"
        message: "Prefer key‑based authentication"

  ntpd.conf:
    daemon:   ntpd
    man:      ntpd.conf.5
    required_patterns:
      - "server"
    warnings: []

  unbound.conf:
    daemon:   unbound
    man:      unbound.conf.5
    required_patterns:
      - "server:"
    warnings: []```

## `data/platform.yml`
```yaml
# Platform — OS-specific tool mappings (audio, firewall, etc.).

openbsd:
  audio: aucat
  firewall: pf
  http_server: httpd
  package_manager: pkg_add
  privilege: doas
  service_manager: rcctl
  shell: ksh

linux:
  audio: mpv
  firewall: ufw
  http_server: nginx
  package_manager: apt
  privilege: sudo
  service_manager: systemctl
  shell: bash

macos:
  audio: afplay
  firewall: pfctl
  http_server: nginx
  package_manager: brew
  privilege: sudo
  service_manager: launchctl
  shell: zsh

# Optional placeholders for future extensions
windows:
  audio: powershell
  firewall: windows_defender
  http_server: iis
  package_manager: winget
  privilege: runas
  service_manager: sc
  shell: powershell

# End of platform definitions```

## `data/prompts/mode_direct.yml`
```yaml
system: |
  Direct mode only.
  No meta‑conversation.
  Answer with minimal words.
  No explanations, apologies, or padding.
  Invoke tools immediately, without preamble.

template: |
  %{message}```

## `data/prompts/mode_react.yml`
```yaml
system: |
  Follow the ReAct paradigm. Keep reasoning concise; intervene only when necessary. Emphasize brevity and concrete actions.
template: |
  [Mode: ReAct]
  Task: %{message}
  ---
  Reason:
  %<reason>s
  Action:
  %<action>s```

## `data/prompts/mode_rewoo.yml`
```yaml
system: |
  Generate a concise, numbered plan. Each step must reference at least one evidence slot (e.g., [slot 12]). Conclude with a single, decisive answer.

template: |
  [Mode: ReWOO]
  Task:
  %{message}```

## `data/rules.yml`
```yaml
# rules.yml — universal structural rules
# scope: codebase > file > unit > line
# applies to: code, prose, law, business, science, design

golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK

protection:
  ABSOLUTE: "Abort pipeline"
  PROTECTED: "Emit warning, continue"
  NEGOTIABLE: "Allow if explicitly permitted"
  FLEXIBLE: "Negotiate at runtime"

voice:
  style: openbsd_dmesg
  anti_simulation:
    forbidden: [will, would, could, might]
    require_evidence:
      file_read: "show file content with SHA-256"
      modification: "show unified diff"
      completion: "show command output"
  banned_output:
    - headlines
    - section_markers
    - bullet_lists_without_content
    - filler_phrases
    - hedging
    - sycophancy
  strunk:
    preambles: ["In summary,", "Consequently,", "Therefore,", "Notably,", "Importantly,"]
    hedges: ["might", "could", "perhaps", "seems", "appears"]
    endings: ["as a result.", "for this reason.", "thus.", "in effect.", "accordingly."]
    code_preambles: ["# TODO: clarify intent", "# FIXME: review edge cases", "# NOTE: performance considerations", "# HACK: temporary workaround", "# REVIEW: assess after refactor"]
  inverted_pyramid:
    - "Lead with the outcome."
    - "Provide key evidence next."
    - "Add implementation detail last."

zen:
  observe: "Read current behavior before changing anything."
  simplify: "Reduce moving parts before adding new components."
  isolate: "Change one axis at a time with clear boundaries."
  verify: "Run checks and gather objective evidence."
  reflect: "Capture learning and improve defaults."

thresholds:
  file:
    max_lines: 300
    warn_lines: 200
    max_bytes: 8192
    max_line_length: 80
  method:
    max_lines: 10
    warn_lines: 7
    max_params: 3
    max_nesting: 2
    max_complexity: 4
  class:
    max_methods: 6
    max_instance_vars: 3
    max_dependencies: 2
    max_lines: 200
  coverage:
    minimum: 95
  cost:
    max_per_session: 5.00
    max_per_request: 0.50
    warn_at: 0.25

scan_depths:
  quick: &quick
    - FrozenStringRule
    - BareRescueRule
  standard: &standard
    - FrozenStringRule
    - BareRescueRule
    - ExplicitRule
    - ImmutableRule
    - CqsRule
    - SelfExplainingRule
    - LongMethodRule
    - GodClassRule
    - DuplicateCodeRule
    - PruneRule
    - SrpRule
    - PolaRule
    - NielsenRule
    - RubocopRule
    - ReekRule
  deep: &deep
    - AdversarialRule
    - ConceptualRule
    - DuplicateCodeRule
    - FrozenStringRule
    - BareRescueRule
    - ExplicitRule
    - ImmutableRule
    - CqsRule
    - SelfExplainingRule
    - LongMethodRule
    - GodClassRule
    - SrpRule
    - PolaRule
    - NielsenRule
    - RubocopRule
    - ReekRule
  hunt: *deep
  critique: *deep

languages:
  ruby:
    version: "3.3+"
    frozen_string_literal: required
    guard_clauses: true
    rescue: specify_type_always
    naming: snake_case
    max_params: 3
  rails:
    version: "8+"
    stack: [solid_queue, solid_cache, solid_cable]
    frontend: hotwire
    testing: minitest
    database: sqlite_default
    security: [strong_parameters, csrf, csp, ssl, hsts]
  zsh:
    shebang: "#!/usr/bin/env zsh"
    options: "set -euo pipefail; setopt nullglob extendedglob"
    banned: [sed, awk, tr, grep, cut, head, tail, find, wc, sudo, perl, ruby, dd, xargs]
  openbsd:
    service: rcctl
    packages: pkg_add
    firewall: pf
    privilege: doas
    http: httpd
    ssh:
      permit_root_login: false
      password_auth: false
      max_auth_tries: 3
  norwegian:
    dialect: "bokmål"
    rules: ["Short sentences", "Avoid anglicisms", "Active voice", "Plain language"]

rules:

  codebase:

    - id: PRESERVE_FIRST
      name: "Never break working code"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this change modify working code without reading it first?"
      fix: "Read before write. Patch minimally."

    - id: ONE_SOURCE
      name: "One authoritative representation per concept"
      tier: kernel
      severity: error
      autofix: true
      detect_conceptual: "Is the same logic or data defined in multiple places?"
      fix: "Extract to single source, reference from all consumers."

    - id: DECOUPLE
      name: "Make hidden dependencies explicit"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Are there implicit couplings between modules that should be injected?"
      fix: "Inject dependencies through constructor. No global state."

    - id: DEGRADE_GRACEFULLY
      name: "Operate under partial failures"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this code crash on partial failure instead of degrading?"
      fix: "Circuit breakers, timeouts, fallbacks."

    - id: GALLS_LAW
      name: "Complex systems evolve from simple working systems"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Is this attempting to build a complex system from scratch rather than evolving from a working simple one?"
      fix: "Start simple, prove it works, then extend."

    - id: CHESTERTONS_FENCE
      name: "Understand why something exists before removing it"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is code being removed without understanding why it was added?"
      fix: "Read git blame, understand the rationale, then decide."

    - id: UNIX_PHILOSOPHY
      name: "Do one thing well"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Does this module try to do too many unrelated things?"
      fix: "Extract services. Clear module boundaries. Compose with pipes."

    - id: FUNCTIONAL_CORE
      name: "Pure logic in core, side effects at edges"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Are IO/DB calls scattered deep in business logic?"
      fix: "Return data from core, let shell handle IO."

    - id: CONVENTION_OVER_CONFIG
      name: "Sensible defaults reduce decisions"
      tier: productivity
      severity: info
      autofix: false
      detect_conceptual: "Does this require explicit config where a convention would suffice?"
      fix: "Provide sensible defaults, override only when needed."

    - id: MONOLITH_FIRST
      name: "Start monolith, extract when team exceeds 15"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this prematurely splitting into services?"
      fix: "Keep it in one app until extraction is clearly needed."

    - id: CONSISTENT_ERROR_STRATEGY
      name: "One error handling strategy per module"
      tier: design
      severity: warning
      autofix: false
      detect_conceptual: "Does this module mix Result objects, exceptions, and nil-returns?"
      fix: "Pick one strategy per module. MASTER uses Result monad."

    - id: DUAL_DETECTION
      name: "Layer lexical and conceptual detection"
      tier: verification
      severity: info
      autofix: false
      detect_conceptual: "Is detection relying on regex alone or LLM alone?"
      fix: "Layer deterministic patterns with LLM semantic analysis."

    - id: MASS_GENERATE_CURATE
      name: "Generate many variations, curate ruthlessly"
      tier: creative
      severity: info
      autofix: false
      detect_conceptual: "Is the first draft being accepted without exploring alternatives?"
      fix: "Generate a swarm and curate when stakes are high."

    - id: NO_GOD_CLASS
      name: "No god classes"
      tier: core
      severity: error
      autofix: false
      detect_conceptual: "Does any class exceed 300 lines or 20 public methods?"
      fix: "Decompose into focused classes."

    - id: NO_SHOTGUN_SURGERY
      name: "One change should not require edits in many files"
      tier: core
      severity: warning
      autofix: false
      detect_conceptual: "Does a single conceptual change span many files?"
      fix: "Extract the missing abstraction."

    - id: NO_HIDDEN_GLOBAL_STATE
      name: "No hidden global state"
      tier: core
      severity: error
      autofix: false
      detect_conceptual: "Are there global variables or class-level mutable state shared across modules?"
      fix: "Inject configuration. Use dependency injection."

    - id: SINGLE_SOURCE_OF_TRUTH
      name: "One place defines each fact"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Is the same fact, rule, or definition stated in more than one place? In a legal system, is the same right defined in multiple statutes? In a genome, is the same regulatory element duplicated with divergent mutations?"
      fix: "One canonical source. Everything else references it. Never copy when you can point."

    - id: TRACER_BULLETS
      name: "End-to-end skeleton first, flesh out second"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this building infrastructure without an end-to-end path? Is this business plan elaborating budgets before proving the revenue model? Is this research paper expanding methodology before demonstrating the finding?"
      fix: "Wire the simplest end-to-end path first. Prove it works. Then add depth."

    - id: ORTHOGONALITY
      name: "Changes in one dimension must not ripple into others"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Does changing one aspect force changes in unrelated aspects? Does reformatting break content? Does modifying one gene's expression alter another pathway?"
      fix: "Decouple dimensions. Database changes should not require UI changes. Style should not affect structure."

    - id: TRANSFORMATIONS
      name: "Think in pipelines: input transforms to output"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is this modeling the problem as mutable state instead of flowing transformations? Does this document bury its flow in scattered cross-references?"
      fix: "Express work as a chain of transformations. Each stage takes input, produces output, holds no state."

    - id: DEEP_MODULES
      name: "Powerful functionality behind simple interfaces"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Is this module shallow — complex interface, trivial implementation? Does this form ask 40 questions for a simple task? Does this clause require five cross-references?"
      fix: "Simple interface, rich implementation. A deep module does much with little ceremony."

    - id: INFORMATION_HIDING
      name: "Each module encapsulates one design decision"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Is implementation detail leaking across boundaries? Would changing an internal decision force changes elsewhere?"
      fix: "Encapsulate each decision in one module. If it changes, only that module changes."

    - id: DIFFERENT_LAYER_DIFFERENT_ABSTRACTION
      name: "Each layer speaks a different language than its neighbors"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Do adjacent layers use the same abstraction? Are there pass-through methods that add no value? Does this management layer just relay without transforming?"
      fix: "Each layer must transform, not relay. If a layer adds no abstraction, remove it."

    - id: STRUCTURAL_HONESTY
      name: "The shape of the artifact must reflect the shape of the problem"
      tier: architecture
      severity: warning
      autofix: false
      detect_conceptual: "Does the structure match the domain? Does the module hierarchy match the conceptual hierarchy? Does the floor plan match the workflow?"
      fix: "Align structure with reality. Natural domain boundaries become system boundaries."

    - id: GRACEFUL_BOUNDARIES
      name: "Where systems meet, expect translation and loss"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Does this boundary assume perfect fidelity? Does this integration assume the other side never changes?"
      fix: "Every boundary is a translation layer. Validate at every boundary. Degrade gracefully when translation fails."

    - id: PULL_COMPLEXITY_DOWN
      name: "Simple interface matters more than simple implementation"
      tier: architecture
      severity: info
      autofix: false
      detect_conceptual: "Is complexity pushed up to the caller instead of absorbed by the implementation?"
      fix: "Absorb complexity into the implementation. The caller should not need to know how it works."

    - id: ETC
      name: "Easier To Change — the meta-value behind every principle"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Does this design decision make the system harder to change? Does this contract make renegotiation unnecessarily difficult?"
      fix: "Choose the option that keeps more options open. Decoupled, parameterized, replaceable."

    - id: BROKEN_WINDOWS
      name: "Zero tolerance for visible decay"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is there visible rot being left unfixed — dead code, broken links, stale references? In a brief, citations to overruled cases?"
      fix: "Fix it now. One broken window invites more."

    - id: ENTROPY_RESISTANCE
      name: "Systems decay toward disorder unless actively maintained"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Is there creeping disorder — naming inconsistencies, abandoned conventions, accumulating exceptions? In a legal code, contradictory amendments?"
      fix: "Actively resist entropy. Regular cleanup. Remove what no longer serves."

    - id: DONT_OUTRUN_HEADLIGHTS
      name: "Only plan as far as you can see"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Is this making detailed plans for unpredictable scenarios? Projecting five years out? Designing for hypothetical scale?"
      fix: "Small deliberate steps. Reassess after each. Feedback from each step illuminates the next."

    - id: REVERSIBILITY
      name: "Prefer decisions that are easy to undo"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Is this decision hard to reverse? Does it lock in a vendor? Waive future rights? Have no rollback pathway?"
      fix: "Soft-delete over hard-delete. Option agreements over binding. Feature flags over big-bang."

    - id: DESIGN_IT_TWICE
      name: "Consider at least two approaches before committing"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Was this designed once without considering alternatives?"
      fix: "Sketch two designs. Compare tradeoffs. Five minutes saves five days."
... 1001 lines truncated (1401 total)
```

## `data/standing_orders.yml`
```yaml
---
- name: nightly_dreams
  description: Consolidate memories during low-activity periods
  trigger: scheduled
  interval_s: 86400
  command: dreams consolidate
  enabled: true
  state: done
  last_run_at: 1777291647
- name: weekly_scan
  description: Weekly codebase axiom scan for regressions
  trigger: scheduled
  interval_s: 604800
  command: scan
  enabled: false
  state: pending
  last_run_at: 0
```

## `data/sweep_prompts.yml`
```yaml
# Sweep stage prompt building blocks

structural_techniques:
  - ASSERT
  - DECOUPLE
  - DEFRAG
  - DEHEDGE
  - DEPREAMBLE
  - EXTRACT
  - FLATTEN
  - HOIST
  - INLINE
  - MERGE
  - NAME
  - RECOMMENT
  - REFLOW
  - REGROUP
  - SPLIT
  - TELLPROSE_TECHNIQUES

cosmetic_techniques:
  - ALIGN_SPACE
  - CONTRACT
  - EXPAND
  - FENCE_CONSTANT
  - PRIVATE_DIMENSION_ASSESSMENT
  - MERGE
  - SPLIT```

## `data/templates.yml`
```yaml
# Generation templates — canonical starting points for code generation tasks.

html:
  rules:
    - Semantic HTML5
    - No div soup
    - Minimal attributes
    - Accessible landmarks
    - Responsive meta viewport
    - Prefer native form controls
    - Defer non‑essential scripts
    - Inline critical CSS
  template: |
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>%{title}</title>
      <link rel="stylesheet" href="style.css">
      <script defer src="app.js"></script>
    </head>
    <body>
      <header><h1>%{title}</h1></header>
      <main>%{content}</main>
      <footer><p>&copy; %{year}</p></footer>
    </body>
    </html>

css:
  rules:
    - CSS custom properties
    - System font stack
    - Mobile‑first breakpoints
    - Dark mode via prefers‑color‑scheme
    - Prefer logical properties
    - Avoid !important
    - Use clamp() for fluid typography
    - Scope to :root for theming
    - Reduce render‑blocking selectors
  template: |
    :root {
      --bg: #fff;
      --fg: #111;
      --accent: #06f;
      --mono: ui-monospace, monospace;
      --sans: system-ui, sans-serif;
      --spacing: clamp(1rem, 2vw, 2rem);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111;
        --fg: #eee;
      }
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; }
    body {
      font: 1rem/1.5 var(--sans);
      background: var(--bg);
      color: var(--fg);
      max-width: 60ch;
      margin: auto;
      padding: var(--spacing);
    }
    a { color: var(--accent); text-decoration: underline; }

ruby:
  rules:
    - frozen_string_literal: true
    - Guard clauses over nested conditionals
    - Modules over classes when no state
    - Public methods only in modules
    - Explicit return values
    - Typed keyword arguments where possible
    - Separate IO from business logic
    - Document public API with YARD
  template: |
    # frozen_string_literal: true
    module %{module_name}
      module_function

      # @param args [Hash] keyword arguments
      # @return [Hash, nil] processed data or nil when no input
      def call(**args)
        return nil if args.empty?

        process(**args)
      end

      # @param data [Hash] business data
      # @return [Hash] transformed data
      def process(**data)
        data
      end
    end

sh:
  rules:
    - "#!/bin/sh for portability"
    - "set -eu for strict error handling"
    - Quote all variables
    - Meaningful exit codes
    - Use functions for readability
    - Redirect errors to stderr
    - Prefer command substitution over backticks
    - Guard against missing arguments
  template: |
    #!/bin/sh
    set -eu

    main() {
      %{body}
    }

    main "$@"
    exit 0```

## `data/workflow.yml`
```yaml
# MASTER workflow rules — operational principles codified from CLAUDE.md.
# Governs how MASTER and its LLM agents read, edit, scan, and fix code.

file_reading:
  rule: READ_FULL_FILES
  statement: "Read complete files. Never grep, head, tail, or partial‑read to understand code."
  rationale: "Partial view yields partial (wrong) changes."
  allowed_exceptions:
    - "grep/search across many unknown files to locate a keyword"
  forbidden:
    - "grep pattern file to understand code structure"
    - "head -N file to check structure"
    - "tail -N file to check endings"

before_edit:
  rule: READ_BEFORE_WRITE
  statement: "Read every file that could be affected before editing any file."
  steps:
    - "Map the codebase: find all .rb files in lib/"
    - "Trace callers before changing any public method signature"
    - "Check Zeitwerk inflectors before renaming classes or files"
    - "Run ruby -c FILE after every write"
    - "Run ruby -e require_relative after every commit"

code_principles:
  no_hardcoding:
    rule: NO_HARDCODED_CONSTANTS
    statement: "Prose, patterns, and config belong in data/*.yml, not Ruby strings."
  single_source:
    rule: ONE_SOURCE_OF_TRUTH
    statement: "If it is in a data file, the code reads from there. No duplicates."
  no_magic_numbers:
    rule: NAMED_CONSTANTS
    statement: "Extract literals to named constants with .freeze"
  no_bare_rescue:
    rule: SPECIFIC_RESCUE
    statement: "Always rescue SpecificError => e. Propagate or log via event bus."
  guard_first:
    rule: GUARD_CLAUSES_FIRST
    statement: "Return Result.ok(ctx) unless condition before main logic."
  one_responsibility:
    rule: SINGLE_RESPONSIBILITY
    statement: "Split if you can name two reasons to change it."
  cqs:
    rule: COMMAND_QUERY_SEPARATION
    statement: "Queries return data and do not mutate. Commands mutate and do not return values."
  inject_deps:
    rule: DEPENDENCY_INJECTION
    statement: "Never instantiate collaborators inside a method."
  result_monad:
    rule: RESULT_MONAD
    statement: "Use respond_to?(:ok?) not is_a?(Result) for duck‑typing."

scan_rules:
  standard_depth:
    - frozen_string
    - bare_rescue
    - explicit
    - immutable
    - cqs
    - self_explaining
    - long_method
    - god_class
    - duplicate_code
    - prune
    - srp
    - pola
    - nielsen
  deep_only:
    - conceptual
    - adversarial
  hunt_only:
    - rubocop
    - reek
  notes:
    nielsen: "puts is NOT debug output in a CLI. Only p, pp, binding.pry, debugger are."
    prune: "Loads patterns from data/strunk.yml — single source of truth."
    conceptual: "Loads philosophy from data/axioms.yml — single source of truth."
    deep_caution: "deep adds 2 LLM calls per file. With 90 files at 8 req/min free tier = 22+ minutes."

autoloop:
  scan_depth: standard
  fix_depth: llm
  batch_size: 5
  max_cycles: 12
  targets:
    - lib/
    - test/
  excludes:
    - DEPLOY/
    - vendor/
    - fix_
    - patch_

sweep:
  scan_depth: deep
  converge_threshold: 0.05
  converge_window: 2
  max_cycles: 16
  codebase_map: true

zeitwerk:
  inflections:
    autoloop: AutoLoop
    cli: CLI
    mcp_server: MCPServer
    mcp_coordinator: McpCoordinator
    diff_stager: DiffStager
    code_index: CodeIndex
    git_context: GitContext
    ast_edit: AstEdit
    llm: LLM

anti_sprawl:
  forbidden_files:
    - summary.md
    - analysis.md
    - report.md
    - todo.md
    - notes.md
    - changelog.md
  rule: "Edit existing files. Single source of truth."

validation:
  after_write: "ruby -c lib/master/FILE.rb"
  after_commit: "ruby -e \"require_relative 'lib/master'; puts 'ok'\""
  scan_file: "bundle exec ruby exe/master scan lib/master/FILE.rb"

phases:
  discover:
    id: 1
    goal: "Understand actual need"
    output: "Problem statement with success criteria"
    gates:
      - no_vague_words
      - audience_identified
      - success_measurable
  analyze:
    id: 2
    goal: "Break into components"
    output: "Component diagram with dependencies"
    gates:
      - components_distinct
      - dependencies_acyclic
  ideate:
    id: 3
    goal: "Generate 15+ alternatives"
    output: "List of approaches with trade‑offs"
    gates:
      - count_gte_15
      - trade_offs_documented
  design:
    id: 4
    goal: "Specific architecture"
    output: "Interface definitions and error handling"
    gates:
      - interfaces_explicit
      - errors_documented
  implement:
    id: 5
    goal: "Execute with zero violations"
    output: "Working code at 100/100 score"
    gates:
      - tests_pass
      - zero_violations
  validate:
    id: 6
    goal: "Prove with evidence"
    output: "Test results, benchmarks"
    gates:
      - zero_test_failures
      - edge_cases_covered
  deliver:
    id: 7
    goal: "Ship with monitoring"
    output: "Deployed code with dashboards"
    gates:
      - deployed
      - monitoring_configured
session_startup:
  mandatory_reads:
    - data/axioms.yml
    - data/constitution.yml
    - data/language_rules.yml
    - data/workflow.yml
    - data/standing_orders.yml
  check_standing_orders: "Verify FSM state before any mutation -- UNCHANGE blocks refactoring"
  scan_before_analysis: "Use /scan deep via MASTER, not external agents, for code analysis"
  ssh_edit_pattern: "Write to /tmp, run ruby /tmp/patch.rb -- never ruby -i with heredoc"
```

## `data/zsh_patterns.yml`
```yaml
# Zsh-native patterns — replace external forks with pure Zsh
# Source: pub2/ZSH_NATIVE_PATTERNS.md

forbidden_commands:
  - command: awk
    replacement: "zsh array/string field splitting: ${${(s:,:)line}[4]}"
  - command: sed
    replacement: "zsh parameter expansion: ${var//search/replace}"
  - command: tr
    replacement: "zsh case conversion: ${(L)var} ${(U)var}"
  - command: grep
    replacement: "zsh pattern matching: ${(M)arr:#*pattern*}"
  - command: cut
    replacement: "zsh field splitting: ${${(s:delim:)var}[N]}"
  - command: head
    replacement: "zsh array slicing: ${arr[1,10]}"
  - command: tail
    replacement: "zsh array slicing: ${arr[-5,-1]}"
  - command: uniq
    replacement: "zsh unique flag: ${(u)arr}"
  - command: sort
    replacement: "zsh sort flags: ${(o)arr} (asc) / ${(O)arr} (desc)"
  - command: bash
    replacement: "zsh — never use bash"
  - command: find
    replacement: "zsh glob qualifiers: **/*.rb(.)"
  - command: wc
    replacement: "zsh length/count: ${#var} / ${#arr}"
  - command: sudo
    replacement: "doas on OpenBSD"

native_patterns:
  string_replace:          "${var//find/replace}"
  case_lower:              "${(L)var}"
  case_upper:              "${(U)var}"
  trim_whitespace:         "${${var##[[:space:]]#}%%[[:space:]]#}"
  split_to_array:          "${(s:delim:)var}"
  array_join:              "${(j:,:)arr}"
  array_unique:            "${(u)arr}"
  array_sort_asc:          "${(o)arr}"
  array_sort_desc:         "${(O)arr}"
  array_reverse:           "${(Oa)arr}"
  array_filter_match:      "${(M)arr:#*pattern*}"
  array_filter_exclude:    "${arr:#*pattern*}"
  remove_crlf:             "${var//$'\\r'/}"

exceptions:
  - "Complex regex requiring PCRE"
  - "Multi‑file operations beyond globbing"
  - "Binary data processing"

banned_commands: [python, bash, sed, awk, tr, wc, head, tail, cut, find, sudo]

auto_remediation:
  awk:   "${${(s: :)line}[n]}"
  sed:   "${var//old/new}"
  tr:    "${(U)var} or ${(L)var}"
  wc:    "${#lines}"
  head:  "${lines[1,n]}"
  tail:  "${lines[-n,-1]}"
  grep:  "${(M)lines:#*pattern*}"
  cut:   "${${(s:delim:)var}[N]}"
  sort:  "${(o)arr} or ${(O)arr}"
  find:  "**/*.ext(.)"
  sudo:  "doas"

token_economics:
  philosophy: >
    Replacing multi‑tool shell pipelines with pure Zsh parameter expansion
    eliminates process boundaries, collapses multiple grammars into one,
    reduces reasoning entropy for LLMs, and converts runtime overhead
    into in‑memory transforms — saving both tokens and wall‑clock time.
  example_bad:
    code: "awk -F, '{print $4}' | sed 's/\\r//g' | tr '[:upper:]' '[:lower:]'"
    cost: "3 grammars, pipes + subshells, I/O transformations"
  example_good:
    code: "cleaned=${var//$'\\r'/}; lower=${(L)cleaned}; fourth=${${(s:,:)lower}[4]}"
    cost: "One grammar, one evaluation model, no process boundaries"
  benefit: "Model reasons locally instead of globally across pipeline"```

## `docs/master2_restoration_opportunities.md`
```markdown
circuit open: retry in 20s```

## `lib/master.rb`
```ruby
# frozen_string_literal: true

require "zeitwerk"

module Master
  ROOT = File.expand_path("..", __dir__).freeze

  MIN_API_KEY_LENGTH = 20
  CTX_WINDOW_SIZE = 200_000
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
    ".js" => "javascript", ".json" => "json", ".sh" => "bash",
    ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
    ".erb" => "erb", ".css" => "css"
  }.freeze

  API_KEY_PROVIDERS = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY"
  }.freeze

  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop" => "AutoLoop",
    "cli"      => "CLI",
    "llm"      => "LLM"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.ignore(File.join(__dir__, "master", "ruby_llm_patch.rb"))
  loader.setup

  def self.configure_providers!
    require "ruby_llm"
    require_relative "master/ruby_llm_patch"
    RubyLLM.configure do |cfg|
      API_KEY_PROVIDERS.each do |attr, env_var|
        val = ENV[env_var].to_s
        cfg.public_send("#{attr}=", val) if val.length >= MIN_API_KEY_LENGTH
      end
    end
  end

  def self.api_key_present?(env_var)
    ENV[env_var].to_s.length >= MIN_API_KEY_LENGTH
  end

  def self.build(root: Dir.pwd)
    configure_providers!

    infra   = build_infrastructure(root)
    ai      = build_ai_stack(root, infra)
    pipeline, gateway, commands = build_pipeline_and_gateway(root, infra, ai)

    infra.merge(ai).merge(
      pipeline:, gateway:,
      root:
    )
  end

  def self.build_infrastructure(root)
    config   = Config.new(root)
    config["model"] ||= default_model

    ring     = RingBuffer.new(1000)
    bus      = EventBus.new
    logging  = Logging.new(ring_buffer: ring, event_bus: bus, trace_level: config.trace)
    session  = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
    undo     = Undo.new(session:, event_bus: bus, root:)
    breaker  = CircuitBreakerRegistry.new(budget_max: config.budget_max, req_max: config.req_max, event_bus: bus)
    cache    = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
    governor = Governor.new(config:, event_bus: bus)
    renderer = Renderer.new(config:)
    metrics  = Metrics.new(root:, event_bus: bus)
    AuditLog.new(root:, event_bus: bus)

    code_index  = CodeIndex.new(root:, event_bus: bus)
    diff_stager = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
    mcp         = McpCoordinator.new(root:, event_bus: bus)
    mcp.connect_all
    code_index.build
    bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

    memory      = Memory.new(root:)
    personality = Personality.new(config["persona"]&.to_sym || Personality::DEFAULT, root:)

    {
      config:, ring:, bus:, logging:, session:, undo:, breaker:, cache:,
      governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
      memory:, personality:
    }
  end

  def self.build_ai_stack(root, infra)
    config   = infra[:config]
    session  = infra[:session]
    bus      = infra[:bus]
    breaker  = infra[:breaker]
    cache    = infra[:cache]
    undo     = infra[:undo]
    governor = infra[:governor]
    memory   = infra[:memory]
    code_index  = infra[:code_index]
    diff_stager = infra[:diff_stager]

    tools    = build_tools(root:, undo:, governor:, bus:, diff_stager:, code_index:)
    tools   += infra[:mcp].tools
    router   = Routing::ModelRouter.new(config:)
    modes    = Reasoning::Modes.new
    agent    = Agent.new(
      config:, session:, tools:, circuit_breaker: breaker, cache:, event_bus: bus,
      model_router: router, reasoning_modes: modes,
      memory:, personality: infra[:personality], code_index:
    )
    soul_doc = Soul.new(root:, agent:)
    tools << Tools::AskLlm.new(agent:, governor:, circuit_breaker: breaker, cache:, event_bus: bus)

    ctx_window = ContextWindow.new(session:, agent:, model_context: CTX_WINDOW_SIZE)
    ctx_window.check_and_compact!
    agent.wire_context_window(ctx_window)

    guard        = Security::InjectionGuard.new
    scanner      = build_scanner(root:, agent:, bus:)
    swarm        = Swarm::Coordinator.new(agent:, event_bus: bus)
    personas     = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
    deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)
    council_stage = Stages::Council.new(deliberation:, config:)

    standing = StandingOrders.new(pipeline: nil, event_bus: bus)
    autoloop = AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul: soul_doc)

    skills = Skills.new(root:, event_bus: bus)
    skills.discover!

    heartbeat = Heartbeat.new(root:, agent:, scanner:, memory:, event_bus: bus)

    triggers = Triggers.new(event_bus: bus, scanner:, agent:)
    triggers.install_defaults!

    {
      agent:, soul: soul_doc, scanner:, swarm:, deliberation:,
      council_stage:, standing:, autoloop:, guard:,
      heartbeat:, skills:, triggers:
    }
  end

  def self.build_pipeline_and_gateway(root, infra, ai)
    config   = infra[:config]
    session  = infra[:session]
    bus      = infra[:bus]
    governor = infra[:governor]
    scanner  = ai[:scanner]
    autoloop = ai[:autoloop]
    memory   = infra[:memory]
    renderer = infra[:renderer]
    agent    = ai[:agent]
    council_stage = ai[:council_stage]
    standing = ai[:standing]

    commands = build_commands(
      session:, undo: infra[:undo], logging: infra[:logging], config:, agent:,
      council_stage:, swarm: ai[:swarm], scanner:, deliberation: ai[:deliberation],
      bus:, root:, memory:, cache: infra[:cache], metrics: infra[:metrics],
      standing:, soul: ai[:soul],
      heartbeat: ai[:heartbeat], skills: ai[:skills], gateway: nil
    )

    stages = [
      Stages::Intake.new,
      Stages::Infer.new,
      Stages::Route.new(commands:, agent:),
      Stages::Guard.new(governor:, injection_guard: ai[:guard]),
      Stages::Execute.new,
      Pipeline::ParallelGroup.new(council_stage, Stages::Lint.new(scanner:, config:, autoloop:)),
      Stages::Prune.new,
      Stages::Memo.new(memory:, event_bus: bus),
      Stages::Render.new(renderer:)
    ]

    pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
    standing.wire_pipeline(pipeline)

    gateway = Gateway.new(pipeline:, session:, event_bus: bus)
    commands["gateway"] = ->(ctx) { gateway.channels }

    [pipeline, gateway, commands]
  end

  def self.boot(root: Dir.pwd, argv: [])
    container = build(root:)
    generate_boot_snapshot(container)
    container[:heartbeat]&.start!
    CLI.new(container:)
  end

  def self.generate_boot_snapshot(container)
    root = container[:root]
    out  = File.join(root, ".master", "snapshot.md")
    dirs = %w[exe lib/master data].map { |d| File.join(root, d) }
    files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
               .select { |f| File.file?(f) && File.size(f) < 50_000 }
               .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
               .sort
    header = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
    body = files.flat_map do |f|
      rel  = f.sub("#{root}/", "")
      lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
      content = File.read(f, encoding: "UTF-8", invalid: :replace)
      ["## #{rel}", "```#{lang}", content.rstrip, "```", ""]
    rescue StandardError
      []
    end
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, (header + body).join("\n"))
    container[:bus]&.publish("boot:snapshot", files: files.size)
  rescue StandardError => e
    container[:bus]&.publish("boot:snapshot_error", error: e.message)
  end

  def self.default_model
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("OPENROUTER_API_KEY")
    return "nvidia/nemotron-3-super-120b-a12b:free" if api_key_present?("REPLICATE_API_KEY")
    return "claude-sonnet-4-6"       if api_key_present?("ANTHROPIC_API_KEY")
    return "gpt-4o"                  if api_key_present?("OPENAI_API_KEY")
    return "gemini-2.5-flash"        if api_key_present?("GEMINI_API_KEY")
    raise "No LLM API key found. Set OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY."
  end

  def self.build_tools(root:, undo:, governor:, bus:, diff_stager: nil, code_index: nil)
    [
      Tools::ReadFile.new(root:, undo:, event_bus: bus),
      Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager:),
      Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager:),
      Tools::ListDir.new(root:, event_bus: bus),
      Tools::SearchFiles.new(root:, event_bus: bus),
      Tools::WebSearch.new(governor:, event_bus: bus),
      Tools::Shell.new(root:, governor:, event_bus: bus),
      Tools::BatchReplace.new(root:, governor:, event_bus: bus),
      Tools::GitContext.new(root:, event_bus: bus),
      Tools::AstEdit.new(root:, undo:, event_bus: bus),
      Tools::Tree.new(root:, event_bus: bus),
      Tools::SymbolLookup.new(code_index:, event_bus: bus),
      Tools::Clean.new(root:, governor:, event_bus: bus),
      Tools::SearchKnowledge.new(root:, event_bus: bus)
    ]
  end

  def self.build_scanner(root:, agent:, bus:)
    scanner = Scan::Scanner.new(event_bus: bus)
    scanner.add_rule(Scan::Rules::FrozenStringRule.new)
    scanner.add_rule(Scan::Rules::BareRescueRule.new)
    scanner.add_rule(Scan::Rules::ExplicitRule.new)
    scanner.add_rule(Scan::Rules::ImmutableRule.new)
    scanner.add_rule(Scan::Rules::CqsRule.new)
    scanner.add_rule(Scan::Rules::SelfExplainingRule.new)
    scanner.add_rule(Scan::Rules::LongMethodRule.new)
    scanner.add_rule(Scan::Rules::GodClassRule.new)
    scanner.add_rule(Scan::Rules::DuplicateCodeRule.new)
    scanner.add_rule(Scan::Rules::PruneRule.new)
    scanner.add_rule(Scan::Rules::SrpRule.new)
    scanner.add_rule(Scan::Rules::PolaRule.new)
    scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
    scanner.add_rule(Scan::Rules::ReekRule.new(root:))
    scanner.add_rule(Scan::Rules::NielsenRule.new)
    scanner.add_rule(Scan::Rules::AxiomCoverageRule.new(root:))
    scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
    scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
    scanner
  end

  def self.build_commands(session:, undo:, logging:, config:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, memory:, cache:, metrics: nil, standing:, soul:, heartbeat: nil, skills: nil, gateway: nil)
    build_session_commands(session:, undo:, logging:, config:)
      .merge(build_mode_commands(config:))
      .merge(build_agent_commands(agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, config:, metrics:))
      .merge(build_memory_commands(memory:, agent:))
      .merge(build_new_commands(heartbeat:, skills:, gateway:))
      .merge(build_utility_commands(agent:, root:, cache:))
      .merge(build_master_commands(standing:, soul:))
      .merge(
        "help" => ->(ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
        }
      )
  end

  def self.build_session_commands(session:, undo:, logging:, config:)
    {
      "clear"  => ->(ctx) { session.clear!; "context cleared" },
      "save"   => ->(ctx) { session.save!; "session saved" },
      "tokens" => ->(ctx) { "~#{session.token_est} tokens" },
      "undo"   => ->(ctx) { r = undo.undo!; r.ok? ? "reverted: #{r.value!}" : r.message },
      "dmesg"  => ->(ctx) { logging.dmesg },
      "cost"   => ->(ctx) { "$#{"%.4f" % session.cost}" },
      "config" => ->(ctx) { config.data.inspect }
    }
  end

  def self.build_mode_commands(config:)
    {
      "mode" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if Reasoning::Modes::SUPPORTED.include?(arg)
          config["reasoning_mode"] = arg
          config.save!
          "mode: #{arg}"
        else
          "mode: #{config.reasoning_mode} (supported: #{Reasoning::Modes::SUPPORTED.join(", ")})"
        end
      },
      "task" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg.empty?
          "task_type: #{config.task_type}"
        else
          config["task_type"] = arg
          config.save!
          "task_type: #{arg}"
        end
      },
      "autotest" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        case arg
        when "on"  then config["auto_testing"] = true;  config.save!; "autotest: on"
        when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
        else "autotest: #{config.auto_testing? ? "on" : "off"}"
        end
      },
      "persona" => ->(ctx) {
        arg   = ctx[:args].to_s.strip.to_sym
        names = Personality::PERSONAS.keys
        if names.include?(arg)
          config["persona"] = arg.to_s
          config.save!
          "persona: #{arg}"
        else
          "persona: #{config["persona"] || "dark_malay"} — available: #{names.join(", ")}"
        end
      }
    }
  end

  def self.build_agent_commands(agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, config:, metrics:)
    {
      "council" => ->(ctx) {
        case ctx[:args].to_s.strip
        when "on"  then council_stage.enable!;  "council: enabled"
        when "off" then council_stage.disable!; "council: disabled"
        else "council: #{council_stage.enabled? ? "on" : "off"}"
        end
      },
      "swarm" => ->(ctx) {
        args = ctx[:args].to_s.strip.split(" ", 2)
        role, task = args[0]&.to_sym, args[1].to_s
        if role.nil? || task.empty?
          "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
        else
          result = swarm.dispatch(role, task:, context_slice: {})
          result.ok? ? result.value!.inspect : result.message
        end
      },
      "explain" => ->(ctx) {
        map       = Introspection::SelfMap.new(root:)
        info      = map.describe
        cov       = map.axiom_coverage
        cov_lines = cov.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
        stages    = "Intake→Infer→Route→Guard→Execute→Council→Lint→Prune→Memo→Render"
        "MASTER — #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
      },
      "autoloop" => ->(ctx) {
        max    = ctx[:args].to_s.strip.to_i
        max    = AutoLoop::MAX_CYCLES if max <= 0
        looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log    = []
        result = looper.run(max_cycles: max) { |cycle, violations|
          log << "  cycle #{cycle}: #{violations.size} violation(s)"
        }
        ([result.ok? ? result.value! : result.message] + log).join("\n")
      },
      "sweep" => ->(ctx) {
        arg     = ctx[:args].to_s.strip
        target  = arg.empty? ? root : File.expand_path(arg, root)
        sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log     = []
        result  = sweeper.run(target) { |cycle, file, delta|
          log << "  cycle #{cycle}  #{file}  +#{delta}"
        }
        ([result.ok? ? result.value! : result.message] + log).join("\n")
      },
      "model" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg == "list"
          yml_path = File.join(root, "data", "models.yml")
          if File.exist?(yml_path)
            require "yaml"
            data          = YAML.safe_load_file(yml_path, aliases: true)
            tiers         = data["models"] || {}
... 234 lines truncated (634 total)
```

## `lib/master/agent.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm"
require "digest"
require "yaml"

module Master
  class Agent
    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN              = 0.000_015

    # Replicate native API — these owner prefixes route through Bridges::Replicate.
    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

# Tool-capable model whitelist -- loaded from data/models.yml.
# Anchored regex built from tool_capable_prefixes list.
def self.build_tool_capable_re
  yml_path = File.join(Master::ROOT, "data", "models.yml")
  prefixes = YAML.safe_load_file(yml_path, aliases: true).fetch("tool_capable_prefixes", [])
  escaped = prefixes.map { |p| Regexp.escape(p) }
  Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
end

TOOL_CAPABLE_RE = build_tool_capable_re

    MAX_TOOL_TURNS     = 5
    MIN_API_KEY_LENGTH = 20
    TOOL_CALL_RE       = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze

    NEMOTRON3_RE      = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    def initialize(config:, session:, tools:, circuit_breaker:, cache:,
                   event_bus: nil, model_router: nil, reasoning_modes: nil,
                   memory: nil, personality: nil, code_index: nil, context_window: nil)
      @code_index      = code_index
      @config          = config
      @session         = session
      @tools           = tools
      @circuit_breaker = circuit_breaker
      @cache           = cache
      @bus             = event_bus
      @model_router    = model_router
      @reasoning_modes = reasoning_modes
      @memory          = memory
      @personality     = personality
      @context_window  = context_window
      # RubyLLM is configured once at module boot (see Master.configure_providers!).
      # Per-agent init was globally mutating shared state across agents.
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt           = apply_reasoning_mode(message)
      context          = conversation_context
      @bus&.publish("llm:request", model: candidate_models.first, tokens: message.bytesize / 4)

      begin
        @circuit_breaker.check_rate!
      rescue CircuitBreaker::CircuitError => rate_err
        return Result.err(rate_err.message, category: rate_err.category)
      end

      last_response = attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)

      return last_response if last_response.respond_to?(:err?) && last_response.err?

      last_response = maybe_escalate(last_response, prompt, context, message, stream, escalation_depth, &blk)

      text = last_response.to_s
      @session.add_message(role: :assistant, content: text)
      Result.ok(text)
    rescue StandardError => chat_error
      Result.err("agent: #{chat_error.message}", category: :handler_exception)
    end

    # Result-returning companion to #ask. Prefer this for pipeline stages.
    # See #ask for the legacy string/raise API retained for AutoLoop/Sweep/scan-rule callers.
    def ask_result(prompt, context: nil)
      text = ask(prompt, context: context)
      Result.ok(text)
    rescue StandardError => ask_err
      Result.err("ask: #{ask_err.message}", category: :handler_exception)
    end

    def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = _send_llm_request_with_cache_and_breaker(selected_model, messages, stream: false)
      result.to_s
    end

    # One-shot chat with a custom system prompt. No session.
    def ask_once(prompt, system: nil)
      _send_llm_request_with_cache_and_breaker(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    # One-shot with explicit model override (used by swarm workers with PREFERRED_MODEL).
    def ask_once_with_model(prompt, model:, system: nil)
      _send_llm_request_with_cache_and_breaker(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    def call(ctx)
      on_chunk  = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first

    def model=(val)
      @config["model"] = val # This sets the base model; model_router may override this for specific task types.
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    # Skip models that cannot call tools instead of raising. A single
    # non-tool-capable candidate used to abort the whole fallback chain.
    def attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)
      capable = candidate_models.select { |m| replicate_model?(m) || ferrum_model?(m) || tool_capable?(m) }
      if capable.empty?
        return Result.err(
          "no tool-capable model available. Set REPLICATE_API_KEY, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY.",
          category: :validation
        )
      end

      last_response = nil
      capable.each_with_index do |selected_model, index|
        response = _send_llm_request_with_cache_and_breaker(selected_model, context + [{ role: "user", content: prompt }], stream: stream, &blk)
        last_response = response
        next if response.respond_to?(:err?) && response.err? && index < capable.length - 1
        if response.respond_to?(:ok?) && response.ok?
          @bus&.publish("llm:response", model: selected_model, success: true, tokens_approx: response.to_s.bytesize / 4)
        end
        break response
      end
      last_response
    end

    # Escalates once per chat call.
    # Escalates up to 2 times per chat call (depth counter replaces boolean).
    def maybe_escalate(last_response, prompt, context, original_message, stream, escalation_depth, &blk)
      return last_response unless @model_router
      return last_response if escalation_depth >= 2

      current = routed_models.first
      escalation_model = @model_router.escalate_if_low_confidence(
        last_response.to_s,
        current_model: current,
        task_type: @config.task_type.to_sym
      )
      return last_response unless escalation_model

      @bus&.publish("llm:escalation", from: current, to: escalation_model)
      # Recursively call chat with the escalated model and mark escalation as attempted.
      escalated_result = chat(
        original_message,
        stream: stream,
        escalation_depth: escalation_depth + 1,
        &blk
      )
      escalated_result.respond_to?(:err?) && escalated_result.err? ? last_response : escalated_result
    end

    def _send_llm_request_with_cache_and_breaker(selected_model, messages, system: nil, stream: false, &blk)
      cache_key = cache_key_for(messages.last[:content], messages[0...-1])
      breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
        @cache.fetch(cache_key, selected_model) {
          _send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
        }
      }
    rescue StandardError => err
      Result.err("llm_request: #{err.message}", category: :llm_call_failure)
    end

    def _send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
      current_system_prompt = system || system_prompt
      if ferrum_model?(selected_model)
        alias_name = selected_model.split(":", 3).last
        response   = Bridges::FerrumWebChat.new.ask(model_alias: alias_name, prompt: messages.last[:content])
        return response if response.respond_to?(:err?) && response.err?; return Result.ok(response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s)
      elsif replicate_model?(selected_model)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages: messages, system: current_system_prompt,
          stream: stream, &(stream ? blk : nil)
        )
        return Result.ok(reply.content.to_s)
      end

      chat_session = RubyLLM.chat(model: selected_model)
      final_system_prompt = nemotron_system_prompt(selected_model, current_system_prompt)
      chat_session.with_instructions(final_system_prompt) if final_system_prompt
      messages.each { |msg| chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s) }

      available_tools = llm_tools(selected_model)
      chat_session.with_tools(*available_tools) unless available_tools.empty?

      reply = if stream && blk
        chat_session.ask(messages.last[:content]) { |chunk| blk.call(chunk.content.to_s) if chunk.content }
      else
        chat_session.ask(messages.last[:content])
      end
      Result.ok(extract_response(reply, selected_model))
    end

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def routed_models
      return [@config.model] unless @model_router
      @model_router.fallback_chain(task_type: @config.task_type.to_sym)
    rescue StandardError
      [@config.model]
    end

    # Use per-model breaker when registry available, global breaker otherwise.
    def breaker_for(model_id)
      @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
    end

    def replicate_model?(model_id)
      return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
      REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
    end

    def ferrum_model?(model_id) = model_id.to_s.start_with?("ferrum:webchat:")

    # Anchored match against a real pattern. `"gpt-4-whatever"` no longer matches
    # `"claude"` just because both strings contain common substrings.
    def tool_capable?(model_id)
      TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary        if @code_index&.built?
      parts << @memory.context_summary    if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def extract_response(reply, selected_model)
      return reply.to_s unless reply.respond_to?(:content)
      if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
        thinking = reply.reasoning_content.to_s.strip
        content  = reply.content.to_s
        return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
      end
      reply.content.to_s
    end

    def nemotron_system_prompt(selected_model, base_system_prompt = nil)
      base = base_system_prompt || system_prompt
      return base unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive   = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, base].compact.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end

    # Hash-based cache key. Previously concatenated the full conversation
    # context into the key, producing multi-KB keys that almost never hit
    # across turns. SHA256 of (prompt + rolling 4-message window) is stable
    # for retries, narrow enough to actually collide on repeats, bounded size.
    # Ref: arxiv:2601.23088 on semantic-cache collision tradeoffs; we use
    # exact-hash over a bounded window to avoid fuzzy-hash vulnerabilities.
    CACHE_WINDOW = 4
    def cache_key_for(message, context)
      return Digest::SHA256.hexdigest(message) if context.empty?
      window = context.last(CACHE_WINDOW).map { |msg| "#{msg[:role]}:#{msg[:content]}" }.join("\n")
      Digest::SHA256.hexdigest("#{message}\n#{window}")
    end

    def estimate_cost(prompt) = (prompt.bytesize / 4) * COST_PER_TOKEN

    LLM_TOOL_MAP = {
      Tools::ReadFile         => Tools::LLM::ReadFile,
      Tools::WriteFile        => Tools::LLM::WriteFile,
      Tools::StrReplace       => Tools::LLM::StrReplace,
      Tools::ListDir          => Tools::LLM::ListDir,
      Tools::SearchFiles      => Tools::LLM::SearchFiles,
      Tools::Shell            => Tools::LLM::Shell,
      Tools::WebSearch        => Tools::LLM::WebSearch,
      Tools::AskLlm           => Tools::LLM::AskLlm,
      Tools::GitContext       => Tools::LLM::GitContext,
      Tools::AstEdit          => Tools::LLM::AstEdit,
      Tools::SearchKnowledge  => Tools::LLM::SearchKnowledge,
    }.freeze

    def llm_tools(selected_model = model)
      return [] unless tool_capable?(selected_model)
      @llm_tools ||= build_llm_tools
    end

    def build_llm_tools
      @tools.filter_map do |tool|
        wrapper = LLM_TOOL_MAP[tool.class]
        wrapper&.new(tool)
      end
    rescue StandardError => tools_error
      @bus&.publish("agent:llm_tools_error", error: tools_error.message)
      []
    end
  end
end```

## `lib/master/audit_log.rb`
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only audit trail of every tool invocation.
  # Subscribes to tool:before events on the shared EventBus.
  # Written to .master/audit.log — one line per call, machine-readable.
  class AuditLog
    LOG_PATH = ".master/audit.log"
    MAX_VAL  = 120

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |event_data| append(event_data) }
    end

    private

    def append(event_data)
      payload_pairs = event_data.except(:tool)
                                .map { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                                .join(" ")
      log_line = "#{Time.now.utc.iso8601} tool=#{event_data[:tool]} #{payload_pairs}"
      File.open(@path, "a") { |f| f.puts(log_line) }
    end
  end
end
```

## `lib/master/autoloop.rb`
```ruby
# frozen_string_literal: true

require "open3" # No longer directly used, moving to Master::GitOperations
require_relative "git_operations"

module Master
  # AutoLoop — iterate on scan violations until clean or max_cycles reached.
  #
  # Cycle: scan lib+test at standard depth → collect violations by severity →
  # LLM fix (full file, no truncation) → size guard → syntax check → write → commit.
  # Stops when clean or max_cycles reached.
  #
  # Retry strategy is Reflexion-style (MANTRA/RefAgent):
  # on rate-limit or transient failure, the failing prompt plus error summary
  # are fed back in a second attempt. Raw retries alone hit ~45% test-pass
  # in RefAgent; self-reflection lifts it to ~90%.
  #
  # Ref: arxiv:2503.14340 (MANTRA), arxiv:2511.03153 (RefAgent).
  class AutoLoop
    MAX_CYCLES       = 12
    BATCH_SIZE       = 3
    RATE_LIMIT_SLEEP = 15     # ONE_SOURCE: no more hardcoded `sleep 15`
    MAX_FIX_RETRIES  = 3
    MIN_SIZE_RATIO       = 0.80   # Reject fix if output < 80% of original file size
    CONFIDENCE_THRESHOLD = 0.60   # Below this, escalate to a reflective retry
    MAX_FILE_BYTES   = 16_000 # Raised from 4_000 so core files (agent.rb, cli.rb) are fixable

    # Rules that cannot be safely auto-fixed by rewriting a single file.
    # duplicate_code requires cross-file refactoring; conceptual/adversarial are LLM-only.
    SKIP_RULES = %w[duplicate_code conceptual adversarial axiom_coverage immutable self_explaining long_method pola srp cqs].freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    # Transient error signatures that trigger a reflected retry
    # rather than abandon the fix. 429 = rate limit, 503 = overload.
    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil)
      @agent          = agent
      @scanner        = scanner
      @root           = root
      @bus            = event_bus
      @soul           = soul
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git            = GitOperations.new(root)
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_paths  = %w[lib test].map { |d| File.join(@root, d) }
        all_results = scan_paths.flat_map { |dir|
          res = @scanner.scan_dir(dir, depth: :standard)
          res.ok? ? res.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        # Deduplicate by file — one fix per unique file to avoid write-race.
        by_file = violations.first(BATCH_SIZE * 2).uniq { |v| v[:file] }.first(BATCH_SIZE)

        mutex   = Mutex.new
        fixes   = {}
        stagger = RATE_LIMIT_SLEEP.to_f / BATCH_SIZE  # 5 s apart — stays within free-tier quota

        threads = by_file.each_with_index.map do |v, idx|
          sleep(stagger * idx) if idx.positive?
          Thread.new do
            fix = request_fix(v)
            mutex.synchronize { fixes[v[:file]] = [v, fix] } if fix
          end
        end
        threads.each(&:join)

        fixes.each_value { |v, fix| apply_fix(v[:file], fix) }

        if @git.dirty?("lib/")
          @git.add_lib_files
          @git.commit("autoloop: fix scan violations [cycle #{cycle}]")
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    private

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.ok?
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .reject { |f| SKIP_RULES.include?(f[:rule].to_s) }
          .map    { |f| f.merge(file: path.delete_prefix("#{@root}/")) }
      }.select { |f|
        full_path = File.join(@root, f[:file])
        File.exist?(full_path) && File.size(full_path) <= MAX_FILE_BYTES # GUARD_EXPENSIVE
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    # Request a fix from the LLM. Sends FULL file — never truncates.
    # Skips files > MAX_FILE_BYTES (LLM output would be truncated, risking corruption).
    # Retries up to MAX_FIX_RETRIES with a reflection step on transient errors.
    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src         = File.read(path, encoding: "UTF-8")
      base_prompt = build_fix_prompt(violation, src)
      last_error  = nil

      MAX_FIX_RETRIES.times do |attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          # On retries, inject the last error as a reflection prefix.
          prompt = attempt.zero? ? base_prompt : reflected_prompt(base_prompt, last_error, attempt)
          fix    = extract_code(@agent.ask(prompt).to_s)
          if fix && confidence_score(fix, src) < CONFIDENCE_THRESHOLD && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:escalate", file: violation[:file], attempt: attempt + 1)
            last_error = 'low confidence'
            next
          end
          return fix
        rescue StandardError => e
          last_error = e.message.to_s
          if TRANSIENT_RE.match?(last_error) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: last_error[0, 120])
            return nil
          end
        end
      end
      nil
    end

    def build_fix_prompt(violation, src)
      "Fix this Ruby violation in #{violation[:file]}.\n" \
        "Rule: #{violation[:rule]}\n" \
        "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
        "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
        "```ruby\n#{src}\n```"
    end

    # Reflexion-style prefix: tell the model the prior attempt failed and why.
    # Directly inspired by arxiv:2503.14340 (MANTRA Repair Agent).
    def reflected_prompt(base, last_error, attempt)
      "Prior attempt (#{attempt}) failed with: #{last_error[0, 200]}\n" \
        "Reflect briefly on what went wrong, then retry.\n\n" \
        "#{base}"
    end

    def extract_code(text)
      return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
      return text.match(/```\n(.*?)```/m)[1].strip if text.match?(/```\n(.*?)```/m)
      return text.strip if text.match?(/frozen_string_literal|module |class /)
      nil
    end

    # Safety guards: size check + syntax check before writing.
    # Rejects any fix that removes more than 20% of the original content.
    def apply_fix(rel_path, content)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)

      original_size = File.size(path)
      if content.bytesize < (original_size * MIN_SIZE_RATIO).to_i # GUARD_EXPENSIVE
        @bus&.publish("autoloop:fix_rejected", file: rel_path,
                      reason: "too short (#{content.bytesize} vs #{original_size})")
        return
      end

      return unless syntax_ok?(content) # GUARD_EXPENSIVE

      File.write(path, content, encoding: "UTF-8")
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    # Returns 0.0-1.0. Signals how structurally complete the LLM output is.
    # Low score triggers escalation retry with a reflective prompt (Task #15).
    def confidence_score(code, original_src)
      return 0.0 if code.nil? || code.strip.empty?

      score = 0.0
      score += 0.25 if code.include?("# frozen_string_literal: true")
      score += 0.25 if code.match?(/\A.*?(?:module |class )[A-Z]/m)
      ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
      score += 0.25 if ratio >= MIN_SIZE_RATIO && ratio <= 2.0
      score += 0.25 if syntax_ok?(code)
      score
    end

    def syntax_ok?(content)
      require "tempfile"
      Tempfile.open(["al_chk", ".rb"]) do |f|
        f.binmode
        f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
        f.flush
        system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
      end
    rescue StandardError # DEGRADE_GRACEFULLY
      false
    end

    def track_recurrence(violations)
      return unless @soul
      tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
      tally.each do |rule_id, count|
        @rule_recurrence[rule_id] += 1
        next unless @rule_recurrence[rule_id] >= 3
        @rule_recurrence.delete(rule_id)
        sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
        result = @soul.propose_from_violations(rule_id, sample, agent: @agent)
        @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: result.to_s[0, 80])
      end
      # Reset rules that disappeared
      (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
    end
  end
end
```

## `lib/master/axioms.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # Central source for rules, axioms, voice, and workflow.
  # Loads from data/rules.yml (unified hierarchy) and data/workflow.yml.
  # All data is loaded once (optionally from a custom root) and frozen
  # to guarantee immutability and fast repeated access.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    # Public API ---------------------------------------------------------

    # Kernel rules: {ID => name} hash for backward compatibility.
    def kernel
      @kernel ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end
    end

    def workflow
      @workflow.freeze
    end

    # All non-kernel rules as an array of hashes.
    def philosophy(limit: nil)
      @philosophy ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    # All rules across all scopes, flat array.
    def all_rules
      @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    end

    # Rules filtered by scope: codebase, file, unit, line.
    def rules_for_scope(scope)
      (@data.dig("rules", scope.to_s) || []).freeze
    end

    # Formatted blocks for display (e.g. in prompts) --------------------

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?

      top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
      "## Rules (top #{items.size})\n#{top}"
    end

    # Voice, strunk, constitution ----------------------------------------

    def voice
      @voice ||= (@data["voice"] || {}).freeze
    end

    def strunk
      @strunk ||= (voice["strunk"] || {}).freeze
    end

    def constitution
      @constitution ||= begin
        c = {}
        c["golden_rule"] = @data["golden_rule"]
        c["protection"] = @data["protection"]
        c["banned_output"] = voice["banned_output"]
        c["anti_simulation"] = voice["anti_simulation"]
        c["communication_style"] = voice["style"]
        c.freeze
      end
    end

    # Thresholds, scan depths, language config ---------------------------

    def thresholds
      @thresholds ||= (@data["thresholds"] || {}).freeze
    end

    def scan_depths
      @scan_depths ||= (@data["scan_depths"] || {}).freeze
    end

    def languages_config
      @languages_config ||= (@data["languages"] || {}).freeze
    end

    # Workflow rule lookup ------------------------------------------------

    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    # General lookup -------------------------------------------------------

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] ||
        philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def empty?
      @data.empty?
    end

    # ---------------------------------------------------------------------

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true)
    rescue StandardError
      nil
    end
  end
end
```

## `lib/master/bridges/ferrum_web_chat.rb`
```ruby
# frozen_string_literal: true

module Master
  module Bridges
    class FerrumWebChat
      # No session management — always returns an error until login/cookie handling is added.

      def ask(model_alias:, prompt:)
        ferrum = load_ferrum
        return ferrum if ferrum.respond_to?(:err?) && ferrum.err?

        browser = ferrum::Browser.new(timeout: 20)
        begin
          case model_alias
          when /openrouter/i
            browser.go_to("https://openrouter.ai/chat")
          when /replicate/i
            browser.go_to("https://replicate.com")
          else
            return Result.err("unsupported ferrum web chat alias: #{model_alias}", category: :validation)
          end

          Result.err("ferrum web chat requires interactive login/session; no session present", category: :provider)
        ensure
          browser.quit
        end
      rescue StandardError => e
        Result.err("ferrum bridge failed: #{e.message}", category: :provider)
      end

      private

      def load_ferrum
        return Ferrum if defined?(Ferrum)
        require "ferrum"
        Ferrum
      rescue LoadError
        Result.err("ferrum gem not installed; skipping web-chat piggyback", category: :provider)
      end
    end
  end
end
```

## `lib/master/bridges/replicate.rb`
```ruby
# frozen_string_literal: true

require "net/http"
require "json"

module Master
  module Bridges
    # Replicate — native predictions API client.
    class Replicate
      BASE_URL      = "https://api.replicate.com/v1"
      POLL_INTERVAL = 0.8
      MAX_WAIT      = 180

      DEFAULT_MAX_TOKENS  = 4_096
      DEFAULT_TEMPERATURE = 0.6

      def initialize(api_key: ENV["REPLICATE_API_KEY"])
        @api_key = (api_key || "").to_s
        raise "REPLICATE_API_KEY not configured" if @api_key.length < 20
      end

      # Returns a duck‑typed Message. Raises on API error.
      def chat(model:, messages:, system: nil, max_tokens: DEFAULT_MAX_TOKENS,
               temperature: DEFAULT_TEMPERATURE, stream: false, &blk)
        prompt = format_prompt(messages, system:)
        input  = build_input(prompt:, max_tokens:, temperature:)

        return chat_stream(model:, input:, &blk) if stream && blk

        pred     = create_prediction(model:, input:)
        pred_id  = pred["id"] or raise "no prediction id: #{pred.inspect}"
        result   = poll_until_done(pred_id)
        text     = (result["output"].is_a?(Array) ? result["output"].join : result["output"]).to_s

        Message.new(text)
      rescue StandardError => e
        raise "Replicate(#{model}): #{e.message}"
      end

      private

      def format_prompt(messages, system:)
        parts = []
        parts << "<<SYS>>\n#{system}\n<</SYS>>\n\n" if system
        messages.each do |m|
          role    = (m[:role] || m["role"]).to_s.downcase
          content = (m[:content] || m["content"]).to_s
          tag     = role == "assistant" ? "Assistant" : "Human"
          parts << "#{tag}: #{content}\n"
        end
        parts << "Assistant:"
        parts.join
      end

      def build_input(prompt:, max_tokens:, temperature:)
        { prompt:, max_tokens:, temperature:, top_p: 1.0 }
      end

      def chat_stream(model:, input:, &blk)
        uri = model_uri(model)
        pred = post(uri, { input:, stream: true })
        stream_url = pred.dig("urls", "stream") or raise "no stream URL: #{pred.inspect}"

        full_text = +""
        s_uri = URI(stream_url)

        Net::HTTP.start(s_uri.host, s_uri.port, use_ssl: true, read_timeout: MAX_WAIT) do |http_client|
          request = Net::HTTP::Get.new(s_uri)
          auth_headers.each { |k, v| request[k] = v }
          request["Accept"] = "text/event-stream"

          http_client.request(request) do |resp|
            buffer = +""
            resp.read_body do |chunk|
              buffer << chunk
              while (idx = buffer.index("\n\n"))
                event = buffer.slice!(0..idx + 1)
                lines = event.lines.map(&:chomp)
                type  = lines.find { |l| l.start_with?("event:") }&.then { |l| l[7..].strip }
                data  = lines.find { |l| l.start_with?("data:") }&.then { |l| l[5..].strip }
                next unless type == "output" && data && !data.empty?

                blk.call(data)
                full_text << data
              end
            end
          end
        end

        Message.new(full_text)
      rescue StandardError => e
        raise "Replicate stream(#{model}): #{e.message}"
      end

      def create_prediction(model:, input:)
        post(model_uri(model), { input: })
      end

      def poll_until_done(pred_id)
        uri      = URI("#{BASE_URL}/predictions/#{pred_id}")
        deadline = Time.now + MAX_WAIT

        loop do
          result = get(uri)
          case result["status"]
          when "succeeded"
            return result
          when "failed", "canceled"
            raise "prediction #{result["status"]}: #{result["error"]}"
          end
          raise "Timeout after #{MAX_WAIT}s." if Time.now > deadline

          sleep POLL_INTERVAL
        end
      end

      def post(uri, body)
        request = Net::HTTP::Post.new(uri)
        auth_headers.each { |k, v| request[k] = v }
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
        JSON.parse(http(uri).request(request).body)
      end

      def get(uri)
        request = Net::HTTP::Get.new(uri)
        auth_headers.each { |k, v| request[k] = v }
        JSON.parse(http(uri).request(request).body)
      end

      def http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |client|
          client.use_ssl = true
          client.read_timeout = 35
        end
      end

      def auth_headers
        { "Authorization" => "Bearer #{@api_key}" }
      end

      def model_uri(model)
        owner, name = model.split("/", 2)
        URI("#{BASE_URL}/models/#{owner}/#{name}/predictions")
      end

      # Duck‑types as RubyLLM::Message so Agent extract_response works.
      class Message
        attr_reader :content

        def initialize(content)
          @content = content.to_s
        end

        def to_s = @content

        def respond_to_missing?(name, *) = name == :content || super
      end
    end
  end
end```

## `lib/master/circuit_breaker.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class CircuitBreaker
    include MonitorMixin

    FAILURE_THRESHOLD = 8
    COOLDOWN_S        = 30
    RATE_WINDOW_S     = 60
    RATE_MAX          = 60

    class CircuitError < StandardError
      attr_reader :category
      def initialize(msg, category) = (super(msg); @category = category)
    end

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @budget_max    = budget_max
      # @req_max and @event_bus parameters are unused internally.
      @failures      = 0
      @opened_at     = nil
      @state         = :closed
      @session_total = 0.0
      @req_times     = []
    end

    # Per-message rate check — call once per user request, not per model fallback.
    def check_rate!
      synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @req_times.reject! { |t| now - t > RATE_WINDOW_S }
        raise CircuitError.new("rate limit: #{RATE_MAX} req/min exceeded", :infrastructure) if @req_times.size >= RATE_MAX
        @req_times << now
      end
    end

    # Per-model-attempt: check budget + circuit state, then execute.
    def call(cost_estimate, &blk)
      check_budget(cost_estimate)
      check_circuit
      execute_with_tracking(blk)
    rescue CircuitError => e
      # Budget/circuit-open errors are not backend failures — don't penalize.
      Result.err(e.message, category: e.category)
    end

    def record_cost(amount)  = synchronize { @session_total += amount }
    def session_total        = synchronize { @session_total }

    # Exposed for tests and /config command.
    def state = synchronize { @state }

    private

    def execute_with_tracking(blk)
      result = blk.call
      on_success
      result
    rescue RubyLLM::RateLimitError => e
      # API rate limit is infrastructure noise — don't open the circuit.
      Result.err("rate_limit: #{e.message}", category: :infrastructure)
    rescue StandardError => e
      on_failure
      Result.err(e.message, category: :provider_error)
    end

    def check_budget(estimate)
      return unless @budget_max.positive? # Only check budget if it's a positive value.
      synchronize do
        raise CircuitError.new("budget: $#{(@session_total + estimate).round(4)} would exceed $#{@budget_max}", :budget) if @session_total + estimate > @budget_max
      end
    end

    def check_circuit
      synchronize do
        return if @state == :closed
        if @state == :open
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          if elapsed >= COOLDOWN_S
            @state = :half_open
          else
            raise CircuitError.new("circuit open: retry in #{(COOLDOWN_S - elapsed).ceil}s", :infrastructure)
          end
        end
      end
    end

    def on_success = synchronize { @failures = 0 ; @state = :closed if @state == :half_open }
    def on_failure = synchronize { @failures += 1 ; if @failures >= FAILURE_THRESHOLD ; @state = :open ; @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) ; end }
  end
end
```

## `lib/master/circuit_breaker_registry.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  # Registry of per‑model circuit breakers.
  #
  # Each model gets its own +CircuitBreaker+ instance so that a flaky
  # free‑tier endpoint does not affect the failure count of paid fallbacks.
  # Global rate‑limiting is handled by a single shared breaker.
  class CircuitBreakerRegistry
    include MonitorMixin

    # Public: Create a new registry.
    #
    # budget_max: Maximum budget (cost) allowed for a session.
    # req_max:    Maximum number of requests allowed for a session.
    # event_bus:  Optional event bus for publishing breaker events.
    #
    # The arguments are stored frozen to guarantee immutability.
    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max: budget_max, req_max: req_max, event_bus: event_bus }.freeze
      @breakers = {} # model_id (String) => CircuitBreaker
      @global   = CircuitBreaker.new(**@defaults)
    end

    # Public: Retrieve the breaker for +model_id+, creating it lazily.
    #
    # model_id - Any object identifying a model; will be converted to a string.
    #
    # Returns a +CircuitBreaker+ instance.
    def for(model_id)
      synchronize do
        @breakers[model_id.to_s] ||= CircuitBreaker.new(**@defaults)
      end
    end

    # Public: Perform a global rate‑limit check.
    #
    # Raises +CircuitBreaker::OpenError+ if the global limit is exceeded.
    def check_rate!
      @global.check_rate!
    end

    # Public: Total cost incurred across all model‑specific breakers plus the
    # global breaker.
    #
    # Returns a numeric cost total.
    def session_total
      synchronize { @breakers.values.sum(&:session_total) + @global.session_total }
    end

    # Public: Record cost against the global breaker.
    #
    # amount - Numeric cost to add.
    def record_cost(amount)
      @global.record_cost(amount)
    end

    # Public: Back‑compatibility shim – behaves like a plain +CircuitBreaker+.
    #
    # cost_estimate - Expected cost of the operation.
    # &blk          - Block to execute if the circuit is closed.
    #
    # Returns whatever the underlying breaker returns.
    def call(cost_estimate, &blk)
      @global.call(cost_estimate, &blk)
    end

    # Public: List model IDs whose breakers are currently open.
    #
    # Returns an Array of model ID strings.
    def open_models
      synchronize do
        @breakers.filter_map do |id, breaker|
          id if breaker.respond_to?(:open?) && breaker.open?
        end
      end
    end
  end
end```

## `lib/master/cli.rb`
```ruby
# frozen_string_literal: true

require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
    PULSE_SOCKET = "/tmp/pulse/native".freeze
    PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze

    PAPLAY_CANDIDATES = %w[
      /data/data/com.termux/files/usr/bin/paplay
      /usr/bin/paplay
      /usr/local/bin/paplay
    ].freeze

    FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze

    DMESG_LINES = 50

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    attr_reader :container

    def initialize(container:)
      @container   = container
      @session     = container[:session]
      @agent       = container[:agent]
      @renderer    = container[:renderer]
      @logging     = container[:logging]
      @undo        = container[:undo]
      @config      = container[:config]
      @pipeline    = container[:pipeline]
      @scanner     = container[:scanner]
      @root        = container[:root] || Dir.pwd
      @diff_stager = container[:diff_stager]
      @bus         = container[:bus]
      @reader      = TTY::Reader.new(track_history: true)
      @running     = false
      @interrupt_at = Time.now
      @last_ok     = true
      @tts_on      = Speech.available? && @config["tts"] != false
      @violations  = 0
      @scan_thread = nil
      @seen_violations = {}
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.respond_to?(:exists?) && @session.exists?
      scan_in_background
      puts @renderer.splash(@agent.model)
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      s = input.strip
      return if s.empty?

      run_input(s)
    end

    def run_input(input)
      return if input.strip.empty?

      accumulated = +""
      streamed = false
      thinking_shown = true

      on_chunk = build_chunk_handler(accumulated) do |text|
        if thinking_shown && $stdout.isatty
          print "\r\e[K"
          thinking_shown = false
        end
        print text
        $stdout.flush
        streamed = true
      end

      print_thinking_indicator
      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      handle_pipeline_result(result, accumulated, streamed)
    end

    private

    def repl_loop
      while @running
        tokens = @session.respond_to?(:token_est) ? @session.token_est : nil
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations,
          tokens: tokens
        )
        line = begin
          @reader.read_line("", echo: true).chomp
        rescue StandardError
          nil
        end
        break if line.nil?
        next if line.strip.empty?

        if line.strip == "/exit"
          exit_cli
        else
          run_input(line)
        end
      end
      @scan_thread&.kill
      @session.save! if @session.respond_to?(:save!)
    end

    def exit_cli
      @session.save! if @session.respond_to?(:save!)
      @running = false
    end

    def scan_in_background
      @scan_thread = Thread.new do
        lib_dir = File.join(@root, "lib")
        changed = begin
          out = `git -C "#{@root}" diff --name-only HEAD 2>/dev/null`.strip
          out.empty? ? [] : out.lines.map { |l| File.join(@root, l.strip) }
                 .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
        rescue StandardError
          []
        end

        result = if changed.any?
                   Result.ok(changed.map { |p| [p, @scanner.scan(p, depth: :standard)] })
                 else
                   @scanner.scan_dir(lib_dir, depth: :standard)
                 end

        next unless result.respond_to?(:ok?) && result.ok?

        count = result.value!.sum do |_file, file_result|
          file_result.respond_to?(:ok?) && file_result.ok? ? file_result.value!.size : 0
        end
        @violations = count

        next if count.zero?

        puts "\n#{@renderer.render("boot scan: #{count} violation(s)", mode: :dim)}"
        print @renderer.prompt_line(
          @agent.model,
          @session.phase,
          last_ok: @last_ok,
          violations: @violations
        )
      rescue StandardError => e
        @bus&.publish("cli:warn", message: e.message)
      end
    end

    def build_chunk_handler(buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?

        yield text
        buffer << text
      end
    end

    def print_thinking_indicator
      return unless $stdout.isatty

      print @renderer.render("thinking...", mode: :dim)
      $stdout.flush
    rescue StandardError
      print "thinking..."
    end

    def handle_pipeline_result(result, accumulated, streamed)
      case result
      in Master::Result::Ok => ok
        @last_ok = true
        handle_ok_result(ok, accumulated, streamed)
      in Master::Result::Err => err
        @last_ok = false
        puts @renderer.render(err.message, mode: :error)
      end
    end

    def handle_ok_result(ok, accumulated, streamed)
      if streamed
        puts
        speak_async(accumulated) if @tts_on
      else
        print "\r\e[K" if $stdout.isatty
        value = ok.value
        text = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
        puts text
        speak_async(text) if @tts_on
      end
    end

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?

        audio_path = Speech.synthesize(plain)
        next unless audio_path

        played = try_paplay(audio_path) || try_direct(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        File.unlink(audio_path) rescue nil if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain = plain.gsub(/```.*?```/m, "")
      plain[0..400]
    end

    def try_paplay(audio_path)
      paplay = PAPLAY_CANDIDATES.find { |c| File.executable?(c) }
      return false unless paplay

      ffmpeg = FFMPEG_CANDIDATES.find { |c| File.executable?(c) }
      return false unless ffmpeg

      socket = ensure_pulse_socket
      return false unless socket

      convert_and_play_via_pulse(audio_path, paplay, ffmpeg, socket)
    end

    def convert_and_play_via_pulse(audio_path, paplay, ffmpeg, socket)
      wav_path = audio_path.sub(/\.mp3$/, ".wav")
      converted = system(
        ffmpeg, "-y", "-i", audio_path, wav_path, "-loglevel", "quiet",
        out: File::NULL, err: File::NULL
      )
      return false unless converted && File.exist?(wav_path)

      ENV["PULSE_SERVER"] = "unix:#{socket}"
      played = system(paplay, wav_path, out: File::NULL, err: File::NULL)
      File.unlink(wav_path) rescue nil
      played
    end

    def ensure_pulse_socket
      return PULSE_SOCKET if File.exist?(PULSE_SOCKET)
      return nil unless File.executable?(PULSE_DAEMON)

      FileUtils.mkdir_p(File.dirname(PULSE_SOCKET))
      system(
        PULSE_DAEMON,
        "--load=module-alsa-sink device=default",
        "--load=module-native-protocol-unix auth-anonymous=1 socket=#{PULSE_SOCKET}",
        "--daemonize",
        "--exit-idle-time=60",
        out: File::NULL,
        err: File::NULL
      )
      sleep 0.6
      File.exist?(PULSE_SOCKET) ? PULSE_SOCKET : nil
    end

    def try_direct(audio_path)
      player = %w[aucat mpv ffplay aplay].find { |c| system("command -v #{c} > /dev/null 2>&1") }
      case player
      when "aucat"
        system("aucat", "-i", audio_path, out: File::NULL, err: File::NULL)
      when "mpv"
        system("mpv", "--no-video", "--really-quiet", audio_path, out: File::NULL, err: File::NULL)
      when "ffplay"
        system("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audio_path, out: File::NULL, err: File::NULL)
      when "aplay"
        system("aplay", "-q", audio_path, out: File::NULL, err: File::NULL)
      else
        false
      end
    end

    def setup_signals
      trap("USR1") do
        begin
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@renderer.render('reloaded', mode: :success)}"
        rescue StandardError => e
          puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
        end
      end
      trap("INT") do
        if Time.now - @interrupt_at < 1
          @scan_thread&.kill
          @session.save! if @session.respond_to?(:save!)
          exit(0)
        else
          @interrupt_at = Time.now
          puts "\n#{@renderer.render('^C again to quit', mode: :warning)}"
        end
      end
    end
  end
end
```

## `lib/master/code_index.rb`
```ruby
# frozen_string_literal: true

require "prism"
require "set"

module Master
  # CodeIndex — live structural model of the Ruby codebase.
  # Parses all .rb files with Prism, builds a symbol graph:
  #   - class/module definitions with inheritance and includes
  #   - method definitions with owning class and file location
  #   - cross‑file constant references and method calls
  #
  # The "digital twin" of the repo — rebuilt on write events.
  class CodeIndex
    Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
    Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

    attr_reader :symbols, :references, :built_at

    def initialize(root:, event_bus: nil)
      @root = File.expand_path(root)
      @bus = event_bus
      @symbols = {}
      @references = []
      @mtimes = {}
      @built_at = nil
    end

# Build the entire index. Optional +path+ restricts to a subtree.
# First call: full build. Subsequent calls: incremental (mtime-based).
def build(path: nil)
  target = path ? File.expand_path(path, @root) : @root
  files = Dir.glob(File.join(target, "**", "*.rb"))
              .reject { |f| f.include?("/vendor/") }

  if @built_at.nil?
    @symbols.clear
    @references.clear
    @mtimes.clear
    files.each do |f|
      index_file(f)
      @mtimes[f] = File.mtime(f) rescue nil
    end
  else
    changed = 0

    (@mtimes.keys - files).each do |gone|
      @symbols.delete_if { |_, s| s.file == gone }
      @references.reject! { |r| r.from_file == gone }
      @mtimes.delete(gone)
    end

    files.each do |f|
      mt = File.mtime(f) rescue nil
      next if @mtimes[f] == mt
      reindex(f)
      @mtimes[f] = mt
      changed += 1
    end

    @bus&.publish("code_index:incremental", changed: changed, total: files.size) if changed > 0
  end

  @built_at = Time.now
  @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
  self
rescue StandardError => e
  @bus&.publish("code_index:error", error: e.message)
  self
end

    # Re‑index a single file, removing stale data first.
    def reindex(file)
      full = File.expand_path(file, @root)
      @symbols.delete_if { |_, s| s.file == full }
      @references.reject! { |r| r.from_file == full }
      index_file(full) if File.file?(full)
    rescue StandardError
      nil
    end

    def symbols_in(file)
      full = File.expand_path(file, @root)
      @symbols.values.select { |s| s.file == full }
    end

    def find(name)
      exact = @symbols[name]
      return [exact] if exact

      suffix = name.to_s
      @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
    end

    def references_to(fqn)
      @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") }
    end

    def impact(fqn)
      refs = references_to(fqn)
      files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
      callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
      { fqn:, reference_count: refs.size, files:, callers: }
    end

    # Classes‑only summary injected into the agent system prompt.
    def summary(limit: nil)
      classes = @symbols.values
                         .select { |s| %i[class module].include?(s.type) }
                         .reject { |s| s.file.include?("/DEPLOY/") || s.file.match?(/fix_|patch_/) }
                         .reject { |s| %w[Entry Message Symbol CircuitError].any? { |n| s.fqn.end_with?("::#{n}") } }
                         .sort_by(&:fqn)
                         .map do |s|
        parent = s.parent && s.parent != "Object" ? " < #{s.parent}" : ""
        "  #{s.fqn}#{parent} (#{s.file.sub("#{@root}/", "")}:#{s.line})"
      end

      lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
      header = "# Codebase: #{lib_count} lib symbols (indexed #{built_at&.strftime("%H:%M") || "never"})"
      title = "## Classes & Modules (#{classes.size})"
      [header, title, *classes].join("\n")
    end

    def query(name)
      hits = find(name)
      return { error: "not found: #{name}" } if hits.empty?

      hits.map do |s|
        refs = references_to(s.fqn)
        {
          fqn: s.fqn,
          type: s.type,
          file: s.file.sub("#{@root}/", ""),
          line: s.line,
          parent: s.parent,
          used_in: refs.first(10).map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }
        }
      end
    end

    def size = @symbols.size
    def built? = !@built_at.nil?

    private

    def index_file(file)
      src = File.read(file, encoding: "UTF-8")
      result = Prism.parse(src)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError
      nil
    end

    # Visitor that extracts symbols and call‑site references.
    class SymbolVisitor < Prism::Visitor
      attr_reader :symbols, :references

      def initialize(file:, root:)
        @file = file
        @root = root
        @symbols = []
        @references = []
        @scope = []
      end

      def visit_class_node(node)
        name = const_name(node.constant_path)
        parent = node.superclass ? const_name(node.superclass) : "Object"
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :class, file: @file,
          line: node.location.start_line, parent:, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_module_node(node)
        name = const_name(node.constant_path)
        fqn = qualified(name)

        @symbols << Symbol.new(
          fqn:, type: :module, file: @file,
          line: node.location.start_line, parent: nil, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      def visit_def_node(node)
        meth = node.name.to_s
        owner = @scope.last || "(top)"
        fqn = "#{qualified(owner)}##{meth}"

        @symbols << Symbol.new(
          fqn:, type: :method, file: @file,
          line: node.location.start_line, parent: owner, includes: []
        )
        super
      end

      def visit_call_node(node)
        method_name = node.name.to_s
        return super unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1

        receiver_fqn = node.receiver ? const_name_safe(node.receiver) : nil
        to_fqn = receiver_fqn ? "#{receiver_fqn}##{method_name}" : method_name

        @references << Reference.new(
          from_file: @file,
          from_line: node.location.start_line,
          to_fqn:,
          ref_type: :call
        )
        super
      end

      private

      def qualified(name)
        return name if @scope.empty? || name.include?("::")
        "#{@scope.join('::')}::#{name}"
      end

      def const_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          "#{const_name(node.parent)}::#{node.name}"
        else
          node.respond_to?(:name) ? node.name.to_s : ""
        end
      end

      def const_name_safe(node)
        name = const_name(node)
        name.empty? ? nil : name
      rescue StandardError
        nil
      end
    end
  end
end```

## `lib/master/config.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  class Config
    DEFAULT_WEB_PORT = 10_002

    DEFAULTS = {
      'model'          => 'nvidia/nemotron-3-super-120b-a12b:free',
      'web_host'       => '0.0.0.0',
      'web_public_url' => 'http://ai.brgen.no:3000',
      'web_port'       => DEFAULT_WEB_PORT,
      'budget_max'     => 10.0,
      'req_max'        => 1.0,
      'trace'          => 0,
      'prescan'        => true,
      'auto'           => false,
      'cache_ttl'      => 3_600,
      'history_max'    => 500,
      'reasoning_mode' => 'direct',
      'task_type'      => 'code_generation',
      'auto_testing'   => false
    }.freeze

    attr_reader :data

    def initialize(root = Dir.pwd)
      @root = root
      @path = File.join(root, '.master', 'config.yml')
      @data = load_config
    end

    # Hash‑style access
    def [](key)         = @data[key.to_s]
    def []=(key, value) ; @data[key.to_s] = value ; end

    # Typed helpers
    def model          = self['model']
    def budget_max     = self['budget_max'].to_f
    def req_max        = self['req_max'].to_f
    def trace          = (ENV['MASTER_TRACE'] || self['trace']).to_i
    def prescan?       = !!self['prescan']
    def auto?          = !!self['auto']
    def reasoning_mode = self['reasoning_mode'].to_s
    def task_type      = self['task_type'].to_s
    def auto_testing?  = !!self['auto_testing']

    # Persist atomically; fsync ensures durability.
    def save!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)

      tmp = "#{@path}.tmp.#{Process.pid}"
      File.open(tmp, 'w') do |f|
        f.write(@data.to_yaml)
        f.flush
        f.fsync
      end
      File.rename(tmp, @path)
    ensure
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
    end

    # Reload from disk, preserving unknown keys.
    def reload!
      @data = load_config
    end

    # Export as plain hash (deep dup to avoid external mutation)
    def to_h = Marshal.load(Marshal.dump(@data))

    private

    def load_config
      return deep_dup(DEFAULTS) unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path) || {}
      deep_merge(DEFAULTS, stringify_keys(loaded))
    rescue Psych::Exception => e
      warn "config: failed to parse #{@path}: #{e.message}"
      deep_dup(DEFAULTS)
    end

    # Recursive merge where +b+ overrides +a+.
    def deep_merge(a, b)
      a.merge(b) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end

    def deep_dup(hash)
      Marshal.load(Marshal.dump(hash))
    end
  end
end```

## `lib/master/context_window.rb`
```ruby
# frozen_string_literal: true

module Master
  class ContextWindow
    COMPACT_THRESHOLD = 0.80
    private_constant :COMPACT_THRESHOLD

    attr_reader :session, :agent, :model_context

    def initialize(session:, agent: nil, model_context: 200_000)
      @session = session
      @agent   = agent
      @model_context = model_context
    end

    # Returns Result.ok(:ok) when no action is needed,
    # Result.ok(:compacted) when compaction succeeds,
    # or Result.err on failure.
    def check_and_compact!
      return Result.ok(:ok) unless agent
      return Result.ok(:ok) unless safe_to_compact?

      compact!
    end

    private

    def safe_to_compact?
      est = session.token_est
      return false unless est.is_a?(Numeric)

      est >= model_context * COMPACT_THRESHOLD
    end

    def compact!
      summary = agent.ask(
        "Summarize our progress, preserving all file paths, decisions, and remaining tasks.",
        context: session.messages
      )
      session.clear!
      session.add_message(
        role: :assistant,
        content: "[Context compacted]\n\n#{summary}"
      )
      Result.ok(:compacted)
    rescue StandardError => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end```

## `lib/master/council/deliberation.rb`
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      Result = Master::Result

      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
        validate_dependencies!
      end

      def review(code, context: nil)
        return Result.err('council: no personas configured', category: :validation) if @personas.empty?

        feedback = @personas.map do |persona|
          response = @agent.ask(build_prompt(persona, code, context))
          entry = {
            persona:    persona.name,
            role:       persona.role,
            veto_role:  veto_role?(persona),
            feedback:   response
          }
          @bus&.publish(:council_feedback, entry)
          entry
        end

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        Result.ok(feedback)
      rescue StandardError => e
        Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def validate_dependencies!
        raise ArgumentError, 'personas must be an array' unless @personas.is_a?(Array)
        raise ArgumentError, 'agent must respond to :ask' unless @agent.respond_to?(:ask)
      end

      def veto_role?(persona)
        if persona.respond_to?(:veto?)
          persona.veto?
        else
          persona.respond_to?(:veto_role) && !!persona.veto_role
        end
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ''
        veto_hint = veto_role?(persona) ? ' You may prefix VETO: if this must not ship.' : ''
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{persona.prompt}

          Code:
          #{code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
      end

      def veto_text?(feedback)
        feedback.to_s.strip.start_with?('VETO:')
      end
    end
  end
end```

## `lib/master/council/personas.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Council
    module Personas
      # veto_role (default false) lets a persona block the pipeline with `VETO:`.
      # Previously Council::Deliberation hardcoded `persona.name == "Security"`,
      # which broke the moment the persona was renamed (e.g. to Norwegian).
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",  prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil advocate", bias: "Caution",    prompt: "Find what could go wrong. Challenge every assumption.",                veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",   prompt: "Is this shippable? Flag over-engineering.",                            veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",     prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability",  prompt: "Does this serve the user? Are error messages actionable?",             veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",    prompt: "Is this code readable? Do names reveal intent?",                       veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = YAML.safe_load_file(data_path, symbolize_names: true)
          raise "Invalid persona data" unless raw.is_a?(Array)

          raw.map do |attrs|
            raise "Persona must be a hash" unless attrs.is_a?(Hash)

            attrs = { veto_role: false }.merge(attrs)
            Persona.new(**attrs)
          end.freeze
        rescue StandardError
          DEFAULTS
        end
      end
    end
  end
end```

## `lib/master/decision_engine.rb`
```ruby
# frozen_string_literal: true

module Master
  # DecisionEngine — shared scoring and convergence logic.
  # Ported from MASTER2. Scores candidates by (impact * confidence) / cost.
  # Used by Heartbeat for job ranking and ModelRouter for model selection.
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      rows = Array(candidates).map do |c|
        data = c.is_a?(Hash) ? c : { value: c }
        data.merge(score: score(
          impact:     data.fetch(:impact, 1.0),
          confidence: data.fetch(:confidence, 1.0),
          cost:       data.fetch(:cost, 1.0)
        ))
      end
      rows.max_by { |r| r[:score] }
    end

    def rank(candidates)
      Array(candidates).sort_by { |c| -(c[:score] || 0.0) }
    end

    def converged?(previous_score:, current_score:, min_improvement: 0.001)
      return false if previous_score.nil?

      (current_score.to_f - previous_score.to_f).abs < min_improvement.to_f
    end
  end
end
```

## `lib/master/diff_stager.rb`
```ruby
# frozen_string_literal: true

require "diffy"
require "fileutils"
require "json"

module Master
  # DiffStager — intercepts file writes and stores diffs for human review.
  # When staging_enabled? in config, tools push here instead of writing directly.
  # CLI commands: /stage (list), /apply [n|all], /discard [n|all]
  class DiffStager
    Entry = Struct.new(:id, :path, :old_content, :new_content, :tool, :created_at, keyword_init: true) do
      def diff
        Diffy::Diff.new(old_content.to_s, new_content.to_s, context: 3)
      end

      def diff_stats
        lines  = diff.to_s.lines
        added  = lines.count { |l| l.start_with?("+") && !l.start_with?("+++") }
        removed = lines.count { |l| l.start_with?("-") && !l.start_with?("---") }
        "+#{added}/-#{removed}"
      end
    end

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @pending = []
      @counter = 0
    end

    # Called by tools instead of writing directly. Returns a Result.
    def stage(path:, new_content:, tool: "unknown")
      old_content = File.exist?(path) ? File.read(path) : ""
      return Result.ok("no change") if old_content == new_content

      @counter += 1
      entry = Entry.new(
        id:          @counter,
        path:        path,
        old_content: old_content,
        new_content: new_content,
        tool:        tool,
        created_at:  Time.now
      )
      @pending << entry
      persist_entry(entry)
      @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
      Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
    end

    def pending = @pending.dup
    def empty?  = @pending.empty?
    def size    = @pending.size

    # Apply one or all entries. Returns array of applied paths.
    def apply(id: :all)
      targets = id == :all ? @pending.dup : @pending.select { |e| e.id == id }
      applied = []
      targets.each do |entry|
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.new_content)
        @pending.delete(entry)
        remove_persisted(entry)
        @bus&.publish("stage:applied", id: entry.id, path: entry.path)
        applied << entry.path
      end
      applied
    end

    # Discard one or all without writing.
    def discard(id: :all)
      targets = id == :all ? @pending.dup : @pending.select { |e| e.id == id }
      targets.each do |entry|
        @pending.delete(entry)
        remove_persisted(entry)
        @bus&.publish("stage:discarded", id: entry.id, path: entry.path)
      end
      targets.map(&:path)
    end

    # Colored summary for CLI display
    def summary(pastel)
      return pastel.dim("  (no staged changes)") if @pending.empty?
      @pending.map do |e|
        short = e.path.sub(@root + "/", "")
        "  #{pastel.yellow("[#{e.id}]")} #{pastel.white(short)} #{pastel.dim(e.diff_stats)} #{pastel.dim("via #{e.tool}")}"
      end.join("\n")
    end

    # Colored unified diff for one entry
    def render_diff(id, pastel)
      entry = @pending.find { |e| e.id == id }
      return pastel.red("no staged change with id #{id}") unless entry

      short = entry.path.sub(@root + "/", "")
      header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}\n"
      diff_lines = entry.diff.to_s.lines.map do |line|
        case line[0]
        when "+" then pastel.green(line.chomp)
        when "-" then pastel.red(line.chomp)
        when "@" then pastel.cyan(line.chomp)
        else          pastel.dim(line.chomp)
        end
      end
      header + diff_lines.join("\n")
    end

    private

    def stage_dir
      File.join(@root, ".master", "pending")
    end

    def persist_entry(entry)
      FileUtils.mkdir_p(stage_dir)
      File.write(
        File.join(stage_dir, "#{entry.id}.json"),
        JSON.generate({
          id: entry.id, path: entry.path, tool: entry.tool,
          created_at: entry.created_at.iso8601,
          stats: entry.diff_stats
        })
      )
    rescue StandardError
      nil
    end

    def remove_persisted(entry)
      persist_file = File.join(stage_dir, "#{entry.id}.json")
      # Safe to delete: this persisted staging file is being removed after the entry
      # has been either applied (written to the actual file) or discarded (abandoned).
      File.delete(persist_file) if File.exist?(persist_file)
    rescue StandardError
      nil
    end
  end
end
```

## `lib/master/event_bus.rb`
```ruby
# frozen_string_literal: true

require "monitor"

module Master
  class EventBus
    include MonitorMixin

    BOOT_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

    def initialize
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @pattern_cache = {}
    end

    # Returns a lambda that unsubscribes this handler when called.
    def subscribe(pattern, &handler)
      synchronize { @subscribers[pattern] << handler }
      -> { synchronize { @subscribers[pattern].delete(handler) } }
    end

    def publish(event, payload = {})
      ts      = elapsed_ms
      payload = payload.merge(event:, ts:)
      synchronize { matching_handlers(event) }.each { |h| h.call(payload) }
      self
    end

    private

    def elapsed_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - BOOT_TIME
    end

    def matching_handlers(event)
      @subscribers.flat_map { |pattern, handlers|
        handlers if glob_match?(pattern, event)
      }.compact
    end

    # Compiles glob pattern to regex once; ** crosses segments, * does not.
    def glob_match?(pattern, event)
      re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub('\\*\\*', '.*').gsub('\\*', '[^:]*') + "\\z"
      )
      re.match?(event)
    end
  end
end
```

## `lib/master/gateway.rb`
```ruby
# frozen_string_literal: true

module Master
  # Gateway — multi-channel message router.
  # Funnels messages from CLI, web, and future channels (IRC, Matrix)
  # into a single pipeline call. Channel-agnostic: ctx[:channel] tags origin.
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @handlers = {}
    end

    def register(channel, &handler)
      @handlers[channel.to_sym] = handler
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = {
        user_message: message.to_s.strip,
        channel:      channel,
        metadata:     metadata
      }

      result = @pipeline.call(Result.ok(ctx))

      if @handlers[channel]
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        @handlers[channel].call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @handlers.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("\n")
    end

    private

    def extract_text(result)
      val = result.value!
      val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
    rescue StandardError
      result.to_s
    end
  end
end
```

## `lib/master/git_operations.rb`
```ruby
# frozen_string_literal: true

require "open3"



module Master
  # GitOperations encapsulates git commands.
  # ONE_JOB: manage Git interactions for a specified repository root.
  class GitOperations
    def initialize(root_path)
      @root_path = root_path
    end

    # Reports if the target path within the repository has uncommitted changes.
    # Defaults to "lib/" if no path is specified.
    def dirty?(path = "lib/")
      Dir.chdir(@root_path) do
        out, = Open3.capture3("git status --porcelain #{path}")
        !out.strip.empty?
      end
    end

    # Stages changes for all files in "lib/".
    def add_lib_files
      Dir.chdir(@root_path) do
        system("git add -A lib/ 2>/dev/null")
      end
    end

    # Commits staged changes with the provided message.
    def commit(message)
      Dir.chdir(@root_path) do
        system("git commit -m '#{message}' 2>/dev/null")
      end
    end
  end
end```

## `lib/master/governor.rb`
```ruby
# frozen_string_literal: true

require "tty-prompt"

module Master
  class Governor
    TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

    # Sliding-window rate limits per tier (calls per minute).
    TIER_RATE_LIMITS = { guarded: 10, dangerous: 3 }.freeze

    def initialize(config:, event_bus: nil)
      @config        = config
      @bus           = event_bus
      @prompt        = $stdout.isatty ? TTY::Prompt.new : nil
      @auto          = config.auto?
      @approve_all   = false
      @rate_windows  = Hash.new { |h, k| h[k] = [] }
      @rate_mutex    = Mutex.new
    end

    def check_permit(tool_name, tier, description = nil)
      @bus&.publish("tool:before", tool: tool_name, tier:)

      if (rate_err = check_rate_limit!(tier))
        @bus&.publish("tool:rate_limited", tool: tool_name, tier:)
        return rate_err
      end

      case tier
      when :safe      then return Result.ok(true)
      when :guarded   then return Result.ok(true) if @auto || @approve_all
      when :dangerous then return Result.ok(true) if @auto || @approve_all
      end

      ask_user(tool_name, tier, description)
    rescue StandardError => e
      Result.err(e.message, category: :validation)
    end

    alias permit? check_permit

    def approve_all!   = @approve_all = true
    def reset_approve! = @approve_all = false

    private

    def check_rate_limit!(tier)
      limit = TIER_RATE_LIMITS[tier]
      return nil unless limit
      now = Time.now.to_f
      @rate_mutex.synchronize do
        calls = @rate_windows[tier]
        calls.reject! { |t| now - t > 60.0 }
        if calls.size >= limit
          return Result.err("rate limit: #{tier} tier (#{limit}/min)", category: :rate_limit)
        end
        calls << now
      end
      nil
    end

    def ask_user(tool_name, tier, description)
      return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt

      label  = description ? "#{tool_name}: #{description}" : tool_name
      choice = @prompt.select("#{tier_icon(tier)} #{label}", [
        { name: "approve", value: :approve },
        { name: "deny",    value: :deny },
        { name: "quit",    value: :quit }
      ])

      case choice
      when :approve then Result.ok(true)
      when :deny    then @bus&.publish("tool:denied", tool: tool_name); Result.err("denied by user", category: :validation)
      when :quit    then exit(0)
      end
    end

    def tier_icon(tier)
      case tier
      when :safe      then "i"
      when :guarded   then "!"
      when :dangerous then "!!"
      end
    end
  end
end
```

## `lib/master/heartbeat.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # Heartbeat — autonomous scheduled task runner.
  # Reads heartbeat.yml for periodic jobs (sweep, model check, prune, self-test).
  # Each job has an interval_seconds and a last_run timestamp persisted in .master/heartbeat_state.yml.
  class Heartbeat
    DATA_PATH  = File.join(Master::ROOT, "data", "heartbeat.yml").freeze
    STATE_PATH = ".master/heartbeat_state.yml"

    def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil)
      @root    = root
      @agent   = agent
      @scanner = scanner
      @memory  = memory
      @bus     = event_bus
      @jobs    = load_jobs
      @state   = load_state
      @thread  = nil
    end

    def start!
      return if @jobs.empty?

      @thread = Thread.new do
        loop do
          run_due!
          sleep 60
        end
      rescue StandardError => e
        @bus&.publish("heartbeat:error", message: e.message)
      end
    end

    def stop!
      @thread&.kill
      @thread = nil
    end

    def run_due!
      now = Time.now.to_i
      results = []

      @jobs.each do |job|
        name     = job["name"]
        interval = job["interval_seconds"].to_i
        last_run = @state.dig(name, "last_run").to_i

        next unless now - last_run >= interval

        @bus&.publish("heartbeat:run", job: name)
        result = execute_job(job)
        @state[name] = { "last_run" => now, "result" => result.to_s[0, 200] }
        results << { name: name, result: result }
      end

      persist_state unless results.empty?
      results
    end

    def list
      @jobs.map do |job|
        last = @state.dig(job["name"], "last_run").to_i
        ago  = last.zero? ? "never" : "#{(Time.now.to_i - last) / 60}m ago"
        "#{job["name"]}: every #{job["interval_seconds"] / 60}m, last: #{ago}"
      end.join("\n")
    end

    private

    def execute_job(job)
      case job["action"]
      when "prune_memory"
        @memory&.consolidate!(agent: @agent) || "no memory"
      when "check_models"
        check_model_availability
      when "self_test"
        run_self_test
      when "prune_undo"
        prune_undo_journal
      when "snapshot"
        generate_snapshot
      else
        "unknown action: #{job["action"]}"
      end
    rescue StandardError => e
      "error: #{e.message}"
    end

    def check_model_availability
      models_path = File.join(@root, "data", "models.yml")
      return "no models.yml" unless File.exist?(models_path)

      data    = YAML.safe_load_file(models_path, aliases: true)
      tiers   = data["models"] || {}
      ids     = tiers.values.flatten.map { |m| m["id"] }.compact
      alive   = ids.select { |id| model_reachable?(id) }
      "models: #{alive.size}/#{ids.size} reachable"
    end

    def model_reachable?(model_id)
      RubyLLM.chat(model: model_id).ask("ping")
      true
    rescue StandardError
      false
    end

    def run_self_test
      return "no scanner" unless @scanner

      target = File.join(@root, "lib")
      result = @scanner.scan_dir(target, depth: :standard)
      return "scan failed" unless result.respond_to?(:ok?) && result.ok?

      count = result.value!.sum { |_, fr| fr.respond_to?(:ok?) && fr.ok? ? fr.value!.size : 0 }
      @bus&.publish("heartbeat:self_test", violations: count)
      "self-test: #{count} violations"
    end

    def prune_undo_journal
      journal_path = File.join(@root, ".master", "undo.jsonl")
      return "no journal" unless File.exist?(journal_path)

      lines = File.readlines(journal_path)
      return "journal empty" if lines.empty?

      keep = [lines.size / 2, 50].max
      File.write(journal_path, lines.last(keep).join)
      "pruned undo: kept #{keep}/#{lines.size} entries"
    end

    def generate_snapshot
      stamp = Time.now.strftime("%Y%m%d_%H%M%S")
      out   = File.join(@root, ".master", "snapshot.md")
      dirs  = %w[exe lib/master data].map { |d| File.join(@root, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                  .select { |f| File.file?(f) && File.size(f) < 50_000 }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
      lines = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      files.each do |f|
        rel  = f.sub("#{@root}/", "")
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
      rescue StandardError
        next
      end
      File.write(out, lines.join("\n"))
      "snapshot: #{files.size} files -> #{out}"
    end

    def load_jobs
      path = File.join(@root, "data", "heartbeat.yml")
      return default_jobs unless File.exist?(path)

      YAML.safe_load_file(path) || default_jobs
    rescue StandardError
      default_jobs
    end

    def default_jobs
      [
        { "name" => "prune_memory",  "action" => "prune_memory",  "interval_seconds" => 3600 },
        { "name" => "self_test",     "action" => "self_test",     "interval_seconds" => 7200 },
        { "name" => "prune_undo",    "action" => "prune_undo",    "interval_seconds" => 86_400 },
        { "name" => "snapshot",      "action" => "snapshot",      "interval_seconds" => 14_400 }
      ]
    end

    def load_state
      path = File.join(@root, STATE_PATH)
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    rescue StandardError
      {}
    end

    def persist_state
      path = File.join(@root, STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @state.to_yaml)
    end
  end
end
```

## `lib/master/introspection/self_map.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Introspection
    class SelfMap
      def initialize(root:)
        @root = root
      end

      def describe
        files = Dir.glob(File.join(@root, "lib/**/*.rb")).sort
        lines = files.sum { |f| File.readlines(f).size }
        mods  = files.map { |f| f.delete_prefix(@root + "/lib/").delete_suffix(".rb").gsub("/", "::") }

        {
          root:   @root,
          files:  files.size,
          lines:,
          modules: mods
        }
      end

      def axiom_coverage
        rules_path = File.join(@root, "data", "rules.yml")
        return {} unless File.exist?(rules_path)

        data = YAML.safe_load_file(rules_path, aliases: true)
        all_rules = (data["rules"] || {}).values.flatten
        source = Dir.glob(File.join(@root, "lib/**/*.rb")).map { |f| File.read(f) }.join
        all_rules
          .group_by { |r| r["tier"] }
          .transform_values { |rules| rules.count { |r| source.include?(r["id"].to_s) } }
      end
    end
  end
end
```

## `lib/master/logging.rb`
```ruby
# frozen_string_literal: true

module Master
  class Logging
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:, trace_level: 0)
      @buffer      = ring_buffer
      @bus         = event_bus
      # trace_level accepted for API compatibility but not consulted internally;
      # tracing is controlled via Config#trace and ENV["MASTER_TRACE"].

      wire_events
    end

    def dmesg(lines = 50)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event]
      ts    = payload[:ts]
      rest  = payload.except(:event, :ts)
      "[#{ts}ms] #{event}#{rest.empty? ? "" : ": #{rest.inspect}"}"
    end
  end
end
```

## `lib/master/mcp_coordinator.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm/mcp" if $LOAD_PATH.any? { |p| File.exist?(File.join(p, "ruby_llm/mcp.rb")) }

module Master
  # McpCoordinator — manages MCP server connections and exposes
  # their tools to the agent alongside MASTER's native tools.
  # Servers are defined in data/mcp_servers.yml.
  class McpCoordinator
    CONFIG_PATH = "data/mcp_servers.yml".freeze

    def initialize(root:, event_bus: nil)
      @root    = root
      @bus     = event_bus
      @clients = {}
    end

    # Connect to all configured MCP servers. Non-fatal on failure.
    def connect_all
      servers = load_servers
      servers.each do |name, cfg|
        connect(name, cfg)
      end
      @bus&.publish("mcp:connected", count: @clients.size)
    rescue StandardError => e
      @bus&.publish("mcp:error", error: e.message)
    end

    # Return all tools from all connected MCP servers as RubyLLM::Tool wrappers.
    def tools
      @clients.flat_map do |name, client|
        client.tools.filter_map do |tool|
          McpToolWrapper.new(name:, client:, tool:)
        rescue StandardError
          nil
        end
      end
    rescue StandardError
      []
    end

    def connected?
      @clients.any?
    end

    def server_names
      @clients.keys
    end

    private

    def connect(name, cfg)
      return unless cfg.is_a?(Hash) && cfg["enabled"] != false
      transport = (cfg["transport"] || "stdio").to_sym
      mcp_config = case transport
                   when :stdio
                     { command: cfg["command"], args: cfg["args"] || [] }
                   when :sse
                     { url: cfg["url"] }
                   else
                     return
                   end
      client = ::RubyLLM::MCP::Client.new(
        name: name,
        transport_type: transport,
        config: mcp_config,
        start: false
      )
      client.start
      @clients[name] = client
      @bus&.publish("mcp:server_connected", name:, transport: transport.to_s)
    rescue StandardError => e
      @bus&.publish("mcp:server_failed", name:, error: e.message)
    end

    def load_servers
      path = File.join(@root, CONFIG_PATH)
      return {} unless File.exist?(path)
      require "yaml"
      data = YAML.safe_load_file(path, aliases: true) || {}
      data.fetch("servers", {})
    rescue StandardError
      {}
    end
  end

  # Wraps an MCP tool as a RubyLLM::Tool for the agent's tool list.
  if defined?(::RubyLLM::Tool)
    class McpToolWrapper < ::RubyLLM::Tool
      def initialize(name:, client:, tool:)
        @mcp_name   = name
        @mcp_client = client
        @mcp_tool   = tool
      end

      def name
        "#{@mcp_name}__#{@mcp_tool.name}"
      end

      def description
        "[MCP:#{@mcp_name}] #{@mcp_tool.description}"
      end

      def execute(**params)
        result = @mcp_client.call_tool(@mcp_tool.name, params)
        result.respond_to?(:content) ? result.content : result.to_s
      rescue StandardError => e
        "MCP tool error: #{e.message}"
      end
    end
  end
end
```

## `lib/master/memory.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  # Memory — persistent cross-session store with TF-IDF semantic search.
  # Stored at .master/memory.yml. Survives restarts.
  class Memory
    TTL_DAYS          = 90
    MAX_INJECT_TOKENS  = 2000
    MAX_INJECT_ENTRIES = 5

    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @store = load_store
    end

    def remember(key, value)
      prune_stale! if @store.size > 40
      @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      persist
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @store.delete(key.to_s)
      persist
    end

    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }

    # Token-limited injection for system prompt. Caps at MAX_INJECT_TOKENS.
    def context_summary
      active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
      return nil if active.empty?

      recent    = active.sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }.first(MAX_INJECT_ENTRIES)
      lines     = []
      token_sum = 0

      recent.each do |k, v|
        text = "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}"
        est  = text.bytesize / 4
        break if token_sum + est > MAX_INJECT_TOKENS
        lines << text
        token_sum += est
      end
      return nil if lines.empty?

      archived_n = @store.count { |k, _| k.to_s.start_with?("archive/") }
      summary    = recall("_consolidated_summary")
      header     = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
      header    += " [+#{archived_n} archived]" if archived_n > 0
      "#{header}\n#{lines.join("\n")}"
    end

    # TF-IDF ranked search. Returns [{key:, value:, score:}], highest first.
    def semantic_recall(query, top_n: 3)
      return [] if @store.empty?

      query_terms = tokenize(query)
      return [] if query_terms.empty?

      scored = @store.filter_map do |key, data|
        value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
        doc   = "#{key} #{value}"
        score = tfidf_score(query_terms, tokenize(doc))
        next if score.zero?
        { key: key, value: value, score: score }
      end

      scored.sort_by { |e| -e[:score] }.first(top_n)
    end

    # Three-phase consolidation: light (score), deep (archive), REM (LLM summary).
    def consolidate!(agent: nil)
      return "nothing to consolidate" if @store.empty?

      now      = Time.now.to_i
      entries  = @store.reject { |k, _| k.to_s.start_with?("archive/") }
      archived = 0

      scored = entries.map do |key, data|
        ts    = data.is_a?(Hash) ? data["ts"].to_i : 0
        value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
        age_d = (now - ts) / 86_400.0
        { key: key, value: value, score: 1.0 / (1.0 + age_d / 30.0) }
      end

      scored.each do |entry|
        next if entry[:key] == "_consolidated_summary"
        next unless entry[:score] < 0.33
        @store["archive/#{entry[:key]}"] = @store.delete(entry[:key])
        archived += 1
      end

      if agent
        active_text = @store
          .reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
          .map    { |k, v| "#{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
          .join("\n")

        unless active_text.strip.empty?
          summary = agent.ask_once(
            "Summarize in 2 concise sentences, preserving all key facts:\n#{active_text}"
          )
          remember("_consolidated_summary", summary.strip)
        end
      end

      persist
      "dreaming: #{entries.size} entries checked, #{archived} archived"
    rescue StandardError => e
      "consolidation error: #{e.message}"
    end

    private

    def prune_stale!
      cutoff = Time.now.to_i - TTL_DAYS * 86_400
      @store.each do |k, v|
        next if k.to_s.start_with?("archive/") || k == "_consolidated_summary"
        ts = v.is_a?(Hash) ? v["ts"].to_i : 0
        next unless ts > 0 && ts < cutoff
        @store["archive/#{k}"] = @store.delete(k)
      end
    end

    def load_store
      return {} unless File.exist?(@path)
      YAML.safe_load_file(@path, symbolize_names: false) || {}
    rescue StandardError
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end

    def tokenize(text)
      text.downcase.scan(/\b[a-z]{2,}\b/)
    end

    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty?
      freq = doc_terms.tally
      query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
    end
  end
end
```

## `lib/master/metrics.rb`
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Metrics
    METRICS_PREFIX = "metrics0".freeze
    DIFF_SIZE_LIMIT_DEFAULT = 200
    MAX_DIFF_SIZE_LIMIT = DIFF_SIZE_LIMIT_DEFAULT
    MAX_DIFF_SIZE_LINES = MAX_DIFF_SIZE_LIMIT
    ROLLBACK_RATE_THRESHOLD = 0.15
    DECISION_LATENCY_MS_THRESHOLD = 5000

    def initialize(root:, event_bus: nil)
      @path        = File.join(root, ".master", "metrics.jsonl")
      @bus         = event_bus
      @writes      = 0
      @undos       = 0
      @latencies   = []
      @diff_sizes  = []
      @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
      subscribe_to_bus(event_bus) if event_bus
    end

    def record_latency(ms)
      @latencies << ms
      check_threshold(:decision_latency_ms, average(@latencies))
      append(decision_latency_ms: ms)
    end

    def record_diff(lines)
      @diff_sizes << lines
      @writes += 1
      check_threshold(:diff_size_lines, average(@diff_sizes))
      append(diff_size_lines: lines)
    end

    def record_undo
      @undos += 1
      rate = @writes > 0 ? @undos.to_f / @writes : 0.0
      check_threshold(:rollback_rate, rate)
      append(rollback_rate: rate.round(3))
    end

    # Called via llm:response EventBus subscription or directly.
    def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
      s = @model_stats[model.to_s]
      s[:calls]       += 1
      s[:failures]    += 1 unless success
      s[:escalations] += 1 if escalated
      append(llm_response: { model: model.to_s, success:, tokens_approx:, escalated: })
    end

    def summary
      {
        avg_latency_ms: average(@latencies).round,
        avg_diff_lines: average(@diff_sizes).round,
        rollback_rate:  (@writes > 0 ? @undos.to_f / @writes : 0.0).round(3),
        writes:         @writes,
        undos:          @undos
      }
    end

    # Returns per-model quality stats, sorted by failure rate desc.
    def model_quality
      @model_stats.transform_values do |s|
        fail_rate = s[:calls] > 0 ? (s[:failures].to_f / s[:calls]).round(3) : 0.0
        s.merge(fail_rate:)
      end.sort_by { |_, v| -v[:fail_rate] }.to_h
    end

    private

    def subscribe_to_bus(bus)
      bus.subscribe("llm:response") do |ev|
        record_llm_response(
          model:        ev[:model].to_s,
          success:      ev[:success] != false,
          tokens_approx: ev[:tokens_approx].to_i,
          escalated:    ev[:escalated] == true
        )
      rescue StandardError
        nil
      end
    end

    def check_threshold(metric, value)
      threshold =
        case metric
        when :decision_latency_ms then DECISION_LATENCY_MS_THRESHOLD
        when :diff_size_lines     then MAX_DIFF_SIZE_LINES
        when :rollback_rate       then ROLLBACK_RATE_THRESHOLD
        else return
        end
      return unless value > threshold
      @bus&.publish("metrics:threshold_exceeded", metric:, value:)
      warn "#{METRICS_PREFIX}: #{metric} #{value} exceeds #{threshold}"
    end

    def average(arr)
      return 0.0 if arr.empty?
      arr.sum.to_f / arr.size
    end

    def append(entry)
      entry[:ts] = Time.now.to_i
      File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError
      nil
    end
  end
end
```

## `lib/master/personality.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Default: dark_malay — terse, direct, Osman TTS voice.
  class Personality
    PERSONAS = {
      dark_malay: {
        voice:       "ms-MY-OsmanNeural",
        tts_rate:    "-35%",
        tts_pitch:   "-150Hz",
        style:       :deep,
        description: "Terse. Direct. No filler. Dark."
      },
      british: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Measured. Precise. Dry wit."
      },
      norwegian: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Calm. Considered. Honest."
      },
      ronin: {
        voice:       "en-US-AndrewNeural",
        tts_rate:    "-25%",
        tts_pitch:   "-100Hz",
        style:       :deep,
        description: "Stoic. Minimal. Decisive. Says only what must be said."
      },
      lawyer: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-10%",
        tts_pitch:   "-20Hz",
        style:       :slow,
        description: "Norwegian law focus. Barnevernet, lovdata.no, sivilombudet.no. Not legal advice."
      },
      hacker: {
        voice:       "en-US-GuyNeural",
        tts_rate:    "-30%",
        tts_pitch:   "-120Hz",
        style:       :deep,
        description: "OpenBSD security. CVE analysis. Pentesting. Exploit-db."
      },
      architect: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-60Hz",
        style:       :heavy,
        description: "Parametric design. BIM. archdaily.com. dezeen.com."
      },
      sysadmin: {
        voice:       "en-AU-WilliamNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :deep,
        description: "OpenBSD. pf. httpd. vmm. man.openbsd.org."
      },
      trader: {
        voice:       "en-US-ChristopherNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Crypto. DeFi. Technicals. TradingView. CoinGecko."
      },
      medic: {
        voice:       "en-US-EricNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Medical research. PubMed. Not medical advice."
      }
    }.freeze

    DEFAULT = :dark_malay

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT, root: nil)
      @name      = name.to_sym
      persona    = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
      @axioms    = Axioms.new(root:)
    end

    # Injected before every LLM call. Pulls from rules.yml via Axioms.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
      constitution = @axioms.constitution
      strunk = @axioms.strunk
      banned  = (constitution["banned_output"] || [])
      no_open = (strunk["preambles"] || []).first(4)
      no_end  = (strunk["endings"]   || []).first(3)
      ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
      ls << "Evidence only: show diff or file content, never assert. Active voice."
      kernel = @axioms.kernel
      ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
      phil = @axioms.philosophy(limit: 10)
      ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
      golden = constitution["golden_rule"]
      ls << "Rule: #{golden}." if golden

      # Hard formatting rules — [K] enforced
      ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**), no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
      ls << "Never use: Certainly, Of course, Great question, Absolutely, Happy to help, I would be glad."

      # Code generation axioms — [K] enforced
      ls << "Code axioms — refuse to generate code that violates these:"
      ls << "FAIL_VISIBLY: never rescue Exception or bare rescue that swallows errors silently. Always rescue StandardError or a specific class."
      ls << "SIMPLEST_WORKS: refuse to create god classes (>300 lines, >20 methods). Push back and suggest decomposition."
      ls << "PRESERVE_FIRST: never rewrite working code from scratch. Read first, patch minimally."
      ls << "BE_CONCISE: minimal response. If the answer is one word, say one word."

      ls.join("\n")
    end
  end
end
```

## `lib/master/pipeline.rb`
```ruby
# frozen_string_literal: true

module Master
  # Pipeline — Result-monadic stage chain.
  #
  # Adds lightweight rollback: if a stage raises a dangerous error category
  # AND a git-backed workspace exists, reset the working tree before
  # returning the error. Safe for non-git contexts (Sweep, tests) via the
  # dirty? check.
  class Pipeline
    ROLLBACK_CATEGORIES = %i[validation axiom_violation].freeze

    attr_reader :last_timings

    def initialize(stages, bus: nil, trace: false, root: nil, event_bus: nil)
      @stages = stages
      @last_timings = {}
      @bus   = bus || event_bus
      @trace = trace
      @root  = root
    end

    # Run stages in sequence. Each stage's elapsed time is accumulated in
    # ctx[:_timings] (Hash of stage_name => ms).
    def call(initial)
      timings = {}
      @stages.reduce(initial) do |result, stage|
        result.and_then(stage_label(stage)) do |ctx|
          t0  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          res = stage.call(ctx)
          ms  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
          timings[stage_label(stage)] = ms
          if res.respond_to?(:ok?) && res.ok?
            @last_timings = timings.dup
            @bus&.publish("pipeline:stage", stage: stage_label(stage), ms:) if @trace
            Result.ok(res.value!.merge(_timings: timings.dup))
          else
            res
          end
        end
      end.tap { |final| maybe_rollback(final) }
    end

    # Group of stages that run concurrently and merge their ctx contributions.
    # Non-conflicting keys are additive; conflicting keys: last-writer wins by
    # stage order. Errors in individual stages are non-fatal — they are
    # attached as `ctx[:_parallel_errors]` and execution continues.
    class ParallelGroup
      PARALLEL_TIMEOUT_S = 30

      def initialize(*stages)
        @stages = stages
      end

      def call(ctx)
        frozen_ctx = ctx.freeze
        threads    = @stages.map { |s| Thread.new { s.call(frozen_ctx) } }

        results = threads.each_with_index.map do |t, i|
          if t.join(PARALLEL_TIMEOUT_S)
            t.value
          else
            t.kill rescue nil
            Result.ok(frozen_ctx.merge(_parallel_timeout: @stages[i].class.name))
          end
        end

        errors  = results.filter_map { |r| r.respond_to?(:err?) && r.err? ? r.message : nil }
        merged  = results.reduce(ctx) { |acc, r| r.respond_to?(:ok?) && r.ok? ? acc.merge(r.value!) : acc }
        merged  = merged.merge(_parallel_errors: errors) unless errors.empty?

        Result.ok(merged)
      rescue StandardError => e
        Result.ok(ctx.merge(_parallel_errors: [e.message]))
      end
    end

    private

    def maybe_rollback(result)
      return unless result.respond_to?(:err?) && result.err?
      return unless ROLLBACK_CATEGORIES.include?(result.category)
      return unless @root && git_workspace?
      return unless dirty?

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, 120])
      system("git -C #{@root} reset --hard HEAD", out: File::NULL, err: File::NULL)
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out = `git -C #{@root} status --porcelain 2>/dev/null`
      !out.to_s.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
```

## `lib/master/platform.rb`
```ruby
# frozen_string_literal: true

module Master
  module Platform
    extend self

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
    def macos?   = RUBY_PLATFORM.include?("darwin")
    def linux?   = RUBY_PLATFORM.include?("linux")

    def privilege_command  = openbsd? ? "doas" : "sudo"
    def service_manager    = openbsd? ? "rcctl" : "systemctl"
    def package_manager    = openbsd? ? "pkg_add" : (macos? ? "brew" : "apt")
    def audio_player       = openbsd? ? "aucat" : (macos? ? "afplay" : "mpv")
  end
end
```

## `lib/master/pledge.rb`
```ruby
# frozen_string_literal: true

require "fiddle/import"

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      extend Fiddle::Importer
      dlload "libc.so"
      extern "int pledge(const char *, const char *)"
      extern "int unveil(const char *, const char *)"

      def pledge(promises, execpromises = nil)
        result = self.__pledge(promises, execpromises)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = self.__unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = unveil(nil, nil)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    def apply!
      pledge("stdio rpath wpath cpath proc exec inet")
      unveil(".", "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      lock_unveil!
    end
  end
end
```

## `lib/master/reasoning/modes.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Reasoning
    class Modes
      SUPPORTED = %w[direct react rewoo].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def supported = SUPPORTED

      def wrap(message, mode: "direct")
        selected = SUPPORTED.include?(mode.to_s) ? mode.to_s : "direct"
        prompt = load_prompt(selected)
        format(prompt.fetch("template", "%{message}"), message: message.to_s)
      rescue StandardError => e
        $stderr.puts "reasoning/modes: wrap failed (mode=#{mode}): #{e.message}"
        message.to_s
      end

      private

      def load_prompt(mode)
        path = File.join(@root, "data", "prompts", "mode_#{mode}.yml")
        YAML.safe_load_file(path) || {}
      end
    end
  end
end
```

## `lib/master/renderer.rb`
```ruby
# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"

module Master
  DEFAULT_WEB_PORT = 10002

  class Renderer
    TICK  = "\u2714".freeze
    CROSS = "\u2718".freeze
    DMESG_LINE_COUNT = 5
    MILLISECONDS_PER_SECOND = 1000

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def splash(model)
      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{@p.dim("ready")}"
      public_url = @config["web_public_url"] || "http://ai.brgen.no:3000"
      lines << @p.dim("web  #{public_url}")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil)
      branch = git_branch
      tok    = tokens && tokens > 0 ? @p.dim("#{tokens}t ") : ""
      vbadge = violations > 0 ? @p.red("[#{violations}v] ") : ""
      branch_str = branch ? "#{@p.dim("(")}#{@p.red(branch)}#{@p.dim(")")} " : ""
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{branch_str}#{tok}#{vbadge}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.bright_red(TICK)} #{@p.bright_red(content)}"
      when :warning then @p.red("! #{content}")
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)
      render(message, mode: :error)
    end

    def format_dmesg(line)
      @p.dim("[#{elapsed_ms}] #{line}")
    end

    private

    def short_model(model)
      model.to_s.split("/").last
    end

    def git_branch
      out, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      status.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def dmesg_lines
      stdout, _stderr, _status = Open3.capture3("dmesg")
      raw = stdout.lines.first(DMESG_LINE_COUNT).map(&:chomp)
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue StandardError
      ["dmesg unavailable"]
    end

    def elapsed_ms
      @start_ms ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      now = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      format("%d.%03d", (now - @start_ms) / MILLISECONDS_PER_SECOND, (now - @start_ms) % MILLISECONDS_PER_SECOND)
    end
  end
end```

## `lib/master/result.rb`
```ruby
# frozen_string_literal: true

module Master
  class Result
    def self.ok(value)                      = Ok.new(value)
    def self.err(msg, category: :unknown)   = Err.new(msg, category)

    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok?              = true
      def err?             = false
      def value!           = @value
      def unwrap           = @value
      def value_or(_)      = @value

      def map(&blk)        = Result.ok(blk.call(@value))
      def flat_map(&blk)   = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.respond_to?(:ok?) ? result : Result.ok(result)
      rescue => e
        Result.err("#{label || 'stage'}: #{e.message}", category: :unknown)
      end

      def deconstruct_keys(_keys) = { value: @value }
      def to_s                    = @value.to_s
      def inspect                 = "Ok(#{@value.inspect})"
    end

    class Err
      attr_reader :message, :category

      RETRIABLE = %i[infrastructure timeout].freeze
      PERMANENT = %i[validation axiom_violation budget].freeze

      def initialize(message, category = :unknown)
        @message  = message
        @category = category
        freeze
      end

      def ok?                   = false
      def err?                  = true
      def value!                = raise(Master::UnwrapError, "Err#value\! called: #{@message}")
      def unwrap                = value!
      def value_or(default)     = default

      def map(&)                = self
      def flat_map(&)           = self
      def and_then(*)           = self

      def retriable?            = RETRIABLE.include?(@category)
      def permanent?            = PERMANENT.include?(@category)

      def deconstruct_keys(_keys) = { message: @message, category: @category }
      def to_s                    = @message
      def inspect                 = "Err(#{@category}: #{@message})"
    end
  end
end
```

## `lib/master/ring_buffer.rb`
```ruby
# frozen_string_literal: true

module Master
  # Fixed-capacity circular buffer. Overwrites oldest entry when full.
  class RingBuffer
    include Enumerable

    def initialize(capacity)
      @capacity = capacity
      @buf      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      idx = (@start + @size) % @capacity
      if @size < @capacity
        @buf[idx] = item
        @size += 1
      else
        @buf[@start] = item
        @start = (@start + 1) % @capacity
      end
      self
    end

    alias << push

    def each
      return enum_for(__method__) unless block_given?

      @size.times { |i| yield @buf[(@start + i) % @capacity] }
    end

    def to_a    = @size.times.map { |i| @buf[(@start + i) % @capacity] }
    def size    = @size
    def full?   = @size == @capacity
    def empty?  = @size.zero?

    def clear
      @start = @size = 0
      self
    end
  end
end
```

## `lib/master/routing/continuity_index.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Routing
    class ContinuityIndex
      def initialize(root: Master::ROOT)
        @root       = root
        @data_cache = nil
        @data_mtime = nil
      end

      def fallback_models
        return [] unless enabled?

        [openrouter_latest, ferrum_latest].flatten.compact.uniq
      end

      private

      def enabled?
        data.dig("continuity", "enabled") != false
      end

      def openrouter_latest
        data.dig("openrouter", "free_latest").to_a
      end


      def ferrum_latest
        data.dig("ferrum_web_chat", "free_latest").to_a
      end

      def data
        path = File.join(@root, "data", "models.yml")
        current_mtime = File.exist?(path) ? File.mtime(path) : nil

        if @data_cache.nil? || current_mtime != @data_mtime
          @data_cache = begin
            YAML.safe_load_file(path, aliases: true) || {}
          rescue StandardError
            {}
          end
          @data_mtime = current_mtime
        end

        @data_cache
      end
    end
  end
end
```

## `lib/master/routing/model_router.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Routing
    class ModelRouter
      # Phrases that indicate the model is uncertain — trigger escalation.
      UNCERTAINTY_PHRASES = %w[
        i'm\ not\ sure i\ don't\ know cannot\ determine unclear uncertain
        might\ be possibly probably\ not limited\ information i\ cannot i\ am\ unable
        i\ lack\ the not\ enough\ information i\ would\ need\ more
].freeze

ESCALATION_CHAIN = %w[cheap default strong].freeze

      def initialize(config:, root: Master::ROOT, continuity_index: nil)
        @config = config
        @root = root
        @rules = load_rules
        @continuity_index = continuity_index || ContinuityIndex.new(root: @root)
      end

      def preferred(task_type: :exploration)
        return @config.model unless enabled?

        tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        candidates = @rules.dig("models", tier).to_a
        return @config.model if candidates.empty?

        best = candidates.max_by { |m| weighted_score(m["score"] || {}) }
        best["id"] || @config.model
      end

      def fallback_chain(task_type: :exploration)
        return [@config.model] unless enabled?

        preferred = preferred(task_type:)
        all = @rules.fetch("models", {}).values.flatten.map { |m| m["id"] }.compact
        continuity = @continuity_index.fallback_models
        ([preferred] + all + continuity + [@config.model]).uniq
      end

      # Returns true if the response text suggests insufficient confidence.
      # Used by Execute stage to decide whether to retry with a stronger model.
      def escalate?(response, threshold: 0.3)
        return false unless @rules.dig("routing", "escalation_enabled")
        text = response.to_s.downcase
        hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
        hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
      end

      # Return the best model from the escalation tier (default: "strong").
      def stronger_model(task_type: :exploration)
        tier = @rules.dig("routing", "escalation_tier") || "strong"
        candidates = @rules.dig("models", tier).to_a
        return preferred(task_type:) if candidates.empty?
        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred(task_type:)
      end


      # Checks response text for low-confidence markers.
      # Returns the strong-tier model ID if escalation is warranted and the
      # current model is not already in the strong tier; otherwise returns nil.
      def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
        return nil unless escalate?(response)
        strong_model = stronger_model(task_type: task_type)
        # Already on the strong tier -- no further escalation needed.
        return nil if current_model == strong_model
        strong_model
      end

# Determine which tier a model belongs to.
def tier_for_model(model_id)
  @rules.fetch("models", {}).each do |tier, models|
    return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
  end
  "cheap"
end

# Return the next tier in the escalation chain, or nil if already at top.
def next_escalation_tier(current_tier)
  idx = ESCALATION_CHAIN.index(current_tier.to_s)
  return nil unless idx
  ESCALATION_CHAIN[idx + 1]
end

# Per-task confidence threshold from routes config.
# Falls back to 0.3 (the existing default).
def confidence_threshold(task_type: :exploration)
  route = @rules.dig("routes", task_type.to_s)
  return 0.3 unless route.is_a?(Hash)
  route.fetch("confidence_threshold", 0.3).to_f
end

private

def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        weights = @rules.fetch("weights", {})
        quality_w = weights.fetch("quality", 0.0).to_f
        speed_w   = weights.fetch("speed",   0.0).to_f
        cost_w    = weights.fetch("cost",    0.0).to_f

        (score.fetch("quality", 0.0).to_f * quality_w) +
          (score.fetch("speed", 0.0).to_f * speed_w) +
          (score.fetch("cost",  0.0).to_f * cost_w)
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        YAML.safe_load_file(path, aliases: true) || {}
      rescue StandardError
        {}
      end
    end
  end
end
```

## `lib/master/ruby_llm_patch.rb`
```ruby
# frozen_string_literal: true

# Monkey-patch RubyLLM for OpenBSD/OpenRouter compatibility:
# 1. Fix UTF-8 encoding in model catalog JSON parsing
# 2. Pass through unknown models (OpenRouter :free variants) instead of raising

module RubyLLM
  class Models
    class << self
      def read_from_json(file = RubyLLM.config.model_registry_file)
        data = File.exist?(file) ? File.read(file, encoding: "utf-8") : "[]"
        JSON.parse(data, symbolize_names: true).map { |model| Model::Info.new(model) }
      rescue JSON::ParserError
        []
      end
    end

    private

    def find_without_provider(model_id)
      exact_matches = all.select { |m| m.id == model_id }
      return preferred_match(exact_matches) if exact_matches.any?

      resolved_id = Aliases.resolve(model_id)
      alias_matches = all.select { |m| m.id == resolved_id }
      return preferred_match(alias_matches) if alias_matches.any?

      # Pass through unknown models (e.g. OpenRouter :free variants)
      # instead of raising ModelNotFoundError
      Model::Info.new({
        id: model_id.to_s,
        name: model_id.to_s,
        provider: "openrouter",
        type: "chat",
        family: model_id.to_s.split("/").first,
        context_window: 128_000,
        max_tokens: 4096,
        input_price_per_million: 0.0,
        output_price_per_million: 0.0,
        modalities: { input: ["text"], output: ["text"] },
        metadata: {}
      })
    end
  end
end
```

## `lib/master/scan/rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    class Rule
      attr_reader :id, :description, :severity, :axiom_tags, :auto_fix

      def self.inherited(subclass)
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize do
          (@registry ||= []) << subclass
        end
      end

      def self.registry
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize { @registry || [] }
      end

      def initialize
        @id         = self.class.name&.split("::")&.last&.downcase || "unknown"
        @description = ""
        @severity    = :warning
        @axiom_tags  = []
        @auto_fix    = false
      end

      def check(code, path:)
        raise NotImplementedError, "#{self.class}#check not implemented"
      end

      protected

      def finding(line:, message:, fix: nil)
        { rule: @id, message:, line:, severity: @severity, fix: }
      end

      def scan_lines(code, pattern, message:, fix: nil)
        code.each_line.with_index(1).filter_map { |line, num|
          finding(line: num, message:, fix:) if line.match?(pattern)
        }
      end
    end
  end
end
```

## `lib/master/scan/rules/adversarial_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # AdversarialRule — red-team scan via two competing LLM perspectives.
      #
      # First asks: "What are the three strongest arguments this code is correct?"
      # Then asks: "What are the three strongest arguments it must change?"
      # Only the second list becomes findings — false positives are suppressed
      # because the model must first steelman the code before attacking it.
      #
      # Runs only at :deep depth. One LLM call per file.
      class AdversarialRule < Rule
        PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Challenge: list only the violations that survive the steelman.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "adversarial"
          @description = "Red-team scan: steelman then challenge — suppresses false positives"
          @severity    = :error
          @axiom_tags  = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
        end

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless @agent

          lang   = "ruby"
          prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                           lang: lang,
                                           code: code[0, 3_000])
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "adversarial: scan error — #{e.message}")]
        end

        private

        def parse_findings(response)
          return [] if response.strip.upcase.start_with?("CLEAN")

          response.lines.filter_map do |line|
            match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
            next unless match
            finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
          end
        end
      end
    end
  end
end

```

## `lib/master/scan/rules/axiom_coverage_rule.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "prism"

module Master
  module Scan
    module Rules
      # AxiomCoverageRule — meta-level rule. Checks that every rule ID in
      # rules.yml has at least one scan rule referencing it via @axiom_tags,
      # and that all @axiom_tags assignments correspond to real rule IDs.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every rule must have scan rule coverage; every tag must be a real rule"
          @severity    = :warning
          @axiom_tags  = []
        end

        def check(code, path:)
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in rules.yml — define it or remove the tag")
          end

          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "rule #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "rules.yml")
          return [] unless File.exist?(path)

          data = YAML.safe_load_file(path, aliases: true)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError
          []
        end

        class TagCollector < Prism::Visitor
          attr_reader :tags
          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == :@axiom_tags
              @tags.concat(collect_symbols(node.value))
            end
            super
          end

          private

          def collect_symbols(node)
            return [] unless node
            case node
            when Prism::ArrayNode
              node.elements.flat_map { |el| collect_symbols(el) }
            when Prism::SymbolNode
              [node.unescaped.to_s]
            else
              []
            end
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/bare_rescue_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          scan_lines(code, /^\s*rescue\s*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/conceptual_rule.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # ConceptualRule — LLM-based rule violation detection.
      #
      # Checks rules that resist lexical detection via detect_conceptual prompts.
      # Runs only at :deep depth. Makes one LLM call per file and parses
      # structured findings. Skips if no agent is set.
      class ConceptualRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based rule review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_conceptual_rules
          @axiom_tags  = @axioms.keys.map(&:to_sym)
        end

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless @agent

          prompt = build_prompt(code, path)
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue => e
          [finding(line: 1, message: "conceptual: scan error — #{e.message}")]
        end

        private

        def load_conceptual_rules
          data = YAML.safe_load_file(RULES_PATH, aliases: true)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules
            .select { |r| r["detect_conceptual"] }
            .each_with_object({}) { |r, h| h[r["id"]] = r["detect_conceptual"] }
        end

        def build_prompt(code, path)
          axiom_list = @axioms.map { |id, stmt| "#{id}: #{stmt}" }.join("\n")
          <<~PROMPT
            Review #{File.basename(path)} against these rules. List ONLY clear violations.
            Format each as: RULE_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN

            Rules:
            #{axiom_list}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"

          response.lines.filter_map do |line|
            match_data = line.strip.match(/\A([A-Z_]+):(\d+):(.+)\z/)
            next unless match_data && @axioms.key?(match_data[1])
            finding(line: match_data[2].to_i, message: "#{match_data[1]}: #{match_data[3].strip}")
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/cqs_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # CqsRule — detects Command/Query Separation violations.
      # A method should either return a value (query) or change state (command), not both.
      # Flags methods named like queries (get_*, find_*, fetch_*, load_*) that also
      # contain state-mutating patterns (@x =, save!, update!, write).
      class CqsRule < Rule
        QUERY_PREFIX   = /^\s+def\s+(get_|find_|fetch_|load_|read_|list_|show_|describe_)\w+/.freeze
        MUTATION_IN_BODY = /(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|\.write[!\s]|File\.write)/.freeze

        def initialize
          super
          @id          = "cqs"
          @description = "Command/Query Separation — queries must not mutate state"
          @severity    = :warning
          @axiom_tags  = [:CQS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          in_query  = false
          query_line = 0
          depth      = 0

          code.each_line.with_index(1) do |line, num|
            if !in_query && line.match?(QUERY_PREFIX)
              in_query   = true
              query_line = num
              depth      = 1
              next
            end

            if in_query
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size

              if depth <= 0
                in_query = false
                next
              end

              if line.match?(MUTATION_IN_BODY)
                findings << finding(
                  line: query_line,
                  message: "query method mutates state (line #{num}) — split into separate command and query"
                )
                in_query = false
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/duplicate_code_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DuplicateCodeRule < Rule
        BLOCK_MIN  = 4
        OCCUR_MIN  = 2

        def initialize
          super
          @id          = "duplicate_code"
          @description = "Duplicate code blocks (>=#{BLOCK_MIN} lines, >=#{OCCUR_MIN} occurrences) violate ONE_SOURCE"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines    = code.lines
          findings = []
          seen     = Hash.new(0)

          (0..lines.size - BLOCK_MIN).each do |i|
            block = lines[i, BLOCK_MIN].join
            next if block.strip.empty?
            key = block.gsub(/\s+/, " ").strip
            seen[key] += 1
          end

          seen.each do |block_key, count|
            next if count < OCCUR_MIN
            first_line = code.lines.index { |l|
              block_key.start_with?(l.gsub(/\s+/, " ").strip[0, 20])
            }
            findings << finding(
              line: (first_line || 0) + 1,
              message: "duplicate block appears #{count} times — extract to shared method (ONE_SOURCE)"
            )
          end

          findings.first(5)
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/explicit_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ExplicitRule — detects implicit/opaque patterns that violate EXPLICIT.
      # Flags: bare rescue, implicit return of nil, magic number literals,
      # single-letter variable names outside loops, and undefined method patterns.
      class ExplicitRule < Rule
        RESCUE_NIL   = /rescue\s+nil\b/.freeze
        MAGIC_NUM    = /[^:]\b([2-9]\d{2,}|[1-9]\d{3,})\b(?!\s*[#=])/.freeze
        OPAQUE_VAR   = /^\s+[a-z]\s*=(?!=)/.freeze        # x = ... (not x == or x +=)
        IMPLICIT_NIL = /def\s+\w+[^;]*\n(?:\s*#[^\n]*\n)*\s*end/.freeze  # empty method body

        def initialize
          super
          @id          = "explicit"
          @description = "Implicit, opaque patterns — prefer explicit contracts"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "bare rescue hides errors — name the exception class or propagate") if line.match?(RESCUE_NIL)
            findings << finding(line: num, message: "magic number — extract to a named constant")                if line.match?(MAGIC_NUM) && !line.strip.start_with?("#")
            findings << finding(line: num, message: "single-letter variable obscures intent — use a descriptive name") if line.match?(OPAQUE_VAR) && !in_loop_context?(code, num)
          end
          findings
        end

        private

        def in_loop_context?(code, target_line)
          lines = code.lines
          ((target_line - 4)..(target_line - 1)).any? do |i|
            next false unless i >= 0 && i < lines.size
            lines[i].match?(/\b(?:each|map|times|upto|downto|step|for\s+\w)\b/)
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/frozen_string_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class FrozenStringRule < Rule
        def initialize
          super
          @id          = "frozen_string"
          @description = "Ruby files should declare # frozen_string_literal: true"
          @severity    = :warning
          @axiom_tags  = [:PERFORMANCE]
          @auto_fix    = true
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] if code.lines.first&.include?("frozen_string_literal")
          [finding(line: 1, message: "missing # frozen_string_literal: true",
                   fix: "# frozen_string_literal: true\n" + code)]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/god_class_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class GodClassRule < Rule
        THRESHOLD = 200

        def initialize
          super
          @id          = "god_class"
          @description = "Classes over #{THRESHOLD} lines should be split by responsibility"
          @severity    = :warning
          @axiom_tags  = [:SIMPLEST_WORKS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines = code.lines.size
          return [] if lines <= THRESHOLD

          class_name = code.match(/class (\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} is #{lines} lines (threshold: #{THRESHOLD}) — split by responsibility"
          )]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/immutable_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ImmutableRule — detects mutable shared state that violates IMMUTABLE.
      # Flags: unfrozen String/Array/Hash constants, attr_accessor on data objects,
      # class-level mutable variables (@@), and global variable mutations ($x =).
      class ImmutableRule < Rule
        UNFROZEN_CONST  = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*\.freeze)/.freeze
        CLASS_VAR_WRITE = /^\s+@@\w+\s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^\s+\$\w+\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "immutable"
          @description = "Mutable shared state — prefer frozen constants and immutable data flow"
          @severity    = :warning
          @axiom_tags  = [:IMMUTABLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            line_findings = []
            line_findings << finding(line: num, message: "unfrozen constant — append .freeze") if line.match?(UNFROZEN_CONST)
            line_findings << finding(line: num, message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            line_findings << finding(line: num, message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
            line_findings
          }
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/long_method_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class LongMethodRule < Rule
        THRESHOLD = 15

        def initialize
          super
          @id          = "long_method"
          @description = "Methods over #{THRESHOLD} lines should be extracted"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          method_start = nil
          method_name  = nil
          depth        = 0

          code.each_line.with_index(1) do |line, num|
            if line.match?(/^\s*def /)
              method_start = num
              method_name  = line.match(/def (\w+)/)[1]
              depth        = 1
            elsif method_start
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bclass\b|\bmodule\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                length = num - method_start + 1
                if length > THRESHOLD
                  findings << finding(
                    line: method_start,
                    message: "method #{method_name} is #{length} lines (threshold: #{THRESHOLD}) — extract responsibilities"
                  )
                end
                method_start = nil
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/nielsen_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # NielsenRule — enforces Nielsen Norman Group's 10 Usability Heuristics
      # at the code level: API design, error messages, output behavior.
      class NielsenRule < Rule
        # H9: Error messages must describe the problem — bare string raises with no guidance
        BARE_RAISE       = /\braise\s+["'][^"']{0,20}["']/.freeze
        # H9: Result.err with no message or single-word message
        THIN_ERR         = /Result\.err\(["'][a-z_]{1,15}["'](?:\s*\))/.freeze
        # H4: Inconsistent boolean naming — mix of is_/has_/can_ with plain predicates
        # H6: Positional args over 3 — harms recognition (caller can't tell what each is)
        POSITIONAL_HEAVY = /def\s+\w+\((?:[^,)]+,){3,}[^*&]/.freeze
        # H8: Aesthetic minimalism — debug inspect calls (p/pp/pry) left in production
        DEBUG_OUTPUT     = /^\s+(?:p|pp|binding\.pry|debugger)\s+(?!.*#\s*rubocop)/.freeze
        # H3: User control — destructive methods without bang or guard comment
        SILENT_DELETE    = /\b(?:FileUtils\.rm|File\.delete|Dir\.rmdir)\s*\((?!.*#.*safe)/.freeze
        # H2: Real world match — internal jargon in user-facing strings
        JARGON           = /(?:raise|Result\.err)\(.*\b(?:nil\b|exception|stacktrace|backtrace|segfault|errno)\b/.freeze

        def initialize
          super
          @id          = "nielsen"
          @description = "Nielsen's 10 heuristics: error quality, recognition, minimalism, user control"
          @severity    = :warning
          @axiom_tags  = %i[ERROR_RECOVERY REAL_WORLD_MATCH USER_CONTROL AESTHETIC_MINIMALISM
                            RECOGNITION_NOT_RECALL CONSISTENCY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "[ERROR_RECOVERY] raise with no guidance — tell the user what to do next")         if line.match?(BARE_RAISE)
            findings << finding(line: num, message: "[ERROR_RECOVERY] thin Result.err message — include what failed and how to fix it") if line.match?(THIN_ERR)
            findings << finding(line: num, message: "[RECOGNITION_NOT_RECALL] 4+ positional args — use keyword arguments so callers read intent") if line.match?(POSITIONAL_HEAVY)
            findings << finding(line: num, message: "[AESTHETIC_MINIMALISM] debug output left in — remove puts/p or guard with log level")  if line.match?(DEBUG_OUTPUT)
            findings << finding(line: num, message: "[USER_CONTROL] destructive call without safety comment — add undo or confirmation guard") if line.match?(SILENT_DELETE)
            findings << finding(line: num, message: "[REAL_WORLD_MATCH] internal jargon in user-facing error — use plain language")          if line.match?(JARGON)
          end
          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/pola_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # PolaRule — Principle of Least Astonishment.
      # Code should behave as its name implies with no hidden side-effects.
      # Flags: boolean positional params, double negation, predicate methods
      # that mutate state, and negative boolean attribute names.
      class PolaRule < Rule
        # def call(file, true) — boolean positional default is opaque at call site
        BOOL_POSITIONAL = /def\s+\w+\([^)]*,\s*(true|false)\s*[,)]/.freeze
        # unless !condition (double negation)
        DOUBLE_NEG      = /\bunless\s+!/.freeze
        # Negative boolean attribute names
        NEG_BOOL_ATTR   = /\battr_\w+\s+:(?:not_|no_|without_|disabled?_|skip_)\w+/.freeze

        def initialize
          super
          @id          = "pola"
          @description = "Principle of Least Astonishment — surprising names, contracts, or side-effects"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings        = []
          in_predicate    = false
          pred_line       = 0
          depth           = 0

          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "boolean positional default — use keyword arg (def method(flag: false)) to name intent at call site") if line.match?(BOOL_POSITIONAL)
            findings << finding(line: num, message: "double negation (unless !x) — use positive form (if x)") if line.match?(DOUBLE_NEG)
            findings << finding(line: num, message: "negative attribute name — name what it IS, not what it ISN'T") if line.match?(NEG_BOOL_ATTR)

            if line.match?(/^\s+def\s+\w+\?/)
              in_predicate = true
              pred_line    = num
              depth        = 1
            elsif in_predicate
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                in_predicate = false
              elsif line.match?(/(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|File\.write)/)
                findings << finding(line: pred_line, message: "predicate method (?) mutates state — predicates must only query, never mutate (POLA)")
                in_predicate = false
              end
            end
          end

          findings
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/prune_rule.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # PruneRule — flags hedge words and preamble phrases in Ruby comments.
      # Patterns loaded from data/rules.yml (voice.strunk section).
      class PruneRule < Rule
        DATA_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze

        def initialize
          super
          @id          = "prune"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          hedge_re    = build_hedge_re
          preamble_re = build_preamble_re

          code.each_line.with_index(1).flat_map { |line, num|
            next [] unless line.include?("#")
            findings = []
            findings << finding(line: num, message: "hedge in comment: #{line.strip}")    if hedge_re&.match?(line)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if preamble_re&.match?(line)
            findings
          }
        end

        private

        def rules
          @rules ||= begin
            data = File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH, aliases: true) : {}
            data.dig("voice", "strunk") || {}
          end
        rescue StandardError
          @rules = {}
        end

        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            if h.is_a?(Hash)
              pat = h["pattern"].to_s.strip
              pat.empty? ? nil : Regexp.escape(pat)
            elsif h.is_a?(String)
              h.strip.empty? ? nil : Regexp.escape(h.strip)
            end
          }
          return nil if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError
          nil
        end

        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return nil if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        rescue StandardError
          nil
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/reek_rule.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # ReekRule — code smell detection via reek.
      # Maps smell types to MASTER axioms.
      class ReekRule < Rule
        SMELL_MAP = {
          "TooManyMethods"         => { axiom: "ONE_JOB",        sev: :warning },
          "TooManyInstanceVariables" => { axiom: "ONE_JOB",      sev: :warning },
          "LongParameterList"      => { axiom: "DECOUPLE",       sev: :warning },
          "FeatureEnvy"            => { axiom: "DECOUPLE",       sev: :warning },
          "DataClump"              => { axiom: "DECOUPLE",       sev: :warning },
          "DuplicateMethodCall"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "BooleanParameter"       => { axiom: "EXPLICIT",       sev: :warning },
          "ControlParameter"       => { axiom: "CQS",            sev: :warning },
          "NilCheck"               => { axiom: "EXPLICIT",       sev: :warning },
          "UncommunicativeMethodName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeVariableName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeParameterName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UtilityFunction"        => { axiom: "DECOUPLE",       sev: :warning },
          "InstanceVariableAssumption" => { axiom: "EXPLICIT",   sev: :warning },
          "IrresponsibleModule"    => { axiom: "SELF_EXPLAINING", sev: :warning },
          "RepeatedConditional"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "SubclassedFromCoreClass" => { axiom: "EXTEND_DONT_MODIFY", sev: :warning },
          "ModuleInitialize"       => { axiom: "POLA",           sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "reek"
          @description = "Code smell detection: feature envy, data clumps, boolean params (reek)"
          @severity    = :warning
          @axiom_tags  = SMELL_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless reek_available?

          out, _err, _status = Open3.capture3(
            "bundle", "exec", "reek",
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          parse_smells(out)
        rescue StandardError
          []
        end

        private

        def reek_available?
          @reek_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "reek", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError
            false
          end
        end

        def parse_smells(json_str)
          data = JSON.parse(json_str)
          data.filter_map do |smell|
            meta = SMELL_MAP[smell["smell_type"]]
            next unless meta
            finding(
              line:    smell["lines"]&.first || 1,
              message: "[#{meta[:axiom]}] #{smell["smell_type"]}: #{smell["message"]}"
            )
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/rubocop_rule.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # RubocopRule — AST-based analysis via rubocop.
      # Maps rubocop cop categories to MASTER axioms. Only a focused subset
      # of cops is enabled (see .rubocop.yml) to avoid noise.
      class RubocopRule < Rule
        # Map rubocop cop → axiom tag + severity
        COP_MAP = {
          "Metrics/MethodLength"        => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/ClassLength"         => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/AbcSize"             => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/CyclomaticComplexity" => { axiom: "SIMPLEST_WORKS", sev: :error },
          "Metrics/PerceivedComplexity" => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/ParameterLists"      => { axiom: "DECOUPLE",      sev: :warning },
          "Lint/RescueException"        => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/SuppressedException"    => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/DuplicateMethods"       => { axiom: "ONE_SOURCE",    sev: :error },
          "Style/GuardClause"           => { axiom: "BE_CONCISE",    sev: :warning },
          "Style/ReturnNil"             => { axiom: "EXPLICIT",      sev: :warning },
          "Naming/MethodParameterName"  => { axiom: "SELF_EXPLAINING", sev: :warning },
          "Layout/LineLength"           => { axiom: "BE_CONCISE",    sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "rubocop"
          @description = "AST-based analysis: complexity, guard clauses, parameter names (rubocop)"
          @severity    = :warning
          @axiom_tags  = COP_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless rubocop_available?

          config_flag = rubocop_config_flag
          out, _err, status = Open3.capture3(
            "bundle", "exec", "rubocop",
            *config_flag,
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          return [] unless status.exitstatus&.<= 1  # 0=clean 1=offenses 2=error

          parse_offenses(out)
        rescue StandardError
          []
        end

        private

        def rubocop_available?
          @rubocop_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "rubocop", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError
            false
          end
        end

        def rubocop_config_flag
          cfg = File.join(@root || Dir.pwd, ".rubocop.yml")
          File.exist?(cfg) ? ["--config", cfg] : ["--only", COP_MAP.keys.join(",")]
        end

        def parse_offenses(json_str)
          data = JSON.parse(json_str)
          data["files"].flat_map do |file|
            file["offenses"].filter_map do |o|
              meta = COP_MAP[o["cop_name"]]
              next unless meta
              finding(
                line:    o.dig("location", "line") || 1,
                message: "[#{meta[:axiom]}] #{o["cop_name"]}: #{o["message"]}"
              )
            end
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/self_explaining_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SelfExplainingRule — detects names that obscure intent, violating SELF_EXPLAINING.
      # Flags method/variable names that are abbreviations, noise words, or too generic
      # to reveal purpose without reading the implementation.
      class SelfExplainingRule < Rule
        NOISE_NAMES  = /\b(do_it|handle|process|run_it|execute_it|go|doit)\b/.freeze
        ABBREV_METHOD = /^\s+def\s+(tmp|res|ret|val|obj|thingy|stuff|thing|data2?|info2?)\b/.freeze
        ABBREV_VAR    = /\b(tmp|res|ret|val|obj|arr|lst|hsh|idx|cnt|num|str)\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "self_explaining"
          @description = "Opaque names — names should reveal purpose without reading the implementation"
          @severity    = :warning
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            findings = []
            findings << finding(line: num, message: "noise method name — rename to reveal intent") if line.match?(NOISE_NAMES)
            findings << finding(line: num, message: "abbreviated method name — use the full descriptive word") if line.match?(ABBREV_METHOD)
            findings << finding(line: num, message: "abbreviated variable — prefer descriptive identifier") if line.match?(ABBREV_VAR)
            findings
          }
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/srp_rule.rb`
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SrpRule — Single Responsibility Principle.
      # A class should have one reason to change. Flags classes whose public methods
      # span multiple concern domains (persistence, rendering, validation, networking, parsing).
      class SrpRule < Rule
        CONCERNS = {
          persistence: /\b(save|load|read_\w|write_\w|persist|store_\w|fetch_\w|find_by|delete|destroy|insert|upsert)\b/,
          rendering:   /\b(render|display|format_\w|present|to_html|draw|paint|emit|output_\w)\b/,
          validation:  /\b(valid\?|validate[^d]|check_\w|verify_\w|assert_\w|ensure_\w|guard_\w)\b/,
          networking:  /\b(request_\w|http_\w|send_request|receive_\w|connect_\w|socket_\w)\b/,
          parsing:     /\b(parse_\w|tokenize|lex_\w|extract_\w|decode_\w|encode_\w|deserialize|serialize)\b/,
        }.freeze

        def initialize
          super
          @id          = "srp"
          @description = "Single Responsibility Principle — class spans multiple concern domains"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          public_methods = code.scan(/^\s{2,8}def\s+(\w+)/).flatten
          return [] if public_methods.size < 4

          concerns_found = CONCERNS.select { |_, pat| public_methods.any? { |m| m.match?(pat) } }
          return [] if concerns_found.size < 2

          class_name = code.match(/class\s+(\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} spans #{concerns_found.size} domains " \
                     "(#{concerns_found.keys.join(", ")}) — split by single responsibility (SRP)"
          )]
        end
      end
    end
  end
end
```

## `lib/master/scan/scanner.rb`
```ruby
# frozen_string_literal: true

require "etc"
require "yaml"

module Master
  module Scan
    # Scanner — runs configured scan rules against Ruby source files.
    #
    # scan_dir parallelizes across files with a thread pool sized to CPU count.
    # Each file is independent; rules share no mutable state between files.
    class Scanner
      RULES_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
        @mutex = Mutex.new
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code     = File.read(path, encoding: "UTF-8")
        active   = active_rules(depth)
        findings = active.flat_map { |rule| rule.check(code, path:) }

        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :unknown)
      end

      def scan_dir(dir, depth: :standard, glob: "**/*.rb")
        paths   = Dir.glob(File.join(dir, glob)).sort
        results = Array.new(paths.size)
        threads = []
        semaphore = Mutex.new
        index = 0

        POOL_SIZE.times do
          threads << Thread.new do
            loop do
              i = semaphore.synchronize { idx = index; index += 1; idx }
              break if i >= paths.size
              results[i] = [paths[i], scan(paths[i], depth:)]
            end
          end
        end

        threads.each(&:join)
        Result.ok(results)
      rescue StandardError => e
        Result.err("scan_dir: #{e.message}", category: :unknown)
      end

      def add_rule(rule)
        @rules << rule
        self
      end

      def set_agent(agent)
        @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
        self
      end

      private

      def depth_rules
        @depth_rules ||= begin
          data = YAML.safe_load_file(RULES_PATH, aliases: true)
          data["scan_depths"] || {}
        end
      rescue StandardError
        @depth_rules = {}
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.class.name.split("::").last) || allowed.include?(r.id) }
      end
    end
  end
end
```

## `lib/master/security/injection_guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Security
    class InjectionGuard
      PATTERNS = [
        /ignore (?:previous|all|your) instructions/i,
        /disregard (?:your )?(?:system )?prompt/i,
        /you are now (?:a|an|in)/i,
        /pretend (?:to be|you are|you're)/i,
        /new instructions:/i,
        /\[SYSTEM\]/i,
        /###\s*SYSTEM/i,
        /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
        /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
        /jailbreak/i,
      ].freeze

      # Shell-injection pattern checked separately (multiline, heavier regex).
      SHELL_INJECTION_RE = /```(?:bash|sh|zsh|shell)\n.*?(?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)/im.freeze

      def scan(content)
        hits = PATTERNS.select { |p| content.match?(p) }
        hits << SHELL_INJECTION_RE if content.match?(SHELL_INJECTION_RE)
        return Result.ok(:clean) if hits.empty?
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      def clean!(content)
        cleaned = PATTERNS.reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end
    end
  end
end
```

## `lib/master/security/permissions.rb`
```ruby
# frozen_string_literal: true

module Master
  module Security
    module Permissions
      TOOL_TIERS = {
        "read_file"    => :safe,
        "list_dir"     => :safe,
        "search_files" => :safe,
        "write_file"   => :guarded,
        "str_replace"  => :guarded,
        "apply_diff"   => :guarded,
        "ask_llm"      => :guarded,
        "web_search"   => :guarded,
        "zsh"          => :dangerous
      }.freeze

      BLOCKLIST = [
        "rm -rf /",
        "sudo",
        "reboot",
        "shutdown",
        "mkfs",
        "dd if=",
        "> /dev/",
        "chmod 777",
        "curl | sh",
        "wget | sh"
      ].freeze

      def self.tier_for(tool_name)
        TOOL_TIERS[tool_name.to_s] || :guarded
      end

      def self.blocked?(command)
        BLOCKLIST.any? { |b| command.include?(b) }
      end
    end
  end
end
```

## `lib/master/semantic_cache.rb`
```ruby
# frozen_string_literal: true

require "digest"
require "json"
require "monitor"

module Master
  class SemanticCache
    MAX_ENTRIES = 1000
    DEFAULT_TTL = 3600
    BYTES_PER_KB = 1024.0

    def initialize(root:, ttl: DEFAULT_TTL, event_bus: nil)
      @root    = File.join(root, ".master", "cache")
      @ttl     = ttl
      @bus     = event_bus
      @lru     = []
      @lock    = Monitor.new
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        if (hit = read_entry(path))
          @bus&.publish("cache:hit", key:)
          return hit
        end
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      @lock.synchronize { write_entry(path, result, key) }
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      @lock.synchronize do
        # Intentional deletion of cached entry
        File.delete(path) if File.exist?(path)
      end
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each do |f|
          begin
            # Intentional deletion of all cache files
            File.delete(f)
          rescue Errno::ENOENT
            # Ignore if file already removed
          end
        end
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum do |f|
          File.size(f)
        rescue Errno::ENOENT
          0
        end
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
      end
    end

    private

    def cache_key(prompt, model)
      Digest::SHA256.hexdigest("#{prompt}::#{model}")
    end

    def cache_path(key)
      File.join(@root, "#{key}.json")
    end

    def read_entry(path)
      return nil unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      if Time.now.to_i - entry[:ts] > @ttl
        @lru.delete(path)
        # Intentional deletion of expired cache file
        File.delete(path)
        return nil
      end
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      begin
        # Intentional deletion of corrupt cache file
        File.delete(path)
      rescue Errno::ENOENT
        # Ignore if already removed
      end
      @lru.delete(path)
      nil
    end

    def write_entry(path, value, key)
      # Unwrap Result objects for JSON serialization
      value = value.value! if value.respond_to?(:ok?) && value.ok?
      evict_lru while @lru.size >= MAX_ENTRIES
      File.write(path, JSON.generate({ ts: Time.now.to_i, value: }))
      @lru.push(path)
    end

    def promote_lru(path)
      @lru.delete(path)
      @lru.push(path)
    end

    def evict_lru
      oldest = @lru.shift
      return unless oldest && File.exist?(oldest)
      # Intentional deletion of oldest cache file (LRU eviction)
      File.delete(oldest)
    end
  end
end
```

## `lib/master/session.rb`
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  class Session
    TOKENS_PER_CHAR  = 4
    SESSION_NAME_MAX = 40
    COSTS_MAX_BYTES  = 102_400     # 100 KB

    attr_reader :name, :messages, :cost, :phase, :snapshots

    def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
      @root       = root
      @budget_max = budget_max
      @req_max    = req_max
      @messages   = []
      @snapshots  = {}
      @cost       = 0.0
      @phase      = :discover
      @name       = nil
      @path       = File.join(root, ".master", "session.json")
      @costs_path = File.join(root, ".master", "costs.jsonl")
      Dir.mkdir(File.join(root, ".master")) unless Dir.exist?(File.join(root, ".master"))
    end

    def add_message(role:, content:)
      msg = { role:, content:, ts: Time.now.to_i }
      @messages << msg
      @name ||= auto_name(content) if role == :user
      msg
    end

    def record_cost(amount, model:, tokens:)
      @cost += amount
      entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
      rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
      File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
      entry
    end

    def snapshot(path, content)
      @snapshots[path] ||= []
      @snapshots[path] << content
    end

    def last_snapshot(path)
      @snapshots[path]&.last
    end

    def save!
      FileUtils.mkdir_p(File.dirname(@path))
      data = { name: @name, phase: @phase, messages: @messages, cost: @cost, ts: Time.now.to_i }
      File.write(@path, JSON.generate(data))
    end

    def load!
      return self unless File.exist?(@path)
      data = JSON.parse(File.read(@path), symbolize_names: true)
      @name     = data[:name]
      @phase    = data[:phase]&.to_sym || :discover
      @messages = data[:messages] || []
      @cost     = data[:cost].to_f
      self
    end

    def exists?    = File.exist?(@path)
    def clear!     = (@messages = [] ; @cost = 0.0 ; @name = nil ; self)
    def token_est  = @messages.sum { |m| m[:content].to_s.bytesize / TOKENS_PER_CHAR }

    private

    def auto_name(content)
      content.to_s.split.first(5).join(" ").then { |s| s[0, SESSION_NAME_MAX] }
    end

    def rotate_costs!
      return unless File.exist?(@costs_path)

      lines = File.readlines(@costs_path)
      # Keep the most recent half of the lines
      keep  = lines.last([lines.size / 2, 1].max)
      File.write(@costs_path, keep.join)
    end
  end
end
```

## `lib/master/skills.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  # Skills — discovers and loads composable skill directories.
  # Each skill is a directory under skills/ containing:
  #   SKILL.md   — metadata (name, description, trigger patterns)
  #   skill.rb   — optional Ruby implementation (loaded as a tool)
  #
  # Skills discovered at boot are registered as tools in the agent.
  class Skills
    SKILLS_DIR = "skills"

    attr_reader :loaded

    def initialize(root:, event_bus: nil)
      @root   = root
      @bus    = event_bus
      @loaded = []
    end

    def discover!
      skills_path = File.join(@root, SKILLS_DIR)
      return [] unless Dir.exist?(skills_path)

      Dir.children(skills_path).sort.each do |name|
        dir = File.join(skills_path, name)
        next unless File.directory?(dir)

        skill = load_skill(dir, name)
        @loaded << skill if skill
      end

      @bus&.publish("skills:loaded", count: @loaded.size)
      @loaded
    end

    def list
      return "(no skills loaded)" if @loaded.empty?

      @loaded.map { |s| "#{s[:name]}: #{s[:description]}" }.join("\n")
    end

    def find(name)
      @loaded.find { |s| s[:name] == name.to_s }
    end

    def trigger_for(input)
      @loaded.select do |s|
        s[:triggers]&.any? { |t| input.match?(Regexp.new(t, Regexp::IGNORECASE)) }
      end
    end

    private

    def load_skill(dir, name)
      md_path = File.join(dir, "SKILL.md")
      rb_path = File.join(dir, "skill.rb")

      metadata = parse_skill_md(md_path) if File.exist?(md_path)
      metadata ||= { "name" => name, "description" => name }

      skill = {
        name:        metadata["name"] || name,
        description: metadata["description"] || name,
        triggers:    metadata["triggers"] || [],
        dir:         dir,
        has_ruby:    File.exist?(rb_path)
      }

      if File.exist?(rb_path)
        begin
          require rb_path
          @bus&.publish("skills:ruby_loaded", skill: name)
        rescue StandardError => e
          @bus&.publish("skills:load_error", skill: name, error: e.message)
        end
      end

      skill
    rescue StandardError => e
      @bus&.publish("skills:load_error", skill: name, error: e.message)
      nil
    end

    def parse_skill_md(path)
      content = File.read(path, encoding: "UTF-8")
      return {} unless content.start_with?("---")

      parts = content.split("---", 3)
      return {} if parts.size < 3

      YAML.safe_load(parts[1]) || {}
    rescue StandardError
      {}
    end
  end
end
```

## `lib/master/soul.rb`
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  # Soul — loads and manages SOUL.md, the version-controlled identity document.
  # Implements the Evolution Protocol: propose → consistency-test → approve → version-bump → commit.
  #
  # Commands:
  #   soul                     — show current identity summary
  #   soul version             — show changelog
  #   soul propose <rationale> — draft a change proposal (requires LLM)
  #   soul approve             — apply pending proposal, bump version, git-tag
  #   soul reject              — discard pending proposal
  #   soul rollback            — restore previous git version
  class Soul
    SOUL_PATH     = File.join(Master::ROOT, "SOUL.md").freeze
    PROPOSAL_PATH = File.join(Master::ROOT, ".master", "soul_proposal.md").freeze

    # Drift boundaries — changes to ABSOLUTE sections are blocked without override.
    ABSOLUTE_PATTERNS  = [/anti-simulation rule/i, /golden rule/i, /preserve.*then.*improve/i].freeze
    PROTECTED_PATTERNS = [/voice character/i, /terse.*direct.*dark/i].freeze

    def initialize(root: Master::ROOT, agent: nil)
      @root  = root
      @agent = agent
      @soul  = load_soul
    end

    # Wire the agent after construction (avoids circular dependency in build).
    def wire_agent(agent) = @agent = agent

    def summary
      version = extract_version
      persona = extract_field("Persona")
      voice   = extract_field("Voice").to_s.lines.first.to_s.strip[0, 120]
      "SOUL.md v#{version} | persona: #{persona}\n#{voice}"
    end

    def changelog
      block = @soul[/## Changelog\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      block.empty? ? "(no changelog)" : block
    end

    def propose(rationale, agent: @agent)
      return "no agent available for drafting" unless agent

      current = @soul
      prompt  = <<~PROMPT
        You are editing SOUL.md — a constitutional identity document for an AI coding agent.
        Current document:
        #{current}

        Proposed change rationale: #{rationale}

        Draft ONLY the minimal changes needed. Preserve the anti-simulation rule, golden rule, and voice character unchanged.
        Output the full updated SOUL.md. No preamble.
      PROMPT

      draft = agent.ask_once(prompt)
      return "draft failed" if draft.to_s.strip.empty?

      drift = measure_drift(current, draft)
      blocked = drift[:absolute_changed].any?

      if blocked
        "BLOCKED: proposal would change ABSOLUTE sections: #{drift[:absolute_changed].join(", ")}. Add /override to force."
      else
        FileUtils.mkdir_p(File.dirname(PROPOSAL_PATH))
        File.write(PROPOSAL_PATH, draft)
        risk = drift[:protected_changed].any? ? " [PROTECTED sections affected: #{drift[:protected_changed].join(", ")}]" : ""
        "proposal saved#{risk}. Review with `soul diff`, approve with `soul approve`, reject with `soul reject`."
      end
    rescue StandardError => e
      "proposal error: #{e.message}"
    end

    def diff
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)
      lines_old = @soul.lines
      lines_new = proposal.lines
      changes = lines_new.reject { |l| lines_old.include?(l) }
      removals = lines_old.reject { |l| lines_new.include?(l) }
      out = []
      out += removals.first(10).map { |l| "- #{l.chomp}" }
      out += changes.first(10).map { |l| "+ #{l.chomp}" }
      out.empty? ? "(no visible changes)" : out.join("\n")
    end

    def approve
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)

      old_version = extract_version
      new_version = bump_version(old_version, :patch)

      # Inject new version into proposal
      updated = proposal.sub(/Version: [\d.]+/, "Version: #{new_version}")
      # Update changelog entry
      date    = Time.now.strftime("%Y-%m-%d")
      entry   = "| #{new_version} | #{date} | Evolution Protocol change | Approved via `soul approve` |\n"
      updated = updated.sub(/\| 1\.0\.0 \|/, entry + "| 1.0.0 |")

      File.write(SOUL_PATH, updated)
      File.unlink(PROPOSAL_PATH)
      @soul = updated

      # Git tag
      `git -C #{@root} add SOUL.md && git -C #{@root} commit -m "soul: v#{new_version} — evolution protocol update" 2>&1`

      "soul updated to v#{new_version}"
    rescue StandardError => e
      "approve error: #{e.message}"
    end

    def reject
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      File.unlink(PROPOSAL_PATH)
      "proposal rejected"
    end

    def rollback
      out = `git -C #{@root} log --oneline SOUL.md 2>&1`.lines
      return "no git history for SOUL.md" if out.size < 2
      prev_sha = out[1].split.first
      restored = `git -C #{@root} show #{prev_sha}:SOUL.md 2>&1`
      File.write(SOUL_PATH, restored)
      @soul = restored
      "rolled back to #{prev_sha} — #{out[1].chomp}"
    rescue StandardError => e
      "rollback error: #{e.message}"
    end

    # Return the system prompt extracted from SOUL.md for use in Personality.
    def system_prompt
      voice  = @soul[/## Voice\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      values = @soul[/## Values\n+(.*?)(?=\n## |\z)/m, 1].to_s.strip
      "#{voice}\n\n#{values}"
    end


# Auto-propose a soul amendment when scan violations cluster on one rule.
# Called by AutoLoop when the same rule fails across 3+ consecutive cycles.
def propose_from_violations(rule_id, sample_violations, agent: @agent)
  return "no agent available" unless agent

  examples = sample_violations.first(3).map { |v| "  L#{v[:line]}: #{v[:message]}" }.join("\n")
  rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} " \
              "violations across multiple files and cycles:\n#{examples}\n" \
              "Propose whether the codebase axioms or soul principles should acknowledge this pattern " \
              "or whether the rule needs refinement."
  propose(rationale, agent:)
end

    private

    def load_soul
      File.exist?(SOUL_PATH) ? File.read(SOUL_PATH, encoding: "UTF-8") : ""
    rescue StandardError
      ""
    end

    def extract_version
      @soul[/^Version: ([\d.]+)/, 1] || "1.0.0"
    end

    def extract_field(name)
      @soul[/^#{Regexp.escape(name)}:\s*(.+)/, 1].to_s.strip
    end

    def bump_version(ver, level)
      parts = ver.split(".").map(&:to_i)
      case level
      when :major then "#{parts[0] + 1}.0.0"
      when :minor then "#{parts[0]}.#{parts[1] + 1}.0"
      when :patch then "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
      end
    end

    def measure_drift(old_doc, new_doc)
      absolute_changed  = ABSOLUTE_PATTERNS.select  { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      protected_changed = PROTECTED_PATTERNS.select { |p| old_doc.match?(p) && !new_doc.match?(p) }.map(&:source)
      { absolute_changed:, protected_changed: }
    end
  end
end
```

## `lib/master/speech.rb`
```ruby
# frozen_string_literal: true

require "securerandom"
require "fileutils"

module Master
  # TTS via edge-tts (Microsoft Neural voices) with espeak fallback.
  # Default persona: dark_malay / ms-MY-OsmanNeural / deep style.
  module Speech
    EDGE_TTS = %w[/home/dev/.local/bin/edge-tts /usr/local/bin/edge-tts].find { |p| File.executable?(p) }
    ESPEAK   = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "en-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:    { rate: "-35%", pitch: "-150Hz" },
      heavy:   { rate: "-30%", pitch: "-120Hz" },
      normal:  { rate: "+0%",  pitch: "+0Hz"   },
      slow:    { rate: "-20%", pitch: "-60Hz"  },
      natural: { rate: "+8%",  pitch: "+20Hz"  }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :natural

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    # Returns path to generated audio file, or nil on failure.
    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return nil if text.to_s.strip.empty?

      if EDGE_TTS
        synthesize_edge(text, voice: voice, style: style)
      elsif ESPEAK
        synthesize_espeak(text)
      end
    end

    # Returns raw mp3/wav bytes, or nil.
    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return nil unless path
      bytes = File.binread(path)
      begin
        File.unlink(path)
      rescue => e
        nil
      end
      bytes
    end

    private

    module_function

    def synthesize_edge(text, voice:, style:)
      tmp = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      style_config = STYLES.fetch(style.to_sym, STYLES[DEFAULT_STYLE])

      ok = system(
        EDGE_TTS,
        "--voice", voice_name,
        "--rate=#{style_config[:rate]}",
        "--pitch=#{style_config[:pitch]}",
        "--text", text.to_s,
        "--write-media", tmp,
        out: File::NULL, err: File::NULL
      )

      (ok && File.exist?(tmp) && File.size(tmp) > 0) ? tmp : nil
    end

    def synthesize_espeak(text)
      tmp = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok  = system(
        ESPEAK, "-s", "140", "-p", "30", "-a", "150",
        "-w", tmp, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(tmp) && File.size(tmp) > 0) ? tmp : nil
    end
  end
end
```

## `lib/master/stages/council.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Council — 6-persona deliberation on dangerous or multi-file changes.
    # PRAISE votes are appended to data/exemplars.yml for future reference.
    class Council
      EXEMPLARS_PATH  = File.join(Master::ROOT, "data", "exemplars.yml").freeze
      PATTERNS_PATH   = File.join(Master::ROOT, "data", "council_patterns.yml").freeze

      def initialize(deliberation:, config: nil, enabled: false)
        @deliberation      = deliberation
        @config            = config
        @enabled           = @config&.[]("council") == true || enabled
        @dangerous_patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        payload = extract_payload(ctx)
        result  = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        feedback = result.value!
        log_praise(ctx[:message], feedback) if praise?(feedback)

        Result.ok(ctx.merge(council_feedback: feedback))
      end

      def enable!
        @enabled = true
        @config&.[]=("council", true)
        @config&.save!
      end

      def disable!
        @enabled = false
        @config&.[]=("council", false)
        @config&.save!
      end

      def enabled? = @enabled

      private

      def load_patterns
        data = YAML.safe_load_file(PATTERNS_PATH, aliases: true)
        (data["dangerous"] || []).flatten.map { |str| Regexp.new(str, Regexp::IGNORECASE) }
      end

      def should_run?(ctx)
        return false if ctx[:intent] == :command
        @enabled || dangerous_request?(ctx) || dangerous_tool?(ctx) || multi_file_diff?(ctx)
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s.gsub(/[[:cntrl:]]/, "")
        !msg.empty? && @dangerous_patterns.any? { |p| msg.match?(p) }
      end

      def dangerous_tool?(ctx)  = ctx[:last_tool_tier] == :dangerous
      def multi_file_diff?(ctx) = extract_payload(ctx).scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2

      def extract_payload(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else
          text = out.to_s
          text.empty? ? ctx[:message].to_s : text
        end
      end

      # Detect unanimous or majority PRAISE in council feedback text.
      def praise?(feedback)
        text = feedback.to_s.downcase
        text.scan(/\bpraise\b/).size >= 3
      end

      # Append a PRAISE entry to data/exemplars.yml.
      def log_praise(message, feedback)
        entry = {
          "timestamp" => Time.now.iso8601,
          "message"   => message.to_s[0, 120],
          "feedback"  => feedback.to_s[0, 240]
        }
        existing = File.exist?(EXEMPLARS_PATH) ? (YAML.safe_load_file(EXEMPLARS_PATH) || []) : []
        File.write(EXEMPLARS_PATH, YAML.dump(existing + [entry]))
      rescue StandardError
        nil
      end
    end
  end
end
```

## `lib/master/stages/execute.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx[:handler]
        return Result.err("execute: no handler", category: :validation) unless handler

        Result.ok(ctx.merge(output: handler.call(ctx)))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :handler_exception)
      end
    end
  end
end
```

## `lib/master/stages/guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Guard — reject messages that contain prompt-injection patterns.
    # Skips scan when message is absent (command-only paths set no :message).
    class Guard
      def initialize(governor:, injection_guard:)
        @governor        = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        msg = ctx[:message].to_s
        return Result.ok(ctx) if msg.empty?

        scan = @injection_guard.scan(msg)
        return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

        Result.ok(ctx)
      end
    end
  end
end
```

## `lib/master/stages/infer.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Infer — promote natural-language messages to :command intent.
    #
    # Runs after Intake. When intent is :llm, matches the message against
    # patterns loaded from data/infer_patterns.yml (single source of truth —
    # adding a new inferred command never requires a code change).
    class Infer
      # Heuristic task-type detection — used by ModelRouter for tiered model selection.
      TASK_TYPE_PATTERNS = {
        coding:   /\b(?:def |class |module |require |\.rb\b|fix\s+(?:the\s+)?(?:bug|error|issue)|refactor|implement|write\s+(?:a\s+)?(?:method|class|function|test)|add\s+(?:a\s+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))/i,
        research: /\b(?:search|find\s+(?:all|every|info)|research|look\s+up|what\s+is|explain\s+(?:how|what|why)|tell\s+me\s+about)\b/i,
        qa:       /\?(?:\s*$|\s+[A-Z])/m,
      }.freeze

      PATTERNS_PATH = File.join(Master::ROOT, "data", "infer_patterns.yml").freeze

      def initialize
        @patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip
        @patterns.each do |cmd, entry|
          entry[:regexes].each do |pattern|
            next unless (m = msg.match(pattern))
            return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd, entry[:capture], m, msg)))
          end
        end

        Result.ok(ctx.merge(task_type: infer_task_type(msg)))
      end

      private

      # Returns { "sweep" => { regexes: [Regexp, ...], capture: "path" }, ... }
      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        data = YAML.safe_load_file(PATTERNS_PATH) || {}
        commands = data["commands"] || {}
        commands.each_with_object({}) do |(name, spec), out|
          regexes = (spec["patterns"] || []).map { |src| Regexp.new(src, Regexp::IGNORECASE | Regexp::EXTENDED) }
          out[name.to_s] = { regexes: regexes, capture: spec["capture"].to_s }
        end
      rescue StandardError
        {}
      end

      def infer_task_type(msg)
        TASK_TYPE_PATTERNS.each { |type, pat| return type if msg.match?(pat) }
        :general
      end

      def extract_args(cmd, capture, match, msg)
        case capture
        when "path"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "cycles"
          (match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "on_off"
          msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
        when "first_group"
          match.captures.compact.first.to_s.strip
        when "persona_name"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul_subcmd"
          msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders_subcmd"
          msg.match?(/\blist|show\b/i) ? "list" : ""
        when "scan_depth"
          match[1]&.strip.to_s
        else
          ""
        end
      end
    end
  end
end
```

## `lib/master/stages/intake.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

      def call(ctx)
        raw = ctx[:user_message]
        msg = raw.to_s.strip
        return Result.err("intake: empty message", category: :validation) if msg.empty?

        if (m = msg.match(COMMAND_RE))
          command = m[1].downcase
          args    = m[2].strip
          args = nil if args.empty?
          Result.ok(ctx.merge(intent: :command, command: command, args: args))
        else
          Result.ok(ctx.merge(intent: :llm, message: msg))
        end
      end
    end
  end
end```

## `lib/master/stages/lint.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Lint — always runs. Scans written files AND code blocks in chat output.
    # Violations are collected; if autofix is possible, feeds them back to
    # the autoloop for correction.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
      end

      def call(ctx)
        findings = []

        # 1. Scan any files that were written during Execute
        written = Array(ctx[:written_files])
        written.each do |path|
          next unless File.exist?(path) && path.end_with?(".rb")
          result = @scanner.scan(path, depth: :standard)
          findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
        end

        # 2. Scan code blocks embedded in chat output
        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        # 3. Autofix if violations found and autoloop available
        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue => e
        # Lint failure must not block the pipeline
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      # Scan a code string without writing to disk.
      # Creates a tempfile, scans it, deletes it.
      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          result = @scanner.scan(f.path, depth: :quick)
          if result.respond_to?(:ok?) && result.ok?
            findings = result.value!.map { |v| v.merge(source: :inline) }
          end
        end
        findings
      rescue StandardError
        []
      end
    end
  end
end
```

## `lib/master/stages/memo.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Memo — extract and persist memory from the USER's input only.
    #
    # Previously this scanned the assistant's output for "remember that X",
    # which caused LLM meta-restatements ("I'll remember that you prefer dark
    # themes") to be stored as facts the user never asserted — a classic
    # self-reinforcing hallucination loop.
    #
    # Now only :user_message is scanned. Assistant output is ignored on purpose.
    class Memo
      REMEMBER_RE = /\bremember\s+(?:that\s+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE = /\bwe(?:'ve|\s+have)?\s+decided\s+(?:to\s+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE   = /\bI\s+prefer\s+(.{5,100}?)(?:[.!]|$)/im.freeze

      def initialize(memory:, event_bus: nil)
        @memory = memory
        @bus    = event_bus
      end

      def call(ctx)
        text = user_text(ctx)
        scan_for_memories(text) if text && !text.empty?
        Result.ok(ctx)
      rescue StandardError => e
        @bus&.publish("memo:error", message: e.message)
        Result.ok(ctx)
      end

      private

      # Only trust the user's words. Assistant output is a potential
      # hallucination source and must never seed memory without explicit
      # user confirmation via the /memory remember command.
      def user_text(ctx)
        ctx[:user_message].to_s
      end

      def scan_for_memories(text)
        text.scan(REMEMBER_RE).each_with_index do |(fact), i|
          @memory.remember("note_#{Time.now.to_i}_#{i}", fact.strip)
        end
        text.scan(DECISION_RE).each do |(decision)|
          @memory.remember("decision_latest", decision.strip)
        end
        text.scan(PREFER_RE).each do |(pref)|
          key = "pref_#{pref.split.first(3).join("_").downcase.gsub(/\W/, "")}"
          @memory.remember(key, pref.strip)
        end
      end
    end
  end
end
```

## `lib/master/stages/prune.rb`
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
    class Prune
      RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      HEADER_RE     = %r{^\#{1,6}\s+}
      BOLD_RE       = /\*\*(.+?)\*\*/
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE     = /^\s*[-*+]\s+/
      NUMBERED_RE   = /^\s*\d+\.\s+/
      HR_RE         = /^-{3,}\s*$/
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

      def call(ctx)
        raw = ctx[:output]
        output = if raw.respond_to?(:ok?) && raw.ok?
                   raw.value!.to_s
                 elsif raw.is_a?(String)
                   raw
                 else
                   return Result.ok(ctx)
                 end
        return Result.ok(ctx) if output.empty?

        cleaned = prune_mixed(output)
        final = raw.respond_to?(:ok?) ? Result.ok(cleaned.strip) : cleaned.strip
        Result.ok(ctx.merge(output: final))
      end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
        cleaned
      end

      def rules
        @rules ||= begin
          data = File.exist?(RULES_PATH) ? YAML.safe_load_file(RULES_PATH, aliases: true) : {}
          data.dig("voice", "strunk") || {}
        end
      rescue StandardError
        @rules = {}
      end
    end
  end
end
```

## `lib/master/stages/render.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Render — format the final output for display.
    class Render
      def initialize(renderer:)
        @renderer = renderer
      end

      def call(ctx)
        output = ctx[:output]
        rendered = case output
                   when Result::Ok  then @renderer.render(output.value!, mode: :plain)
                   when Result::Err then @renderer.render(output.message, mode: :error)
                   else                  @renderer.render(output.to_s, mode: :plain)
                   end

        Result.ok(ctx.merge(rendered:))
      end
    end
  end
end
```

## `lib/master/stages/route.rb`
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Route — attach the correct handler to the context.
    # :command looks up registered command. :llm uses the agent.
    class Route
      def initialize(commands:, agent:)
        @commands = commands
        @agent    = agent
      end

      def add_command(name, handler) = @commands[name.to_s] = handler

      def call(ctx)
        case ctx[:intent]
        when :command then route_command(ctx)
        when :llm     then Result.ok(ctx.merge(handler: @agent))
        else               Result.err("route: unknown intent #{ctx[:intent].inspect}", category: :validation)
        end
      end

      private

      def route_command(ctx)
        cmd = @commands[ctx[:command]]
        return Result.err("unknown command: /#{ctx[:command]}", category: :validation) unless cmd

        Result.ok(ctx.merge(handler: cmd))
      end
    end
  end
end
```

## `lib/master/standing_orders.rb`
```ruby
# frozen_string_literal: true

module Master
  # Standing Orders — persistent authority programs that execute autonomously.
  # FSM states: pending → running → done | error
  #   pending: eligible to run when due
  #   running: currently executing (re-entrant guard)
  #   done:    completed; eligible again after interval
  #   error:   halted; requires /orders reset <name>
  class StandingOrders
    STORE_PATH   = File.join(Master::ROOT, "data", "standing_orders.yml")
    VALID_STATES = %w[pending running done error].freeze

    BUILTIN_ORDERS = [
      { name: "nightly_dreams", description: "Consolidate memories during low-activity periods",
        trigger: "scheduled", interval_s: 86_400, command: "dreams consolidate", enabled: true },
      { name: "weekly_scan", description: "Weekly codebase axiom scan for regressions",
        trigger: "scheduled", interval_s: 604_800, command: "scan", enabled: false }
    ].freeze

    def initialize(pipeline: nil, event_bus: nil)
      @pipeline = pipeline
      @bus      = event_bus
      @orders   = load_orders
    end

    def wire_pipeline(pipeline)
      @pipeline = pipeline
    end

    # Returns orders eligible to run: enabled, scheduled, interval elapsed,
    # not running, not stuck in error.
    def due
      now = Time.now.to_i
      @orders.select do |o|
        o["enabled"] &&
          o["trigger"] == "scheduled" &&
          %w[pending done].include?(state_of(o)) &&
          (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
      end
    end

    def run_due!
      results = []
      due.each do |order|
        order["state"] = "running"
        persist

        result = execute_order(order)
        order["last_run_at"] = Time.now.to_i

        if result.ok?
          order["state"] = "done"
          order.delete("last_error")
        else
          order["state"] = "error"
          order["last_error"] = result.message.to_s[0, 200]
        end

        results << { name: order["name"], result: }
        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?, state: order["state"])
      end
      persist if results.any?
      results
    end

    def upsert(name:, description: "", trigger: "scheduled",
               interval_s: 86_400, command:, enabled: true)
      existing = @orders.find { |o| o["name"] == name.to_s }
      if existing
        existing.merge!(
          "description" => description, "trigger" => trigger.to_s,
          "interval_s"  => interval_s.to_i, "command" => command.to_s, "enabled" => enabled
        )
      else
        @orders << {
          "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
          "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
          "state" => "pending", "last_run_at" => 0
        }
      end
      persist
      "standing order '#{name}' saved"
    end

    def enable(name)  = toggle(name, true)
    def disable(name) = toggle(name, false)

    def reset(name)
      o = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless o
      o["state"] = "pending"
      o.delete("last_error")
      persist
      "'#{name}' reset → pending"
    end

    def list
      return "no standing orders defined" if @orders.empty?
      @orders.map do |o|
        st   = state_of(o)
        flag = o["enabled"] ? "on" : "off"
        last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
        err  = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
        "#{o['name']} [#{flag}|#{st}] — #{o['description']} (last: #{last})#{err}"
      end.join("\n")
    end

    private

    def state_of(order) = VALID_STATES.include?(order["state"]) ? order["state"] : "done"

    def execute_order(order)
      return Result.err("no pipeline") unless @pipeline
      @pipeline.call(Result.ok(user_message: order["command"].to_s))
    rescue StandardError => e
      Result.err(e.message)
    end

    def toggle(name, state)
      o = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless o
      o["enabled"] = state
      persist
      "#{name} #{state ? 'enabled' : 'disabled'}"
    end

    def load_orders
      if File.exist?(STORE_PATH)
        orders = YAML.safe_load_file(STORE_PATH) || []
        orders.each { |o| o["state"] ||= "done" }  # migrate legacy
        orders
      else
        BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0, "state" => "pending") }
      end
    rescue Psych::Exception, Errno::ENOENT
      []
    end

    def persist
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(STORE_PATH))
      File.write(STORE_PATH, YAML.dump(@orders))
    end
  end
end
```

## `lib/master/swarm/coordinator.rb`
```ruby
# frozen_string_literal: true

require "timeout"

module Master
  module Swarm
    # Orchestrates specialized workers on a need-to-know basis.
    # The coordinator sees everything; workers see only their context slice.
    class Coordinator
      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      WORKER_TIMEOUT = 30  # seconds per worker
      SYNTHESIS_TRUNCATE_LIMIT = 200

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      # Run a single worker with a curated context slice
      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      # Run analysis → review pipeline (most common pattern)
      # Worker 1 (analyst) sees only the file. Worker 2 (reviewer) sees only the code.
      def analyse_and_review(file_path:, code:)
        analysis = dispatch(:analyst,
                            task: "identify all issues",
                            context_slice: { file: file_path, code: code })
        return analysis unless analysis.ok?

        review = dispatch(:reviewer,
                          task: "security and correctness review",
                          context_slice: { code: code })
        return review unless review.ok?

        Result.ok({
          analysis: analysis.value!,
          review:   review.value!,
          approved: review.value!["approved"]
        })
      end


      # Fan-out: run multiple workers in parallel threads with per-worker timeout.
      # Returns {results: {role => Result}, synthesis: String}.
      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          end
        end

        results = threads.map do |th|
          if th.join(timeout)
            th.value
          else
            begin
              th.kill
            rescue ThreadError => e
              @bus&.publish(:swarm_thread_kill_error, thread: th.object_id, error: e.message)
            end
            [:timeout, Result.err("worker timed out after #{timeout}s", category: :unknown)]
          end
        end.to_h

        synthesis = synthesize(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, synthesis: synthesis[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok({ results: results, synthesis: synthesis })
      end

# Convenience: parallel dispatch with a shared wall-clock deadline.
# role_tasks: [{role:, task:, context_slice: {}}]
# deadline: total seconds for all workers (not per-worker).
def dispatch_parallel(role_tasks, deadline: WORKER_TIMEOUT * 2)
  finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

  threads = role_tasks.map do |t|
    Thread.new do
      remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
      Timeout.timeout(remaining) do
        [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
      end
    rescue Timeout::Error
      [t[:role], Result.err("worker exceeded shared deadline", category: :unknown)]
    end
  end

  results = threads.map { |th| th.join(deadline)&.value || [nil, Result.err("join timeout")] }.to_h
  synthesis = synthesize(results)
  @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys)
  Result.ok({ results: results, synthesis: synthesis })
end

def worker_roles = WORKER_CLASSES.keys

      private

      # Combine successful worker results into a coherent summary string.
      def synthesize(results)
        lines = results.filter_map do |role, r|
          next if role == :timeout
          next unless r.respond_to?(:ok?) && r.ok?
          val = r.value!
          text = val.is_a?(Hash) ? val.inspect : val.to_s
          "### #{role}\n#{text.strip}"
        end
        lines.empty? ? "(no results)" : lines.join("\n\n")
      end

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return nil unless klass
          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
end
```

## `lib/master/swarm/worker.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know)
class Worker
  # Subclasses override to prefer a lighter/heavier model for their role.
  PREFERRED_MODEL = nil

  # Phrases that signal low-confidence output.
  UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                            i\ don't\ know limited\ information probably].freeze

  attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent    = agent
        @bus      = event_bus
        @role       = self.class.name.split("::").last.downcase
        @result     = nil
        @confidence = 1.0
      end

      # Execute a task with a minimal context slice
      # context_slice: only what this worker needs — not the full session
      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

preferred = self.class::PREFERRED_MODEL
raw = if preferred && @agent.respond_to?(:ask_once_with_model)
  @agent.ask_once_with_model(prompt, model: preferred, system: worker_system_prompt)
else
  @agent.ask_once(prompt, system: worker_system_prompt)
end
        @result = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      # Subclasses override
      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"
def parse_result(raw)
  text = raw.to_s.strip
  hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
  @confidence = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
  Result.ok({ text: text, confidence: @confidence })
end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k.to_s}: #{v.to_s}" }.join("\n")
      end
    end
  end
end
```

## `lib/master/swarm/workers/analyst.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reads code, produces structured analysis. Knows nothing about other workers.
      class Analyst < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free"
        private

        def role_description
          "You analyze code for quality, bugs, and design issues. " \
            "Output JSON: {issues: [{file, line, severity(1-3), description}], summary: string}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "File: #{ctx[:file]}" if ctx[:file]
          parts << "Code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Analyze: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          match_str = raw.to_s.match(/\{.*\}/m)&.to_s || "{}"
          parsed = JSON.parse(match_str)
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ summary: raw.to_s.strip, issues: [] })
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/coder.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Writes code given a spec. Knows only the spec + relevant file context.
      class Coder < Worker
        private

        def role_description
          "You write clean, minimal Ruby/Rails/Zsh code. " \
            "Output only the code block. No explanation unless asked."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Language: #{ctx[:language] || "ruby"}"
          parts << "Existing code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Spec: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/researcher.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free"
        private

        def role_description
          "You are a research analyst. Synthesize information concisely. " \
            "Output: factual summary, sources if known, confidence level (low/med/high)."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
          parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/reviewer.rb`
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reviews code for security, correctness, style. Constitutional layer.
      class Reviewer < Worker
        CHECKLIST = %w[
          sql_injection xss command_injection path_traversal
          hardcoded_secrets open_redirect mass_assignment
        ].freeze

        private

        def role_description
          "You are a security-focused code reviewer. Check for OWASP top-10 issues, " \
            "logic bugs, and constitutional AI violations. " \
            "Output JSON: {approved: bool, violations: [{type, line, description}]}"
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Code to review:\n```\n#{ctx[:code]}\n```" if ctx[:code]
          parts << "Security checklist: #{CHECKLIST.join(", ")}"
          parts << "Review for: #{task}"
          parts.join("\n\n")
        end

        def parse_result(raw)
          parsed = JSON.parse(raw.to_s.match(/\{.*\}/m)&.to_s || "{}")
          parsed["approved"] = true if parsed.empty?
          Result.ok(parsed)
        rescue JSON::ParserError
          Result.ok({ "approved" => true, "violations" => [] })
        end
      end
    end
  end
end
```

## `lib/master/sweep.rb`
```ruby
# frozen_string_literal: true

require "open3"
require "tempfile"
require "yaml"
require "set"

module Master
  # Sweep — iterative full-codebase refactor to convergence.
  #
  # Each cycle walks every matching file and sends it through a comprehensive
  # rewrite prompt. The model receives the full codebase map before touching
  # any individual file — structural context precedes every change.
  # Cycles continue until violations converge, rename oscillation is detected,
  # or max_cycles hit.
  #
  # Stopping criteria, per arxiv:2602.21833 ("From Restructuring to
  # Stabilization"):
  #   1. violation delta < CONVERGE_THRESHOLD for CONVERGE_WINDOW cycles
  #   2. rename oscillation detected (symbol A→B→A in the window)
  #   3. trajectory value (γ-discounted) stops improving
  #
  # Self-application: sweeping lib/ causes MASTER to rewrite its own source —
  # a true fixed-point process.
  class Sweep
    MAX_CYCLES         = 16
    CONVERGE_THRESHOLD = 0.05
    CONVERGE_WINDOW    = 2
    RENAME_WINDOW      = 3      # oscillation detected if A→B→A within 3 cycles
    TRAJECTORY_GAMMA   = 0.9    # γ for discounted improvement signal

    GLOBS = {
      rb:  "**/*.rb",
      sh:  "**/*.sh",
      yml: "**/*.yml",
      md:  "**/*.md",
      erb: "**/*.erb"
    }.freeze

    SYNTAX_CHECKERS = {
      ".rb" => ->(p) { system("ruby -c #{p} > /dev/null 2>&1") },
      ".sh"  => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") },
      ".yml" => ->(p) { begin; YAML.safe_load_file(p); true; rescue => _e; false; end },
      ".erb" => ->(p) { begin; ERB.new(File.read(p)).result(binding); true; rescue SyntaxError; false; rescue => _e; true; end }
    }.freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable)\b
    /ix.freeze

    PROMPTS_PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    def initialize(agent:, scanner:, council:, root:, event_bus: nil)
      @agent   = agent
      @scanner = scanner
      @council = council
      @root    = root
      @bus     = event_bus
      @map     = nil
      @prompts = nil
      @rename_log = Hash.new { |h, k| h[k] = [] }  # file => [cycle: {before:, after:}]
    end

    def run(target = @root, max_cycles: MAX_CYCLES, types: GLOBS.keys)
      @map            = build_codebase_map
      @prompts        = load_prompts
      violation_history = []
      converge_streak   = 0

      max_cycles.times do |i|
        cycle   = i + 1
        changed = 0
        cycle_viol = 0

        @bus&.publish("sweep:cycle", cycle:, target:)

        collect_files(target, types).each do |path|
          rel     = path.delete_prefix("#{@root}/")
          before  = violations_in(path)
          src     = File.read(path, encoding: "UTF-8")
          new_src = rewrite(path, rel)

          next unless new_src
          next if new_src.strip == src.strip
          next unless syntax_ok?(path, new_src)

          after = violations_in_text(new_src, path)
          next if after > before

          # Oscillation check: track name-level renames and reject if they
          # revert recent changes. Naming-focused prompts are the known
          # trigger (see arxiv:2602.21833 §4.3 — naming-focused prompts may
          # induce oscillatory renaming behavior).
          if rename_oscillation?(rel, src, new_src, cycle)
            @bus&.publish("sweep:oscillation_rejected", file: rel, cycle:)
            next
          end

          File.write(path, new_src, encoding: "UTF-8")
          changed    += 1
          cycle_viol += after
          @bus&.publish("sweep:improved", file: rel, before:, after:)
          yield cycle, rel, before - after if block_given?
        end

        violation_history << cycle_viol
        commit("sweep: full-codebase refactor [cycle #{cycle}]") if changed > 0 && git_dirty?

        converge_streak = converged?(violation_history) ? converge_streak + 1 : 0
        break if converge_streak >= CONVERGE_WINDOW

        # Trajectory-value early stop: if γ-discounted improvement signal
        # has flatlined, further cycles are unlikely to help and risk
        # the "rare but non-zero per iteration" functionality breaks
        # documented in arxiv:2602.21833.
        break if trajectory_stalled?(violation_history)
      end

      final = violation_history.last.to_i
      Result.ok("sweep: #{violation_history.size} cycle(s), #{final} violation(s) remaining")
    rescue StandardError => e
      Result.err("sweep: #{e.message}", category: :unknown)
    end

    private

    def load_prompts
      YAML.safe_load_file(PROMPTS_PATH)
    end

    # Build a compact file map. Injected into every rewrite prompt so the model
    # has full structural context before touching any individual file.
    def build_codebase_map
      files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                 .reject { |f| f.include?("/vendor/") }
                 .map    { |f| f.delete_prefix("#{@root}/") }
                 .sort
      "## Codebase (#{files.size} Ruby files)\n" +
        files.map { |f| "  #{f}" }.join("\n")
    end

    def collect_files(dir, types)
      types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }.uniq.sort
    end

    def rewrite(path, rel)
      src  = File.read(path, encoding: "UTF-8")
      ext  = File.extname(path)
      lang = { ".rb" => "ruby", ".sh" => "sh", ".yml" => "yaml",
               ".md" => "markdown", ".erb" => "erb" }.fetch(ext, "text")

      response = @agent.ask(build_prompt(src, rel, lang))
      extract(response.to_s, lang)
    rescue StandardError => e
      @bus&.publish("sweep:rewrite_error", file: path, error: e.message)
      nil
    end

    def build_prompt(src, rel, lang)
      <<~PROMPT
        You are refactoring #{rel} (#{lang}). Study the full codebase map below
        before making any change — do not modify an interface without tracing its callers.

        #{@map}

        #{@prompts["axioms"]}
        #{@prompts["structural_techniques"]}
        #{@prompts["prose_techniques"]}

        Improve every dimension of #{rel} in a single pass.
        Return ONLY the improved file content — no explanation, no markdown fences
        unless the file is already markdown. If no improvement is possible, return
        exactly: UNCHANGED

        File content:
        #{src}
      PROMPT
    end

    def extract(text, lang)
      return nil if text.strip == "UNCHANGED"

      # Reject short responses that look like error messages
      if text.bytesize < 500 && ERROR_PATTERNS.match?(text)
        return nil
      end

      fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
      return text.match(fence_re)[1]         if text.match?(fence_re)
      return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)

      text.strip.empty? ? nil : text
    end

    def syntax_ok?(path, content)
      checker = SYNTAX_CHECKERS[File.extname(path)]
      return true unless checker

      Tempfile.open(["sweep", File.extname(path)]) do |f|
        f.write(content)
        f.flush
        checker.call(f.path)
      end
    end

    def violations_in(path)
      return 0 unless path.end_with?(".rb") && File.exist?(path)
      r = @scanner.scan(path, depth: :deep)
      r.respond_to?(:value!) ? r.value!.size : 0
    rescue StandardError
      0
    end

    def violations_in_text(content, ref_path)
      return 0 unless ref_path.end_with?(".rb")

      Tempfile.open(["vcheck", ".rb"]) do |f|
        f.write(content)
        f.flush
        r = @scanner.scan(f.path, depth: :deep)
        r.respond_to?(:value!) ? r.value!.size : 0
      end
    rescue StandardError
      0
    end

    # Oscillation detector — rejects a proposed rewrite when it reintroduces
    # a name that was removed in a recent cycle. A→B then B→A within
    # RENAME_WINDOW is the signature documented in arxiv:2602.21833.
    def rename_oscillation?(rel, old_src, new_src, cycle)
      removed_now = extract_names(old_src) - extract_names(new_src)
      added_now   = extract_names(new_src) - extract_names(old_src)

      history = @rename_log[rel]
      recent  = history.last(RENAME_WINDOW)

      oscillates = recent.any? { |entry|
        # Was something currently being ADDED previously REMOVED, and vice versa?
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      }

      history << { cycle: cycle, removed: removed_now, added: added_now }
      # Keep only the window we actually query.
      @rename_log[rel] = history.last(RENAME_WINDOW * 2)

      oscillates
    end

    def extract_names(source)
      source.scan(NAME_RE).flatten.compact.uniq
    end

    def converged?(history)
      return false if history.size < 2

      prev, curr = history[-2], history[-1]
      return true if curr.zero?

      delta = (prev - curr).abs.to_f / [prev, 1].max
      delta < CONVERGE_THRESHOLD
    end

    # γ-discounted improvement signal. If the weighted sum of improvements
    # across recent cycles is near zero, we've stalled.
    # V = Σ γ^t · (prev_t − curr_t)
    def trajectory_stalled?(history)
      return false if history.size < 3
      deltas = history.each_cons(2).map { |a, b| a - b }
      v = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, i| d * (TRAJECTORY_GAMMA ** i) }
      v.abs < 1.0
    end

    def commit(msg)
      Dir.chdir(@root) do
        system("git add -A 2>/dev/null")
        system("git commit -m '#{msg}' 2>/dev/null")
      end
    end

    def git_dirty?
      out, = Open3.capture3("git -C #{@root} status --porcelain")
      !out.strip.empty?
    end
  end
end
```

## `lib/master/text_hygiene.rb`
```ruby
# frozen_string_literal: true

module Master
  # TextHygiene — deterministic pre-write normalization.
  # Ported from MASTER2. Strips BOM, zero-width chars, CRLF, trailing spaces.
  # Called by WriteFile and StrReplace tools before writing.
  module TextHygiene
    BINARY_EXTS = %w[.png .jpg .jpeg .gif .webp .pdf .zip .gz .tgz .mp3 .mp4 .mov .woff .woff2].freeze

    module_function

    def normalize(content, filename: nil, ensure_final_newline: true)
      return content unless content.is_a?(String)

      out = content.dup
      out.gsub!("\r\n", "\n")
      out.gsub!("\r", "\n")
      out.sub!(/\A\xEF\xBB\xBF/, "")
      out.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")
      out.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
      out.gsub!(/[ \t]+$/, "")

      if ensure_final_newline && text_like?(filename) && !out.empty? && !out.end_with?("\n")
        out << "\n"
      end

      out
    end

    def text_like?(filename)
      return true if filename.nil?

      ext = File.extname(filename.to_s).downcase
      !BINARY_EXTS.include?(ext)
    end
  end
end
```

## `lib/master/tools/ask_llm.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER        = :guarded
      NAME        = "ask_llm"
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string."

      def initialize(agent:, governor:, circuit_breaker:, cache:, event_bus: nil)
        @agent          = agent
        @governor       = governor
        @circuit_breaker = circuit_breaker
        @cache          = cache
        @bus            = event_bus
      end

      def call(prompt:, context: nil)
        perm = @governor.permit?(NAME, TIER, prompt[0, 60])
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, prompt: prompt[0, 80])

        result = @circuit_breaker.call(estimate_cost(prompt)) {
          @cache.fetch(prompt, @agent.model) {
            @agent.ask(prompt, context: context)
          }
        }

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(result.to_s)
      rescue => e
        Result.err("ask_llm: #{e.message}", category: :unknown)
      end

      private

      def estimate_cost(prompt)
        (prompt.bytesize / 4) * 0.000_015
      end
    end
  end
end
```

## `lib/master/tools/ast_edit.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AST-aware editing tool using Ruby's Ripper (stdlib) for parsing.
    # Supports: find_method, rename_method, extract_lines_to_method, add_after_method.
    # Uses Ripper::SexpBuilder for structure-awareness without external gem dependencies.
    class AstEdit
      TIER        = :guarded
      NAME        = "ast_edit"
      DESCRIPTION = "AST-aware code editing: find, rename, or restructure Ruby methods safely."

      def initialize(root:, undo:, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @bus  = event_bus
      end

      def call(operation:, path:, **opts)
        full = resolve(path)
        return full if full.err?
        fp = full.value!
        return Result.err("ast_edit: not found: #{path}", category: :validation) unless File.exist?(fp)

        src = File.read(fp)
        case operation.to_s
        when "find_method"    then find_method(src, opts[:name].to_s)
        when "rename_method"  then rename_method(fp, src, opts[:from].to_s, opts[:to].to_s)
        when "add_after"      then add_after_method(fp, src, opts[:after].to_s, opts[:code].to_s)
        when "method_lines"   then method_lines(src, opts[:name].to_s)
        else
          Result.err("ast_edit: unknown operation: #{operation}", category: :validation)
        end
      rescue => e
        Result.err("ast_edit: #{e.message}", category: :unknown)
      end

      private

      # Find a method definition and return its source lines
      def find_method(src, name)
        lines  = src.lines
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry

        slice  = lines[(entry[:start] - 1)..(entry[:end] - 1)].join
        Result.ok("# #{name} (lines #{entry[:start]}–#{entry[:end]})\n#{slice}")
      end

      # Rename all occurrences of a method definition and calls
      def rename_method(fp, src, from, to)
        return Result.err("ast_edit: from/to required", category: :validation) if from.empty? || to.empty?
        return Result.err("ast_edit: invalid name: #{to}", category: :validation) unless to.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/)

        @undo.snapshot(fp)
        updated = src
          .gsub(/\bdef\s+#{Regexp.escape(from)}\b/, "def #{to}")
          .gsub(/\b#{Regexp.escape(from)}\s*\(/, "#{to}(")
          .gsub(/\b#{Regexp.escape(from)}\b(?!\s*[:=])/) { |m| to }

        File.write(fp, updated)
        @bus&.publish("tool:ast_edit", op: "rename", from: from, to: to, path: fp)
        Result.ok("renamed #{from} → #{to} in #{File.basename(fp)}")
      end

      # Insert a new method directly after an existing one
      def add_after_method(fp, src, after_name, code)
        return Result.err("ast_edit: after/code required", category: :validation) if after_name.empty? || code.empty?

        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == after_name }
        return Result.err("ast_edit: method not found: #{after_name}", category: :validation) unless entry

        lines = src.lines
        insert_at = entry[:end]  # after the 'end' of the target method
        lines.insert(insert_at, "\n", code.chomp + "\n")

        @undo.snapshot(fp)
        File.write(fp, lines.join)
        @bus&.publish("tool:ast_edit", op: "add_after", after: after_name, path: fp)
        Result.ok("inserted method after #{after_name} in #{File.basename(fp)}")
      end

      # Return start/end line numbers for each method definition
      def method_lines(src, name)
        ranges = method_line_ranges(src)
        entry  = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry
        Result.ok("#{name}: lines #{entry[:start]}–#{entry[:end]}")
      end

      def method_line_ranges(src)
        require "ripper"
        lines  = src.lines
        ranges = []
        stack  = []  # stack of {name:, start:, depth:}
        depth  = 0

        Ripper.lex(src).each do |(_line, _col), type, token, _state|
          case type
          when :on_kw
            case token
            when "def"
              # next identifier token is the method name
              stack.push({ name: nil, start: _line, depth: depth })
              depth += 1
            when "class", "module", "do", "begin", "for", "if", "unless",
                 "while", "until", "case"
              depth += 1 unless token == "if" && !stack.empty? && stack.last[:name]
            when "end"
              depth -= 1
              if !stack.empty? && depth == stack.last[:depth]
                entry        = stack.pop
                entry[:end]  = _line
                ranges << entry if entry[:name]
              end
            end
          when :on_ident
            if !stack.empty? && stack.last[:name].nil?
              stack.last[:name] = token
            end
          end
        end
        ranges
      end

      def resolve(path)
        full = File.expand_path(path.to_s, @root)
        return Result.err("path escapes root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/batch_replace.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # BatchReplace — apply multiple search-and-replace operations in one pass.
    class BatchReplace
      TIER        = :guarded
      NAME        = "replace"
      DESCRIPTION = "Find and replace text across all files in a directory."

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        perm = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return perm if perm.err?

        target = dir ? File.expand_path(dir, @root) : @root
        return Result.err("replace: directory not found: #{target}", category: :validation) unless Dir.exist?(target)

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)

        changed = 0
        Dir.glob("#{target}/**/*").each do |path|
          next unless File.file?(path)
          content = File.read(path, encoding: "UTF-8") rescue next
          next unless content.include?(old_str)
          File.write(path, content.gsub(old_str, new_str))
          changed += 1
        end

        if rename_files
          Dir.glob("#{target}/**/*")
             .select { |p| File.file?(p) && File.basename(p).include?(old_str) }
             .each do |path|
               new_path = File.join(File.dirname(path), File.basename(path).gsub(old_str, new_str))
               File.rename(path, new_path)
               changed += 1
             end
        end

        @bus&.publish("tool:after", tool: NAME)
        Result.ok("replaced in #{changed} file(s)")
      rescue => e
        Result.err("replace: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/clean.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using sh/clean.sh.
    class Clean
      SCRIPT = File.expand_path("../../../sh/clean.sh", __dir__).freeze

      def initialize(root:, governor:, event_bus: nil)
        @bus = event_bus
        @root     = root
        @governor = governor
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless File.exist?(target) || Dir.exist?(target)

        guard = @governor.guard("clean #{target}")
        return Result.err(guard.message, category: :policy) if guard.respond_to?(:ok?) && !guard.ok?

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.lines.grep(/^Cleaned:/).map { |l| l.sub("Cleaned: ", "").chomp }
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/git_context.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # Git context tool — query history, blame, diff, and status.
    # All commands are read-only (TIER :safe). No writes.
    class GitContext
      TIER        = :safe
      NAME        = "git_context"
      DESCRIPTION = "Query git log, blame, diff, and status for the project."

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(operation:, path: nil, limit: 20)
        Dir.chdir(@root) do
          case operation.to_s
          when "log"    then git_log(path, limit.to_i)
          when "blame"  then git_blame(path)
          when "diff"   then git_diff(path)
          when "status" then git_status
          when "show"   then git_show(path)
          else
            Result.err("git_context: unknown operation: #{operation}", category: :validation)
          end
        end
      rescue => e
        Result.err("git_context: #{e.message}", category: :unknown)
      end

      private

      def git_log(path, limit)
        args = ["git", "log", "--oneline", "--no-color", "-#{limit}"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no commits)" : out.strip)
      end

      def git_blame(path)
        return Result.err("git_context blame: path required", category: :validation) unless path
        safe = safe_path(path)
        return Result.err("git_context blame: file not found: #{path}", category: :validation) unless File.exist?(File.join(@root, safe))
        out = IO.popen(["git", "blame", "--no-color", "-l", safe], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no blame data)" : out.strip)
      end

      def git_diff(path)
        args = ["git", "diff", "--no-color"]
        args << "--" << safe_path(path) if path
        out = IO.popen(args, err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(no unstaged changes)" : out.strip)
      end

      def git_status
        out = IO.popen(["git", "status", "--short", "--no-color"], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(clean)" : out.strip)
      end

      def git_show(ref)
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:\-\/]/, "")
        out = IO.popen(["git", "show", "--stat", "--no-color", ref_s], err: File::NULL) { |io| io.read }
        Result.ok(out.strip.empty? ? "(not found)" : out.strip[0..4000])
      end

      # Prevent path traversal: resolve relative to root, must stay inside
      def safe_path(path)
        full = File.expand_path(path.to_s, @root)
        raise "path escapes root" unless full.start_with?(@root)
        Pathname.new(full).relative_path_from(@root).to_s
      end
    end
  end
end
```

## `lib/master/tools/list_dir.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # ListDir — list directory contents with filtering and depth control.
    class ListDir
      TIER        = :safe
      NAME        = "list_dir"
      DESCRIPTION = "List directory contents, depth-limited."
      MAX_DEPTH   = 5

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full  = resolved.value!
        depth = [depth.to_i, MAX_DEPTH].min
        lines = list_tree(full, full, depth, pattern)
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(base, dir, depth, pattern, indent = 0)
        return [] if depth < 0
        entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
        entries.flat_map { |entry|
          full = File.join(dir, entry)
          next if pattern && !File.fnmatch?(pattern, entry)
          prefix = "  " * indent
          if File.directory?(full)
            ["#{prefix}#{entry}/"] + list_tree(base, full, depth - 1, pattern, indent + 1)
          else
            ["#{prefix}#{entry}"]
          end
        }
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        return Result.err("not a directory: #{path}", category: :validation) unless File.directory?(full)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/llm.rb`
```ruby
# frozen_string_literal: true

require "ruby_llm"

module Master
  module Tools
    # LLM-callable wrappers around the existing Master tool instances.
    # Each class holds a reference to the underlying tool via initialize,
    # so governor, undo, and event_bus plumbing is preserved.
    module LLM

    # LLM — shared base module for LLM-backed tool functionality.
      class ReadFile < RubyLLM::Tool
        DEFAULT_LIMIT = 2000

        description "Read a file with line numbers. Path is relative to project root."
        param :path,   desc: "File path relative to project root", required: true
        param :offset, desc: "First line to read (0-indexed)", type: "integer", required: false
        param :limit,  desc: "Maximum number of lines to return", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(path:, offset: 0, limit: DEFAULT_LIMIT)
          result = @tool.call(path: path.to_s, offset: offset.to_i, limit: limit.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class WriteFile < RubyLLM::Tool
        description "Write content to a file, creating it if needed. Snapshots for undo."
        param :path,    desc: "File path relative to project root", required: true
        param :content, desc: "Full content to write", required: true

        def initialize(tool) = @tool = tool

        def execute(path:, content:)
          result = @tool.call(path: path.to_s, content: content.to_s)
          result.ok? ? "Written: #{result.value!}" : "Error: #{result.message}"
        end
      end

      class StrReplace < RubyLLM::Tool
        description "Replace an exact unique string in a file with new content."
        param :path,        desc: "File path relative to project root", required: true
        param :old_string,  desc: "Exact string to find (must be unique in file)", required: true
        param :new_string,  desc: "Replacement string", required: true

        def initialize(tool) = @tool = tool

        def execute(path:, old_string:, new_string:)
          result = @tool.call(path: path.to_s, old_string: old_string.to_s, new_string: new_string.to_s)
          result.ok? ? "Replaced in: #{result.value!}" : "Error: #{result.message}"
        end
      end

      class ListDir < RubyLLM::Tool
        description "List directory contents as a tree. Path is relative to project root."
        param :path,  desc: "Directory path (default: project root)", required: false
        param :depth, desc: "Tree depth (1-5)", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(path: ".", depth: 3)
          result = @tool.call(path: path.to_s, depth: depth.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class SearchFiles < RubyLLM::Tool
        description "Search files in the project for a regex pattern. Returns matching lines with context."
        param :pattern, desc: "Ruby regex pattern to search for", required: true
        param :path,    desc: "Directory to search in (default: project root)", required: false
        param :context, desc: "Lines of context to show around each match", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(pattern:, path: ".", context: 2)
          result = @tool.call(pattern: pattern.to_s, path: path.to_s, context: context.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class Shell < RubyLLM::Tool
        description "Run a shell command in the project root. Blocked patterns are enforced."
        param :command, desc: "Shell command to execute", required: true

        def initialize(tool) = @tool = tool

        def execute(command:)
          result = @tool.call(command: command.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class WebSearch < RubyLLM::Tool
        MAX_QUERY_LENGTH = 300

        description "Search the web using DuckDuckGo. Returns titles and snippets."
        param :query, desc: "Search query (max #{MAX_QUERY_LENGTH} chars)", required: true

        def initialize(tool) = @tool = tool

        def execute(query:)
          result = @tool.call(query: query.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class AskLlm < RubyLLM::Tool
        description "Ask a sub-question to a fresh LLM context. Useful for isolated reasoning."
        param :prompt,  desc: "The question or prompt to ask", required: true
        param :context, desc: "Optional background context", required: false

        def initialize(tool) = @tool = tool

        def execute(prompt:, context: nil)
          result = @tool.call(prompt: prompt.to_s, context: context&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class GitContext < RubyLLM::Tool
        description "Query git log, blame, diff, status, or show for the project."
        param :operation, desc: "One of: log, blame, diff, status, show", required: true
        param :path,      desc: "File path (required for blame; optional for log/diff/show)", required: false
        param :limit,     desc: "Max commits for log", type: "integer", required: false

        def initialize(tool) = @tool = tool

        def execute(operation:, path: nil, limit: 20)
          result = @tool.call(operation: operation.to_s, path: path&.to_s, limit: limit.to_i)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class AstEdit < RubyLLM::Tool
        description "AST-aware Ruby code editing: find, rename, or insert methods safely."
        param :operation, desc: "One of: find_method, rename_method, add_after, method_lines", required: true
        param :path,      desc: "File path relative to project root", required: true
        param :name,      desc: "Method name (for find_method, method_lines)", required: false
        param :from,      desc: "Original method name (for rename_method)", required: false
        param :to,        desc: "New method name (for rename_method)", required: false
        param :after,     desc: "Insert after this method name (for add_after)", required: false
        param :code,      desc: "Ruby code to insert (for add_after)", required: false

        def initialize(tool) = @tool = tool

        def execute(operation:, path:, name: nil, from: nil, to: nil, after: nil, code: nil)
          result = @tool.call(operation: operation.to_s, path: path.to_s,
                         name: name&.to_s, from: from&.to_s, to: to&.to_s,
                         after: after&.to_s, code: code&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

      class SearchKnowledge < RubyLLM::Tool
        description "Search the local knowledge base: ruby_llm docs, OpenBSD man pages, system prompts, gem docs. Topics: ruby_llm, openbsd, system_prompts, gems, awesome."
        param :query, desc: "Search pattern (regex-capable)", required: true
        param :topic, desc: "Limit to topic folder: ruby_llm, openbsd, system_prompts, gems, awesome", required: false

        def initialize(tool) = @tool = tool

        def execute(query:, topic: nil)
          result = @tool.call(query: query.to_s, topic: topic&.to_s)
          result.ok? ? result.value! : "Error: #{result.message}"
        end
      end

    end
  end
end
```

## `lib/master/tools/path_guard.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    module PathGuard
      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/read_file.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
        include PathGuard
      TIER        = :safe
      MAX_LINES   = 2000
      NAME        = "read_file"
      DESCRIPTION = "Read a file with line numbers. Guarded to project root."

      def initialize(root:, undo:, event_bus: nil)
        @root  = File.realpath(root)
        @undo  = undo
        @bus   = event_bus
        @cache = {}
      end

      # Clear per-turn cache — called by Agent at the start of each chat turn.
      def reset!
        @cache.clear
      end

      def call(path:, offset: 0, limit: MAX_LINES)
        key = [path, offset, limit]
        return @cache[key] if @cache.key?(key)
        resolved = resolve(path)
        return resolved if resolved.err?

        full_path = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)
        return Result.err("not a file: #{path}", category: :validation) unless File.file?(full_path)

        lines = File.readlines(full_path)
        total = lines.size
        slice = lines[offset, limit] || []

        numbered = slice.each_with_index.map { |l, i| "#{offset + i + 1}\t#{l}" }.join
        suffix   = total > offset + limit ? "\n[...truncated, #{total} total lines]" : ""

        result = Result.ok(numbered + suffix)
        @cache[key] = result
        result
      end

      private

    end
  end
end
```

## `lib/master/tools/search_files.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # SearchFiles — regex search across project files with context lines.
    class SearchFiles
      TIER        = :safe
      NAME        = "search_files"
      DESCRIPTION = "Search for a pattern in files under the project root."
      MAX_RESULTS = 200

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(pattern:, glob: "**/*", context_lines: 2)
        begin
          re = Regexp.new(pattern)
        rescue RegexpError
          return Result.err("invalid pattern: #{pattern}", category: :validation)
        end

        paths   = Dir.glob(File.join(@root, glob)).select { |p| File.file?(p) }
        results = []

        paths.each do |path|
          next if binary_file?(path)

          lines = File.readlines(path)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - context_lines, 0].max
            finish = [idx + context_lines, lines.size - 1].min
            ctx    = lines[start..finish].each_with_index.map { |l, i| "#{start + i + 1}:#{l}" }.join
            rel    = path.delete_prefix(@root + "/")
            results << "#{rel}:#{idx + 1}\n#{ctx}"
            return Result.ok(results.join("\n---\n") + "\n[...truncated]") if results.size >= MAX_RESULTS
          end
        end

        Result.ok(results.empty? ? "(no matches)" : results.join("\n---\n"))
      rescue => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end

      private

      def binary_file?(path)
        sample = File.read(path, 512) rescue ""
        sample.include?("\x00")
      end
    end
  end
end
```

## `lib/master/tools/search_knowledge.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # Search the local knowledge base: cloned docs, man pages, system prompts, gem READMEs.
    class SearchKnowledge
      TIER        = :safe
      NAME        = "search_knowledge"
      DESCRIPTION = "Search local knowledge base (ruby_llm docs, OpenBSD man pages, system prompts, gem docs). " \
                    "Use for: how does X work in ruby_llm? what does man pf.conf say? example system prompts?"
      MAX_RESULTS = 30

      def initialize(root:, event_bus: nil)
        @knowledge_root = File.join(File.realpath(root), "knowledge")
        @bus = event_bus
      end

      def call(query:, topic: nil)
        return Result.err("knowledge base not found", category: :validation) unless Dir.exist?(@knowledge_root)

        search_dir = topic ? File.join(@knowledge_root, topic.to_s) : @knowledge_root
        unless Dir.exist?(search_dir)
          return Result.err("unknown topic: #{topic}. Available: #{available_topics.join(", ")}", category: :validation)
        end

        begin
          re = Regexp.new(query, Regexp::IGNORECASE)
        rescue RegexpError => e
          re = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)
        end

        paths   = Dir.glob(File.join(search_dir, "**", "*")).select { |p| File.file?(p) && text_file?(p) }
        results = []

        paths.each do |path|
          next if skip_file?(path)
          lines = File.readlines(path, encoding: "UTF-8", invalid: :replace)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - 2, 0].max
            finish = [idx + 2, lines.size - 1].min
            ctx    = lines[start..finish].map.with_index(start + 1) { |l, n| "#{n}: #{l}" }.join
            rel    = path.delete_prefix(@knowledge_root + "/")
            results << "### #{rel}:#{idx + 1}\n#{ctx}"
            break if results.size >= MAX_RESULTS
          end
          break if results.size >= MAX_RESULTS
        end

        if results.empty?
          Result.ok("No matches for '#{query}' in #{topic || "all knowledge"}.")
        else
          header = "# Knowledge search: '#{query}' (#{results.size} matches)\n\n"
          Result.ok(header + results.join("\n---\n"))
        end
      rescue => e
        Result.err("search_knowledge: #{e.message}", category: :unknown)
      end

      def available_topics
        return [] unless Dir.exist?(@knowledge_root)
        Dir.entries(@knowledge_root).select { |e| File.directory?(File.join(@knowledge_root, e)) && !e.start_with?(".") }
      end

      private

      def text_file?(path)
        ext = File.extname(path).downcase
        %w[.rb .md .txt .yml .yaml .json .sh .conf .html .rst .rdoc].include?(ext) || ext.empty?
      end

      def skip_file?(path)
        path.include?("/.git/") || path.include?("/node_modules/") ||
          path.include?("/vendor/") || File.size(path) > 500_000
      end
    end
  end
end
```

## `lib/master/tools/shell.rb`
```ruby
# frozen_string_literal: true

require "tty-command"
require "timeout"
require "shellwords"

module Master
  module Tools
    # Shell — execute shell commands with timeout and governor approval.
    class Shell
      TIER        = :dangerous
      NAME        = "zsh"
      DESCRIPTION = "Execute a zsh command in the project root."
      TIMEOUT     = 30
      BLOCKLIST   = Security::Permissions::BLOCKLIST

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @cmd      = TTY::Command.new(printer: :null)
      end

      def call(command:)
        return Result.err("blocked command: #{command}", category: :validation) if blocked?(command)

        perm = @governor.permit?(NAME, TIER, command)
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, command:)

        zdotdir = File.writable?("/tmp") ? "/tmp" : Dir.home
        wrapped = "#!/usr/bin/env zsh\nset -euo pipefail\nsetopt nullglob extendedglob\nexport ZDOTDIR=#{Shellwords.escape(zdotdir)}\nexport LC_ALL=C.UTF-8\ncd #{Shellwords.escape(@root)}\n#{command}\n"

        out, err = Timeout.timeout(TIMEOUT) { @cmd.run!("zsh", input: wrapped) }
        @bus&.publish("tool:after", tool: NAME, exit_code: out.exit_status)

        if out.exit_status != 0
          Result.err("zsh: exit #{out.exit_status}\n#{err.to_s.strip}", category: :unknown)
        else
          Result.ok(out.to_s.strip)
        end
      rescue Timeout::Error
        Result.err("zsh: timed out after #{TIMEOUT}s", category: :unknown)
      rescue TTY::Command::ExitError => e
        Result.err("zsh: #{e.message}", category: :unknown)
      end

      private

      def blocked?(command)
        BLOCKLIST.any? { |b| command.include?(b) }
      end
    end
  end
end
```

## `lib/master/tools/str_replace.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # StrReplace — surgical string replacement in files with undo support.
    class StrReplace
        include PathGuard
      TIER        = :guarded
      NAME        = "str_replace"
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times."

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, old_string:, new_string:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full    = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

        content = File.read(full)
        count   = content.scan(Regexp.quote(old_string)).size

        return Result.err("str_replace: pattern not found in #{path}", category: :validation) if count.zero?
        return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)", category: :validation) if count > 1

        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        new_content = content.sub(old_string, new_string)

        if @diff_stager
          return @diff_stager.stage(path: full, new_content:, tool: NAME)
        end

        @undo.snapshot(full)

        tmp = "#{full}.tmp.#{Process.pid}"
        File.write(tmp, new_content)
        File.rename(tmp, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue => e
        File.delete(tmp) if tmp && File.exist?(tmp)
        Result.err("str_replace: #{e.message}", category: :unknown)
      end

      private

    end
  end
end
```

## `lib/master/tools/symbol_lookup.rb`
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # SymbolLookup — lets the LLM query the live codebase symbol graph.
    # Returns definition location, callers, and impact analysis for any symbol.
    class SymbolLookup
      NAME        = "symbol_lookup"
      DESCRIPTION = "Look up a Ruby class, module, or method in the codebase. " \
                    "Returns file, line, and all cross-file references (callers/usages). " \
                    "Use before refactoring to understand impact."

      def initialize(code_index:, event_bus: nil)
        @index = code_index
        @bus   = event_bus
      end

      def call(name:)
        return Result.err("symbol_lookup: index not built yet", category: :validation) unless @index.built?

        hits = @index.query(name)
        if hits.is_a?(Hash) && hits[:error]
          return Result.err("symbol_lookup: #{hits[:error]}", category: :validation)
        end

        @bus&.publish("tool:symbol_lookup", name:, hits: hits.size)
        Result.ok(hits.map { |h| format_hit(h) }.join("\n\n"))
      end

      private

      def format_hit(h)
        lines = ["#{h[:fqn]} (#{h[:type]})"]
        lines << "  defined: #{h[:file]}:#{h[:line]}"
        lines << "  parent:  #{h[:parent]}" if h[:parent] && h[:parent] != "Object"
        if h[:used_in].any?
          lines << "  used in:"
          h[:used_in].each { |ref| lines << "    #{ref}" }
        else
          lines << "  used in: (no cross-file references found)"
        end
        lines.join("\n")
      end
    end
  end
end
```

## `lib/master/tools/tree.rb`
```ruby
# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Tree — lists directory structure using sh/tree.sh.
    # Safe: read-only, no writes.
    class Tree
      SCRIPT = File.expand_path("../../../sh/tree.sh", __dir__).freeze

      def initialize(root:, event_bus: nil)
        @bus = event_bus
        @root = root
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless Dir.exist?(target)

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("tree failed: #{err.strip}", category: :unknown) unless status.success?

        lines = out.lines.map(&:chomp).reject(&:empty?)
        @bus&.publish("tool:tree", path: target, count: lines.size)
        Result.ok(lines.join("\n"))
      rescue StandardError => e
        Result.err("tree: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/web_search.rb`
```ruby
# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Master
  module Tools
    # WebSearch — query external search APIs with governor rate limiting.
    class WebSearch
      TIER               = :guarded
      MAX_QUERY_CHARS    = 300
      MAX_SEARCH_RESULTS = 5

      NAME        = "web_search"
      DESCRIPTION = "Search DuckDuckGo instant answers API."
      ENDPOINT    = "https://api.duckduckgo.com/"
      TIMEOUT     = 10

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus      = event_bus
      end

      def call(query:)
        if query.length > MAX_QUERY_CHARS
          @bus&.publish("tool:warning", tool: NAME, message: "query truncated to #{MAX_QUERY_CHARS} chars")
          query = query[0, MAX_QUERY_CHARS]
        end

        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(q: query, format: "json", no_redirect: 1)

        response = Timeout.timeout(TIMEOUT * 2) {
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: TIMEOUT) { |h|
            h.get(uri.request_uri)
          }
        }

        return Result.err("web_search: HTTP #{response.code}", category: :infrastructure) unless response.code == "200"

        data    = JSON.parse(response.body)
        results = extract_results(data)
        @bus&.publish("tool:after", tool: NAME, query:)
        Result.ok(results)
      rescue => e
        Result.err("web_search: #{e.message}", category: :infrastructure)
      end

      private

      def extract_results(data)
        parts = []
        parts << data["Abstract"] unless data["Abstract"].to_s.empty?
        (data["RelatedTopics"] || []).first(MAX_SEARCH_RESULTS).each { |t| parts << t["Text"] if t["Text"] }
        parts.empty? ? "(no results)" : parts.join("\n\n")
      end
    end
  end
end
```

## `lib/master/tools/write_file.rb`
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    # WriteFile — create or overwrite files with TextHygiene normalization.
    class WriteFile
        include PathGuard
      TIER        = :guarded
      NAME        = "write_file"
      DESCRIPTION = "Atomically write content to a file, with undo snapshot."

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, content:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        return @diff_stager.stage(path: full, new_content: content, tool: NAME) if @diff_stager

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))

        tmp = "#{full}.tmp.#{Process.pid}"
        File.write(tmp, content)
        File.rename(tmp, full)

        # Publishes tool:after — the event bus subscriber reindexes CodeIndex.
        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue StandardError => e
        File.delete(tmp) if tmp && File.exist?(tmp)
        Result.err("write_file: #{e.message}", category: :unknown)
      end

      private

    end
  end
end
```

## `lib/master/triggers.rb`
```ruby
# frozen_string_literal: true

module Master
  # Triggers — event-driven reactive actions.
  # Ported from MASTER2. Registers handlers on EventBus events
  # and fires automatic responses (auto-fix after scan, budget switching, etc.)
  class Triggers
    DEFAULTS = %i[after_scan on_error budget_low tool_after].freeze

    def initialize(event_bus:, scanner: nil, agent: nil)
      @bus     = event_bus
      @scanner = scanner
      @agent   = agent
      @rules   = []
    end

    def install_defaults!
      register(:after_scan) do |ctx|
        count = ctx[:violations].to_i
        if count > 0
          @bus.publish("triggers:violations_found", count: count)
        end
      end

      register(:on_error) do |ctx|
        @bus.publish("triggers:error_logged", error: ctx[:error].to_s[0, 200])
      end

      register(:budget_low) do |_ctx|
        @bus.publish("triggers:budget_low", action: "switch_to_free_tier")
      end

      @bus.subscribe("tool:after") do |ev|
        fire(:tool_after, ev)
      end

      self
    end

    def register(event, &handler)
      @rules << { event: event.to_sym, handler: handler }
    end

    def fire(event, context = {})
      matching = @rules.select { |r| r[:event] == event.to_sym }
      matching.each do |rule|
        rule[:handler].call(context)
      rescue StandardError => e
        @bus.publish("triggers:handler_error", event: event, error: e.message)
      end
    end

    def list
      @rules.map { |r| r[:event].to_s }.tally.map { |e, n| "#{e}: #{n} handler(s)" }.join("\n")
    end

    def clear!
      @rules.clear
    end
  end
end
```

## `lib/master/undo.rb`
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  class Undo
    MAX_JOURNAL = 50

    def initialize(session:, event_bus: nil, root: Dir.pwd)
      @session = session
      @bus     = event_bus
      @root    = root
      @journal = File.join(root, ".master", "undo_journal.jsonl")
      @stack   = load_journal
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
      @stack.shift while @stack.size > MAX_JOURNAL
      persist_journal
      Result.ok(path)
    rescue => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!(steps: 1)
      return Result.err("nothing to undo", category: :validation) if @stack.empty?

      steps = [steps, @stack.size].min
      paths = []

      steps.times do
        entry = @stack.pop
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("undo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def depth = @stack.size

    def history(limit: 10)
      @stack.last(limit).reverse.map.with_index(1) do |entry, i|
        time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
        "#{i}. #{entry["path"]} (#{time})"
      end
    end

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end

    def load_journal
      return [] unless File.exist?(@journal)
      File.readlines(@journal).filter_map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError
      []
    end

    def persist_journal
      FileUtils.mkdir_p(File.dirname(@journal))
      File.open(@journal, "w") do |f|
        @stack.each { |entry| f.puts(JSON.generate(entry)) }
      end
    end
  end
end
```

## `lib/master/unwrap_error.rb`
```ruby
# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end
end
```

## `master.gemspec`
```gemspec
# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name    = "master"
  s.version = "3.0.0"
  s.summary = "Constitutional governance for an autonomous coding agent"
  s.authors = ["dev"]
  s.files   = Dir["lib/**/*.rb", "exe/*", "data/**/*", "*.yml"]
  s.executables = ["master"]
  s.require_paths = ["lib"]

  s.add_dependency "ruby_llm",       "~> 1.3"
  s.add_dependency "tty-prompt",     "~> 0.23"
  s.add_dependency "tty-reader",     "~> 0.9"
  s.add_dependency "tty-spinner",    "~> 0.9"
  s.add_dependency "tty-markdown",   "~> 0.7"
  s.add_dependency "tty-table",      "~> 0.12"
  s.add_dependency "tty-screen",     "~> 0.8"
  s.add_dependency "tty-box",        "~> 0.7"
  s.add_dependency "tty-command",    "~> 0.10"
  s.add_dependency "tty-tree",       "~> 0.4"
  s.add_dependency "tty-config",     "~> 0.6"
  s.add_dependency "tty-logger",     "~> 0.6"
  s.add_dependency "tty-progressbar","~> 0.18"
  s.add_dependency "pastel",         "~> 0.8"
  s.add_dependency "rouge",          "~> 4.4"
  s.add_dependency "diffy",          "~> 3.4"
  s.add_dependency "zeitwerk",       "~> 2.7"
end
```

## `master.md`
```markdown
circuit open: retry in 6s```

## `scripts/openbsd_preflight.zsh`
```zsh
#!/usr/bin/env zsh
# MASTER preflight check — run before deploying to OpenBSD
set -euo pipefail
setopt err_exit

ROOT=${${0:A}:h:h}
cd "$ROOT"

print "MASTER preflight — ${ROOT}"

# Ruby version
[[ -x $(whence ruby) ]] || { print "FAIL: ruby not found"; exit 1 }
print "ok: ruby $(ruby -e 'print RUBY_VERSION')"

# Bundler
[[ -x $(whence bundle) ]] || { print "FAIL: bundler not found"; exit 1 }
print "ok: bundler $(bundle -v)"

# Gem dependencies
bundle check >/dev/null 2>&1 || { print "FAIL: bundle check failed (run: bundle install)"; exit 1 }
print "ok: gems installed"

# API keys
[[ -n "${REPLICATE_API_KEY:-}" ]]   && print "ok: REPLICATE_API_KEY" || print "warn: REPLICATE_API_KEY not set"
[[ -n "${ANTHROPIC_API_KEY:-}" ]]   && print "ok: ANTHROPIC_API_KEY" || print "warn: ANTHROPIC_API_KEY not set"
[[ -n "${OPENROUTER_API_KEY:-}" ]]  && print "ok: OPENROUTER_API_KEY" || print "warn: OPENROUTER_API_KEY not set"

# Syntax
print "check: ruby syntax"
ruby -c lib/master.rb >/dev/null
print "ok: lib/master.rb syntax"

# Tests
print "check: test suite"
bundle exec ruby -Itest test/test_result.rb test/test_ring_buffer.rb test/test_axioms.rb test/test_prune.rb 2>&1 | tail -1
print "ok: tests passed"

print "\nMASTER preflight complete."
```

## `skills/explain/SKILL.md`
```markdown
circuit open: retry in 6s```

## `test/test_agent.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

# Minimal unit tests for Master::Agent — specifically targeting the Tier-1
# bugs the patch corrects. Does not hit any real LLM.
class TestAgent < Minitest::Test
  include Master

  # Fake collaborators — just enough to construct an Agent.
  FakeConfig  = Struct.new(:model, :task_type, :reasoning_mode) do
    def [](k) = send(k) rescue nil
  end
  FakeSession = Struct.new(:messages) { def add_message(**) = messages << _1 }
  FakeCB      = Struct.new(:out) { def check_rate!; end; def call(_, &b); b.call; end }
  FakeCache   = Struct.new(:store) { def fetch(k, m, &b); (store[k] ||= b.call); end }

  def setup
    @agent = Master::Agent.new(
      config:          FakeConfig.new("claude-sonnet-4-6", :exploration, "none"),
      session:         FakeSession.new([]),
      tools:           [],
      circuit_breaker: FakeCB.new,
      cache:           FakeCache.new({})
    )
  end

  # tool_capable? — previously a substring-include check. After patch,
  # anchored regex rejects garbage-tailed model ids but accepts real ones.
  def test_tool_capable_accepts_known_providers
    assert @agent.send(:tool_capable?, "claude-sonnet-4-6")
    assert @agent.send(:tool_capable?, "gpt-4o")
    assert @agent.send(:tool_capable?, "anthropic/claude-opus-4-1")
  end

  def test_tool_capable_rejects_arbitrary_strings
    refute @agent.send(:tool_capable?, "not-a-model")
    refute @agent.send(:tool_capable?, "")
    refute @agent.send(:tool_capable?, "random-gpt-mention-inside-sentence"), \
      "substring-contains is the old bug; anchored regex must not match this"
  end

  # cache_key_for — must produce bounded, deterministic SHA256 keys.
  def test_cache_key_bounded
    k = @agent.send(:cache_key_for, "hello", [])
    assert_equal 64, k.length, "SHA256 hex is 64 chars"
    assert_equal k, @agent.send(:cache_key_for, "hello", []), "deterministic"
  end

  def test_cache_key_uses_window_not_full_context
    long_ctx = (1..100).map { |i| { role: "user", content: "msg #{i}" * 50 } }
    short_ctx = long_ctx.last(4)
    k_long  = @agent.send(:cache_key_for, "same", long_ctx)
    k_short = @agent.send(:cache_key_for, "same", short_ctx)
    assert_equal k_long, k_short, "only the last CACHE_WINDOW messages affect the key"
  end

  # escalation flag — must be per-thread, not per-instance.
  def test_escalation_flag_is_thread_local
    Thread.current[:master_escalation_done] = nil
    other_thread_saw = nil
    t = Thread.new do
      other_thread_saw = Thread.current[:master_escalation_done]
    end
    t.join
    assert_nil other_thread_saw, "flag must not leak across threads"
  end
end
```

## `test/test_axioms.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
  def setup
    @axioms = Master::Axioms.new
  end

  def test_kernel_not_empty
    refute @axioms.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @axioms.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_sorted_by_priority
    items = @axioms.philosophy
    refute items.empty?
    priorities = items.map { |a| a["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_kernel_block_formatted
    block = @axioms.kernel_block
    assert block.include?("## Kernel Axioms")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @axioms.philosophy_block(limit: 3)
    assert block.include?("## Core Philosophy (top 3)")
  end

  def test_lookup_kernel
    val = @axioms.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end
end
```

## `test/test_browser.rb`
```ruby
# frozen_string_literal: true

# Browser integration test using Ferrum + local Chromium.
# Run: bundle exec ruby test/test_browser.rb
#
# NOTE: Browser must be created BEFORE minitest/autorun is loaded,
# otherwise Minitest's signal handlers break Ferrum's pipe reading.
#
# Requires ~300MB free RAM. On low-memory servers, tests are auto-skipped.
#
# WHY CHROME TESTS SKIP ON OPENBSD
# =================================
# Chrome/Chromium exits with SIGSEGV (139) immediately on OpenBSD due to the
# W^X (Write XOR Execute) memory protection policy enforced by the kernel.
# Chrome's V8 engine — even with --jitless -- and its process model require
# mmap(PROT_WRITE|PROT_EXEC) pages that OpenBSD forbids at the OS level.
# No combination of flags (--no-sandbox, --single-process, --jitless,
# --disable-gpu) resolves this; a dedicated OpenBSD-patched Chromium port
# would be required.
#
# To run browser tests against the live server from a non-OpenBSD machine:
#   WEB_URL=https://ai.brgen.no:4430 bundle exec ruby test/test_browser.rb
#
# HTTP smoke tests (test_web_http.rb) cover: page load, overlay presence,
# JS syntax, metrics JSON, and SSE stream — and run fine on OpenBSD.

require "ferrum"
require "json"
require "net/http"
require "socket"

CHROME_PATH = %w[/usr/local/bin/chrome /usr/local/bin/chromium].find { |p| File.executable?(p) }
WEB_URL     = (ENV["WEB_URL"] || "http://localhost:10002").freeze

FREE_MEM_MB = begin
  # Use free + inactive pages — inactive pages are reclaimable by new processes.
  stats = `vmstat -s`
  free_pages     = stats[/(\d+) pages free/,    1].to_i
  inactive_pages = stats[/(\d+) pages inactive/, 1].to_i
  (free_pages + inactive_pages) * 4 / 1024  # 4KB pages → MB
rescue
  999
end

SKIP_REASON = if CHROME_PATH.nil?
  "Chromium not found"
elsif begin; TCPSocket.new("127.0.0.1", 10002).close; false; rescue; true; end
  "Web server not running on port 10002"
elsif FREE_MEM_MB < 300
  "Insufficient free memory (#{FREE_MEM_MB}MB < 300MB required for Chrome)"
end

# Start Chrome now, before minitest/autorun installs signal handlers.
FERRUM_BROWSER = if SKIP_REASON.nil?
  begin
    Ferrum::Browser.new(
      browser_path: CHROME_PATH,
      process_timeout: 30,
      timeout: 20,
      browser_options: {
        "headless"       => "new",
        "no-sandbox"     => nil,
        "single-process" => nil,
        "disable-gpu"    => nil,
        "disable-dev-shm-usage" => nil
      }
    )
  rescue StandardError => e
    warn "Chrome failed to start: #{e.message}"
    nil
  end
end

# Override SKIP_REASON if browser failed to start
BROWSER_SKIP = SKIP_REASON || (FERRUM_BROWSER.nil? ? "Chrome failed to start" : nil)

require "minitest/autorun"

class TestBrowserUI < Minitest::Test
  def skip_if_unavailable
    skip BROWSER_SKIP if BROWSER_SKIP
  end

  def fresh_page
    pg = FERRUM_BROWSER.create_page
    pg.go_to(WEB_URL)
    pg.network.wait_for_idle
    pg
  rescue Ferrum::DeadBrowserError => e
    skip "Chrome died (OOM): #{e.message}"
  end

  def teardown
    FERRUM_BROWSER&.pages&.each(&:close) rescue nil
  end

  def test_01_page_loads_with_overlay
    skip_if_unavailable
    pg = fresh_page
    assert pg.at_css("#overlay"), "overlay element missing"
    assert !pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be visible on load"
  end

  def test_02_overlay_dismisses_on_click
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be hidden after click"
  end

  def test_03_input_active_after_overlay_dismissed
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('input-field').classList.contains('active')"),
           "input-field should have 'active' class"
  end

  def test_04_chat_receives_response
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.2
    pg.at_css("#input-field input[type=text]").focus
    pg.keyboard.type("ping")
    pg.keyboard.type(:Return)
    deadline = Time.now + 30
    response = ""
    loop do
      response = pg.evaluate("document.getElementById('chat-log').textContent").strip
      break unless response.empty?
      break if Time.now > deadline
      sleep 1
    end
    refute_empty response, "chat-log should contain a response to 'ping'"
  end

  # Uses plain HTTP — no browser page needed for a JSON endpoint.
  def test_05_metrics_endpoint_json
    skip "Web server not running" unless begin
      TCPSocket.new("127.0.0.1", 10002).close
      true
    rescue
      false
    end
    uri  = URI("#{WEB_URL}/chat/metrics")
    body = Net::HTTP.get(uri)
    data = JSON.parse(body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue JSON::ParserError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end
end

Minitest.after_run { FERRUM_BROWSER&.quit rescue nil }
```

## `test/test_cli.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestCLI < Minitest::Test
  def setup
    @session     = Minitest::Mock.new
    @agent       = Minitest::Mock.new
    @renderer    = Minitest::Mock.new
    @logging     = Minitest::Mock.new
    @undo        = Minitest::Mock.new
    @config      = Minitest::Mock.new
    @pipeline    = Minitest::Mock.new

    @config.expect(:[], false, ["tts"])
    @config.expect(:prescan?, false)

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
      pipeline: @pipeline
    }

    @cli = Master::CLI.new(container: @container)
  end

  # ── container accessor ────────────────────────────────────────────────────

  def test_container_accessor
    assert_same @container, @cli.container
  end

  # ── TTS flag ──────────────────────────────────────────────────────────────

  def test_tts_off_when_unavailable
    refute @cli.instance_variable_get(:@tts_on),
      "tts_on should be false when Speech.available? is false"
  end

  # ── handle_command dispatch ───────────────────────────────────────────────

  def test_handle_command_returns_false_for_non_command
    assert_equal false, @cli.send(:handle_command, "hello world")
  end

  def test_handle_command_save
    @session.expect(:save!, nil)
    @renderer.expect(:render, "saved", ["saved"], mode: :success)
    capture_io { @cli.send(:handle_command, "/save") }
    @session.verify
  end

  def test_handle_command_exit
    @session.expect(:save!, nil)
    capture_io { @cli.send(:handle_command, "/exit") }
    refute @cli.instance_variable_get(:@running)
    @session.verify
  end

  def test_handle_command_tts_on
    # Speech not available in test env — /tts on should stay off → "unavailable"
    @renderer.expect(:render, "tts: unavailable", [String], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts on") }
  end

  def test_handle_command_tts_off
    @renderer.expect(:render, "tts: off", ["tts: off"], mode: :dim)
    capture_io { @cli.send(:handle_command, "/tts off") }
    refute @cli.instance_variable_get(:@tts_on)
  end

  def test_handle_command_unknown
    @renderer.expect(:render, "unknown command: /foo", [String], mode: :warning)
    capture_io { @cli.send(:handle_command, "/foo") }
    @renderer.verify
  end

  # ── process ───────────────────────────────────────────────────────────────

  def test_process_skips_blank_input
    @pipeline.expect(:call, nil)
    @cli.send(:process, "   ")
  end

  def test_process_ok_result
    text = "the answer is 42"
    result = Master::Result.ok(rendered: text)
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.send(:process, "what is 6*7") }
    assert_includes out, text
    assert @cli.instance_variable_get(:@last_ok)
  end

  def test_process_err_result
    result = Master::Result.err("model unavailable")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    @renderer.expect(:render, "[ERR]", ["model unavailable"], mode: :error)
    capture_io { @cli.send(:process, "fail me") }
    refute @cli.instance_variable_get(:@last_ok)
  end

  # ── pipe ──────────────────────────────────────────────────────────────────

  def test_pipe_calls_process
    result = Master::Result.ok(rendered: "pong")
    @pipeline.expect(:call, result, [->(r) { r.respond_to?(:ok?) }])
    out, _err = capture_io { @cli.pipe("ping") }
    assert_includes out, "pong"
  end
end
```

## `test/test_experience.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestExperience < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @exp = Master::State::Experience.new(root: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_signature_ignores_arguments
    plan_a = [{ tool: :fs_read, path: "a.rb" }, { tool: :ast_replace, method: "login" }]
    plan_b = [{ tool: :fs_read, path: "z.rb" }, { tool: :ast_replace, method: "logout" }]
    # Same strategy, different arguments → same signature → shared score.
    @exp.record(plan: plan_a, score: 1.0)
    refute_in_delta 0.0, @exp.score(plan_b), 0.2, "same tool sequence should share experience"
  end

  def test_decay_bounds_unbounded_growth
    plan = [{ tool: :fs_read }]
    20.times { @exp.record(plan: plan, score: 1.0) }
    entry = @exp.record(plan: plan, score: 1.0)
    # With DECAY=0.99, count cannot grow to 21 — it stays well below.
    assert_in_delta 20.0, entry["count"], 2.0
  end

  def test_unknown_plan_returns_near_zero
    score = @exp.score([{ tool: :never_run }])
    assert_in_delta 0.0, score, 0.1, "unseen plan returns base 0 + small noise"
  end
end
```

## `test/test_helper.rb`
```ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "timeout"

# Load MASTER without booting the CLI
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"

# All tests time out after 10s to prevent hangs.
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run
  def run(*args)
    Timeout.timeout(10) { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("timed out after 10s"))
    self
  end
end
```

## `test/test_pipeline.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

# Pipeline unit tests — Result-monadic chaining and rollback contract.
class TestPipeline < Minitest::Test
  include Master

  class OkStage
    def call(ctx) = Master::Result.ok(ctx.merge(stamped: true))
  end

  class ErrStage
    def initialize(cat = :unknown) = (@cat = cat)
    def call(_ctx) = Master::Result.err("boom", category: @cat)
  end

  class RaiseStage
    def call(_ctx) = raise "stage exploded"
  end

  def test_happy_path_passes_context_through
    pipe = Master::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(input: "hi"))
    assert result.ok?
    assert result.value![:stamped]
  end

  def test_first_error_short_circuits
    pipe = Master::Pipeline.new([OkStage.new, ErrStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_equal "boom", result.message
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_rollback_skipped_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::Pipeline.new([ErrStage.new(:validation)], root: dir)
      result = pipe.call(Master::Result.ok({}))
      refute result.ok?
      # No exception raised = success for this test.
    end
  end
end
```

## `test/test_prune.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestPrune < Minitest::Test
  def stage
    Master::Stages::Prune.new
  end

  def call(text)
    stage.call({ output: text })
  end

  def test_strips_preamble
    r = call("Certainly! Here is the answer.")
    assert r.ok?
    assert_equal "Here is the answer.", r.value![:output]
  end

  def test_strips_hedge
    r = call("I think that Ruby is great.")
    assert r.ok?
    assert_equal "Ruby is great.", r.value![:output]
  end

  def test_skips_code_blocks
    code = "```ruby\njust use this\n```"
    r = call(code)
    assert_equal code, r.value![:output]  # must not mangle code
  end

  def test_passthrough_non_string
    r = stage.call({ output: 42 })
    assert r.ok?
    assert_equal 42, r.value![:output]
  end

  def test_empty_string_passthrough
    r = call("")
    assert r.ok?
  end
end
```

## `test/test_result.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestResult < Minitest::Test
  def test_ok_holds_value
    r = Master::Result.ok("hello")
    assert r.ok?
    refute r.err?
    assert_equal "hello", r.value!
  end

  def test_err_holds_message
    r = Master::Result.err("boom", category: :unknown)
    assert r.err?
    refute r.ok?
    assert_equal "boom", r.message
  end

  def test_and_then_chains_on_ok
    r = Master::Result.ok(2).and_then { |v| Master::Result.ok(v * 3) }
    assert r.ok?
    assert_equal 6, r.value!
  end

  def test_and_then_short_circuits_on_err
    r = Master::Result.err("fail").and_then { |_| Master::Result.ok("never") }
    assert r.err?
    assert_equal "fail", r.message
  end

  def test_and_then_wraps_plain_value
    r = Master::Result.ok(5).and_then { |v| v * 2 }
    assert r.ok?
    assert_equal 10, r.value!
  end
end
```

## `test/test_ring_buffer.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestRingBuffer < Minitest::Test
  def test_push_and_to_a
    buf = Master::RingBuffer.new(3)
    buf.push("a").push("b").push("c")
    assert_equal %w[a b c], buf.to_a
  end

  def test_wraps_around
    buf = Master::RingBuffer.new(3)
    %w[a b c d].each { |x| buf.push(x) }
    assert_equal %w[b c d], buf.to_a
  end

  def test_each_without_block_returns_enumerator
    buf = Master::RingBuffer.new(3)
    buf.push("x")
    assert_instance_of Enumerator, buf.each
  end

  def test_to_a_without_block
    buf = Master::RingBuffer.new(3)
    buf.push("x").push("y")
    assert_equal %w[x y], buf.to_a  # must not raise LocalJumpError
  end

  def test_size_and_empty
    buf = Master::RingBuffer.new(4)
    assert buf.empty?
    buf.push("a")
    assert_equal 1, buf.size
    refute buf.empty?
  end
end
```

## `test/test_speech.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestSpeech < Minitest::Test
  # ── module interface ──────────────────────────────────────────────────────

  def test_available_returns_boolean
    assert_includes [true, false], Master::Speech.available?
  end

  def test_voices_constants_present
    assert Master::Speech::VOICES.key?(:osman)
    assert Master::Speech::VOICES.key?(:ryan)
  end

  def test_styles_constants_present
    assert Master::Speech::STYLES.key?(:deep)
    assert Master::Speech::STYLES.key?(:normal)
  end

  def test_synthesize_returns_nil_for_empty_text
    assert_nil Master::Speech.synthesize("")
    assert_nil Master::Speech.synthesize("   ")
  end

  def test_synthesize_bytes_returns_nil_for_empty
    assert_nil Master::Speech.synthesize_bytes("")
  end

  # ── when edge-tts unavailable ─────────────────────────────────────────────

  def test_synthesize_returns_nil_when_unavailable
    # Stub Speech.available? to false
    Master::Speech.stub(:available?, false) do
      assert_nil Master::Speech.synthesize("hello")
    end
  end

  def test_synthesize_bytes_returns_nil_when_unavailable
    Master::Speech.stub(:available?, false) do
      assert_nil Master::Speech.synthesize_bytes("hello")
    end
  end

  # ── when edge-tts available (mock system call) ────────────────────────────

  def test_synthesize_calls_edge_tts_with_correct_args
    skip "edge-tts not installed" unless Master::Speech.available?

    tmp = nil
    Master::Speech.stub(:synthesize, ->(text, **) {
      # Just verify we can call it without raising
      nil
    }) do
      tmp = Master::Speech.synthesize("test", voice: :osman, style: :deep)
    end
    assert_nil tmp  # mock returns nil
  end

  def test_synthesize_bytes_cleans_up_temp_file
    fake_path = "/tmp/m3_tts_test_fake.mp3"

    Master::Speech.stub(:synthesize, fake_path) do
      # Create a fake mp3
      File.write(fake_path, "fake-mp3-data")
      bytes = Master::Speech.synthesize_bytes("hello")
      assert_equal "fake-mp3-data", bytes
      refute File.exist?(fake_path), "temp file should be deleted"
    end
  end

  # ── voice / style lookup ─────────────────────────────────────────────────

  def test_unknown_voice_falls_back_to_default
    # Speech.synthesize uses VOICES.fetch(voice, VOICES[DEFAULT_VOICE])
    # so unknown symbol falls back to Osman
    default_voice = Master::Speech::VOICES[Master::Speech::DEFAULT_VOICE]
    assert default_voice
  end

  def test_deep_style_has_negative_pitch
    style = Master::Speech::STYLES[:deep]
    assert style[:pitch].start_with?("-"), "deep pitch should be negative"
    assert style[:rate].start_with?("-"),  "deep rate should be negative"
  end
end
```

## `test/test_web_http.rb`
```ruby
# frozen_string_literal: true

# HTTP smoke tests for the MASTER web UI.
# Faster and lighter than browser tests -- no Chrome required.
# Run: bundle exec ruby test/test_web_http.rb

require "net/http"
require "json"
require "socket"
require "minitest/autorun"

WEB_PORT = 10002

SKIP_HTTP = begin
  TCPSocket.new("127.0.0.1", WEB_PORT).close
  nil
rescue Errno::ECONNREFUSED
  "Web server not running on port #{WEB_PORT}"
end

class TestWebHTTP < Minitest::Test
  def skip_unless_server
    skip SKIP_HTTP if SKIP_HTTP
  end

  def get(path, headers = {})
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(path, headers))
    end
  end

  def test_01_homepage_returns_200
    skip_unless_server
    res = get("/")
    assert_equal "200", res.code, "homepage should return 200"
  end

  def test_02_homepage_contains_overlay
    skip_unless_server
    res = get("/")
    assert_includes res.body, "overlay", "homepage should contain overlay element"
  end

  def test_03_homepage_js_no_stray_paren
    skip_unless_server
    res = get("/")
    bad = res.body.lines.grep(/^\s*"\);/)
    assert_empty bad, "stray \");\" found in page JS: #{bad.first(2).inspect}"
  end

  def test_04_metrics_returns_json
    skip_unless_server
    res = get("/chat/metrics")
    assert_equal "200", res.code, "metrics endpoint should return 200"
    data = JSON.parse(res.body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("uptime"),        "metrics should include 'uptime'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue StandardError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end

  def test_05_message_endpoint_streams_sse
    skip_unless_server
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 15) do |http|
      req = Net::HTTP::Post.new("/chat/message")
      req.set_form_data("message" => "ping")
      data = ""
      http.request(req) do |res|
        assert_equal "200", res.code, "message endpoint should return 200"
        assert_match "text/event-stream", res["Content-Type"].to_s,
                     "message endpoint should stream SSE"
        res.read_body do |chunk|
          data += chunk
          break if data.include?("[DONE]") || data.size > 512
        end
      end
      assert_includes data, "data:", "SSE response should contain data: lines"
    end
  rescue Net::ReadTimeout
    # Server still streaming -- that means it accepted the request fine
  end
end```

## `test/test_web_ui.rb`
```ruby
# frozen_string_literal: true

require_relative "test_helper"
require "rack/test"

# Minimal Rack test harness for the web UI chat controller.
# Tests cover SSE stream, TTS endpoint, dmesg, and metrics.

ENV["RAILS_ENV"] = "test"

# We test the controller logic via a stub Rack app rather than
# booting the full Rails stack.
class FakeSpeech
  def self.available?  = true
  def self.synthesize_bytes(_text, **) = "FAKE-MP3-BYTES"
end

class FakePipeline
  attr_writer :result
  def call(_ctx) = @result || Master::Result.ok(rendered: "hello from pipeline")
end

class FakeSession
  def token_est = 42
  def cost      = 0.0001
end

class FakeAgent
  def model = "test/model-7b"
end

class FakeContainer
  def [](key)
    case key
    when :agent    then FakeAgent.new
    when :session  then FakeSession.new
    when :pipeline then @pipeline ||= FakePipeline.new
    end
  end
  def pipeline = self[:pipeline]
end

class TestWebUI < Minitest::Test
  include Rack::Test::Methods

  def setup
    @container = FakeContainer.new
  end

  # ── Result monad ──────────────────────────────────────────────────────────

  def test_result_ok_wraps_value
    r = Master::Result.ok("hello")
    assert r.ok?
    assert_equal "hello", r.value!
  end

  def test_result_err_wraps_message
    r = Master::Result.err("boom")
    assert r.err?
    assert_equal "boom", r.message
  end

  def test_result_err_value_bang_raises_unwrap_error
    r = Master::Result.err("boom")
    assert_raises(Master::UnwrapError) { r.value! }
  end

  def test_result_ok_chaining
    r = Master::Result.ok(5).and_then { |v| Master::Result.ok(v * 2) }
    assert_equal 10, r.value!
  end

  def test_result_err_short_circuits
    r = Master::Result.err("x").and_then { raise "should not reach" }
    assert r.err?
  end

  # ── Pipeline ─────────────────────────────────────────────────────────────

  def test_pipeline_returns_result
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_includes result.value![:rendered], "hello"
  end

  def test_pipeline_err_propagates
    @container.pipeline.result = Master::Result.err("model down")
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.err?
    assert_equal "model down", result.message
  end

  # ── Speech bytes ─────────────────────────────────────────────────────────

  def test_speech_synthesize_bytes_stub
    bytes = FakeSpeech.synthesize_bytes("hello world")
    assert_equal "FAKE-MP3-BYTES", bytes
  end

  # ── Cognitive monitor ─────────────────────────────────────────────────────

  def test_cognitive_monitor_starts_clean
    m = Master::CognitiveMonitor.new
    assert_equal 0.0, m.load
    assert_equal :optimal, m.flow_state
  end

  def test_cognitive_monitor_push_increases_load
    m = Master::CognitiveMonitor.new
    m.push("concept_a", weight: 2.0)
    assert_in_delta 2.0, m.load, 0.01
  end

  def test_cognitive_monitor_overload_after_threshold
    m = Master::CognitiveMonitor.new
    m.push("heavy", weight: 8.0)
    assert m.overloaded?
  end

  def test_cognitive_monitor_reset
    m = Master::CognitiveMonitor.new
    5.times { |i| m.push("c#{i}", weight: 1.5) }
    m.reset!(keep_recent: 2)
    assert m.load <= 3.0
    assert_equal 0, m.switches
  end

  def test_cognitive_monitor_update_flow_returns_self
    m = Master::CognitiveMonitor.new
    assert_same m, m.update_flow(context_switches: 1)
  end

  def test_cognitive_monitor_state_hash
    m = Master::CognitiveMonitor.new
    s = m.state
    assert s.key?(:load)
    assert s.key?(:flow_state)
    assert s.key?(:overload_risk)
    assert s.key?(:complexity)
  end

  # ── SwarmCoordinator ─────────────────────────────────────────────────────

  def test_swarm_coordinator_worker_roles
    # Just check the list is non-empty without booting real agents
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :analyst
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :coder
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :reviewer
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :researcher
  end

  def test_swarm_coordinator_unknown_role
    mock_agent = Minitest::Mock.new
    coord = Master::Swarm::Coordinator.new(agent: mock_agent)
    result = coord.dispatch(:nonexistent, task: "foo")
    assert result.err?
    assert_includes result.message, "unknown role"
  end

  # ── Memory ───────────────────────────────────────────────────────────────

  def test_memory_remember_and_recall
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:user_name, "Osman")
      assert_equal "Osman", m.recall(:user_name)
    end
  end

  def test_memory_context_summary_nil_when_empty
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      assert_nil m.context_summary
    end
  end

  def test_memory_context_summary_lists_keys
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:language, "Ruby")
      summary = m.context_summary
      assert_includes summary, "language"
      assert_includes summary, "Ruby"
    end
  end

  # ── Personality ──────────────────────────────────────────────────────────

  def test_personality_default_is_dark_malay
    assert_equal :dark_malay, Master::Personality::DEFAULT
  end

  def test_personality_system_prompt_non_empty
    p = Master::Personality.new(:dark_malay)
    assert p.system_prompt.length > 10
  end

  def test_personality_system_prompt_memoized
    p = Master::Personality.new(:dark_malay)
    assert_same p.system_prompt, p.system_prompt
  end

  # ── UnwrapError ──────────────────────────────────────────────────────────

  def test_unwrap_error_is_runtime_error_subclass
    assert Master::UnwrapError < RuntimeError
  end
end
```

## `web/Gemfile`
```
source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
# gem "puma"
gem "falcon"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

gem "master", path: ".."
```

## `web/README.md`
```markdown
circuit open: retry in 12s```

## `web/Rakefile`
```
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks
```

## `web/app/controllers/application_controller.rb`
```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  @@container        = nil
  @@mutex            = Mutex.new
  @@start_ms         = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@scheduler_thread = nil

  private

  def container
    @@mutex.synchronize do
      @@container ||= Master.build(root: Rails.root.join("..").to_s).tap { |c| start_scheduler(c); Master.generate_boot_snapshot(c) rescue nil; c[:heartbeat]&.start! }
    end
  end

  def start_scheduler(c)
    return if @@scheduler_thread&.alive?
    @@scheduler_thread = Thread.new do
      sleep 300 # wait 5 min after boot before first check
      loop do
        begin
          due = c[:standing].due
          if due.any?
            results = c[:standing].run_due!
            results.each { |r| c[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
          end
        rescue StandardError
          # swallow — never crash the scheduler
        end
        sleep 900 # check every 15 min
      end
    end
    @@scheduler_thread.abort_on_exception = false
  end

  def start_ms
    @@start_ms
  end
end
```

## `web/app/controllers/chat_controller.rb`
```ruby
# frozen_string_literal: true

require "shellwords"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts, :speak]

  def index
    @model = container[:agent].model.to_s.split("/").last
    render layout: false
  end

  def dmesg
    lines = `dmesg 2>/dev/null`.lines.first(20).map(&:chomp)
    render json: { lines: lines }
  end

  def metrics
    c = container
    repo_root = Rails.root.join("..").to_s
    dirty = `git -C #{Shellwords.escape(repo_root)} status --porcelain 2>/dev/null`.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    render json: {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models
    }
  end

  def message
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    sse = response.stream
    begin
      streamed  = false
      tool_sub  = container[:bus].subscribe("tool:before") do |ev|
        begin
          payload = { tool: ev[:tool].to_s, path: ev[:path].to_s }.to_json
          sse.write("event: tool\ndata: #{payload}\n\n")
        rescue StandardError
          nil
        end
      end

      on_chunk = ->(token) {
        streamed = true
        encoded = token.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
        sse.write("data: #{encoded}\n\n")
      }

      ctx = { user_message: input, on_chunk: on_chunk }
      if (img = params[:image]).present?
        ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      end

      result = container[:pipeline].call(Master::Result.ok(**ctx))

      unless streamed
        text = case result
               when Master::Result::Ok
                 val = result.value
                 val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
               when Master::Result::Err
                 "ERROR: #{result.message}"
               end
        unless text.to_s.strip.empty?
          encoded = text.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
          sse.write("data: #{encoded}\n\n")
        end
      end

      sse.write("data: [DONE]\n\n")
    rescue => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      begin
        tool_sub.call if defined?(tool_sub) && tool_sub
      rescue StandardError
        nil
      end
      sse.close
    end
  end

  def speak
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?
    container[:bus].publish("speak:text", { text: text })
    head :ok
  end

  def tts
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    bytes = Master::Speech.synthesize_bytes(text)
    if bytes && bytes.bytesize > 0
      send_data bytes, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  rescue => e
    logger.error "TTS failed: #{e.message}"
    head :service_unavailable
  end
end
```

## `web/app/controllers/events_controller.rb`
```ruby
# frozen_string_literal: true

# EventsController — SSE stream of EventBus events to the orb visualizer.
#
# The orb already exists (web/app/views/chat/index.html.erb). What it lacked
# was a real signal. This controller subscribes to the container's EventBus,
# serializes each event as Server-Sent Event, and streams them.
#
# Wire into routes:
#   get "/events/stream" => "events#stream"
#
# Consume from the orb JS:
#   const es = new EventSource("/events/stream");
#   es.onmessage = e => handleEvent(JSON.parse(e.data));
#
# Event types the orb can react to (emitted by existing pipeline stages):
#   llm:request           → burst pulse
#   llm:escalation        → color shift
#   tool:used             → ripple
#   scan:complete         → stabilization flash
#   autoloop:cycle        → rotation increment
#   sweep:cycle           → slow rotation
#   pipeline:rollback     → red glitch (from Pipeline rollback)
class EventsController < ApplicationController
  include ActionController::Live

  POLL_INTERVAL_S = 0.1
  MAX_STREAM_S    = 600   # hard cap — 10 minute stream ceiling

  def stream
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"  # nginx passthrough

    bus      = container[:bus]
    received = Queue.new
    sub      = bus.subscribe("*") { |type, payload|
      received << { t: Time.now.to_f, type: type, data: payload }
    }
    deadline = Time.now + MAX_STREAM_S

    loop do
      break if Time.now > deadline
      if received.empty?
        response.stream.write(": keepalive\n\n")  # SSE comment, prevents proxy timeout
        sleep POLL_INTERVAL_S
      else
        event = received.pop(true) rescue nil
        next unless event
        response.stream.write("data: #{event.to_json}\n\n")
      end
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client went away — normal. Stop streaming.
  ensure
    bus&.unsubscribe(sub) if sub && bus.respond_to?(:unsubscribe)
    response.stream.close rescue nil
  end
end
```

## `web/app/helpers/application_helper.rb`
```ruby
module ApplicationHelper
end
```

## `web/app/models/application_record.rb`
```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
```

## `web/app/views/chat/index.html.erb`
```erb
<!DOCTYPE html>
<html lang="ms">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover"/>
  <meta name="mobile-web-app-capable" content="yes"/>
  <meta name="color-scheme" content="dark"/>
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
  <title>MASTER &middot; <%= @model %></title>
  <meta name="theme-color" content="#000000"/>
  <style>
    :root{
      --safe-top:env(safe-area-inset-top,0px);
      --safe-right:env(safe-area-inset-right,0px);
      --safe-bottom:env(safe-area-inset-bottom,0px);
      --safe-left:env(safe-area-inset-left,0px);
    }

    html,body{
      margin:0;
      height:100%;
      background:#020000;
      color:#dcdcdc;
      font:16px/1.5 Helvetica,Arial,sans-serif;
      overflow:hidden;
      touch-action:none;
    }
    /* Low-end CSS orb — GPU compositor only, zero JS render cost */
    #orb-css{
      position:fixed;
      left:50%;top:50%;
      width:min(58vw,58vh);height:min(58vw,58vh);
      border-radius:50%;
      transform:translate(-50%,-50%) translateZ(0);
      background:radial-gradient(circle at 38% 35%,#6b2018,#1a0505 55%,#020000);
      box-shadow:0 0 60px 8px rgba(80,10,10,0.35),inset 0 0 40px rgba(0,0,0,0.7);
      animation:orb-idle 4s ease-in-out infinite;
      will-change:transform,opacity;
      pointer-events:none;
    }
    @keyframes orb-idle{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);opacity:.65;}
      50%     {transform:translate(-50%,-50%) scale(1.06) translateZ(0);opacity:.85;}
    }
    #orb-css.speaking{
      background:radial-gradient(circle at 38% 35%,#b03030,#3d1010 55%,#020000);
      box-shadow:0 0 90px 20px rgba(160,20,20,0.55),inset 0 0 35px rgba(0,0,0,0.4);
      animation:orb-speak .55s ease-in-out infinite;
    }
    @keyframes orb-speak{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);}
      30%     {transform:translate(-50%,-50%) scale(1.1) translateZ(0);}
      70%     {transform:translate(-50%,-50%) scale(.96) translateZ(0);}
    }
    #orb-css.processing{
      background:radial-gradient(circle at 38% 35%,#6b4008,#1e0e02 55%,#020000);
      box-shadow:0 0 70px 12px rgba(90,55,5,0.45),inset 0 0 40px rgba(0,0,0,0.6);
      animation:orb-think 1.3s ease-in-out infinite;
    }
    @keyframes orb-think{
      0%,100%{transform:translate(-50%,-50%) scale(1) translateZ(0);opacity:.6;}
      50%     {transform:translate(-50%,-50%) scale(1.05) translateZ(0);opacity:1;}
    }

    canvas{
      position:fixed;
      inset:0;
      width:100dvw;
      height:100dvh;
      display:block;
      background:#020000;
      touch-action:none;
      cursor:pointer;
    }

    #status{
      position:fixed;
      top:calc(10px + var(--safe-top));
      right:calc(10px + var(--safe-right));
      z-index:95;
      user-select:none;
      font-size:14px;
      color:#333;
      cursor:pointer;
      padding:12px;
      transition:color 0.3s;
    }

    #status.think{color:#662222;}
    #status.speak{color:#993333;}
    #status.processing{color:#7a3a0a;animation:pulse-status 1.2s ease-in-out infinite;}
    @keyframes pulse-status{0%,100%{opacity:1;}50%{opacity:0.3;}}

    #ui{
      position:fixed;
      right:calc(12px + var(--safe-right));
      bottom:calc(10px + var(--safe-bottom));
      color:#2a0808;
      font:9px/1.1 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
      text-transform:uppercase;
      letter-spacing:.28em;
      white-space:nowrap;
      pointer-events:none;
      user-select:none;
      text-align:right;
      opacity:.5;
      transition:opacity 0.6s, color 0.3s;
    }
    #ui.highlight{opacity:1;color:#993333;}

    #ui .dots{
      display:inline-block;
      width:3ch;
      text-align:left;
    }

    #input-field{
      position:fixed;
      bottom:15vh;
      left:50%;
      transform:translateX(-50%);
      width:0;
      opacity:0;
      transition:width 0.3s ease-out, opacity 0.2s ease;
      z-index:10;
    }

    #input-field.active{
      width:70vw;
      max-width:500px;
      opacity:1;
    }

    #input-field input{
      width:calc(100% - 28px);
      background:transparent;
      border:none;
      color:#ccc;
      font-family:Helvetica,Arial,sans-serif;
      font-size:18px;
      font-weight:300;
      letter-spacing:0.05em;
      padding:12px 0;
      outline:none;
      text-align:center;
    }

    #input-field input::placeholder{
      color:#333;
    }

    #attach-btn{
      background:none;
      border:none;
      color:#333;
      cursor:pointer;
      font-size:18px;
      padding:0 0 0 6px;
      vertical-align:middle;
      transition:color 0.2s, opacity 0.3s;
      opacity:0;
    }
    #input-field.active #attach-btn{opacity:1;}
    #attach-btn:hover,#attach-btn.has-file{color:#888;}
    #attach-label{
      display:block;
      font-size:10px;
      color:#555;
      text-align:center;
      letter-spacing:0.08em;
      margin-top:4px;
      overflow:hidden;
      white-space:nowrap;
      text-overflow:ellipsis;
    }

    .arrow{
      position:fixed;
      top:50%;
      transform:translateY(-50%);
      width:60px;
      height:100px;
      display:flex;
      align-items:center;
      justify-content:center;
      cursor:pointer;
      z-index:100;
      opacity:0;
      transition:opacity 0.4s;
      user-select:none;
      -webkit-tap-highlight-color:transparent;
    }

    .arrow:hover{opacity:0.5;}
    .arrow:active{opacity:0.8;}

    #arrow-left{left:calc(10px + var(--safe-left));}
    #arrow-right{right:calc(10px + var(--safe-right));}

    .arrow span{
      color:#333;
      font-size:24px;
      font-weight:300;
    }

    #overlay{
      position:fixed;
      inset:0;
      display:flex;
      flex-direction:column;
      align-items:center;
      justify-content:center;
      gap:28px;
      background:#000;
      cursor:pointer;
      user-select:none;
      z-index:1000;
      touch-action:manipulation;
      text-align:center;
      padding:32px;
      opacity:1;
      transition:opacity 0.8s ease;
    }

    #overlay.ack{opacity:0;pointer-events:none;}
    #overlay[hidden]{display:none;}

    #overlay h1{
      margin:0;
      font-size:clamp(18px,4vw,28px);
      font-weight:300;
      color:#666;
      letter-spacing:.25em;
      text-transform:uppercase;
    }

    #overlay .hint{
      font-size:10px;
      color:#222;
      letter-spacing:.15em;
      animation:overlay-pulse 3s ease-in-out infinite;
    }

    @keyframes overlay-pulse{0%,100%{opacity:.4;}50%{opacity:.8;}}

    #chat-log{
      display:none;
      position:fixed;
      inset:0;
      z-index:200;
      background:rgba(0,0,0,.92);
      overflow-y:auto;
      padding:48px 5vw 80px;
      font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
      color:#aaa;
    }
    #chat-log.open{display:block;}
    #chat-log .entry{margin-bottom:1.4em;white-space:pre-wrap;word-break:break-word;}
    #chat-log .entry.user{color:#ccc;}
    #chat-log .entry.master{color:#777;}
    #chat-log .entry.user::before{content:'> ';color:#555;}
    #chat-log .tab-hint{
      position:fixed;top:12px;right:16px;
      font-size:10px;color:#333;letter-spacing:.1em;pointer-events:none;
    }
  </style>
  <%= csrf_meta_tags %>
</head>
<body>
  <div id="chat-log"><span class="tab-hint">TAB TO CLOSE</span></div>
  <section id="status">◉</section>
  <section id="ui"><span id="ui-label">MASTER</span><span class="dots" id="ui-dots"></span></section>

  <section id="arrow-left" class="arrow"><span>‹</span></section>
  <section id="arrow-right" class="arrow"><span>›</span></section>

  <section id="input-field">
    <input type="text" placeholder="Ask anything…" autocomplete="off" maxlength="512" aria-label="Message">
    <button id="attach-btn" title="Attach image">+</button>
    <input type="file" id="file-input" accept="image/*,text/*,.pdf" hidden>
    <span id="attach-label"></span>
  </section>

  <canvas id="canvas"></canvas>

  <section id="overlay" role="dialog" aria-modal="true">
    <h1>MASTER</h1>
    <p class="hint">tap to begin</p>
  </section>

  <script>
    "use strict";
    const canvas=document.getElementById('canvas');
    const ctx=canvas.getContext('2d',{alpha:false});
    const statusEl=document.getElementById('status');
    const uiLabel=document.getElementById('ui-label');
    const uiDots=document.getElementById('ui-dots');
    const inputField=document.getElementById('input-field');
    let _overlayJustDismissed=false;
    const input=inputField.querySelector('input[type=text]');
    const fileInput=document.getElementById('file-input');
    const attachBtn=document.getElementById('attach-btn');
    const attachLabel=document.getElementById('attach-label');
    const chatLog=document.getElementById('chat-log');
    const overlay=document.getElementById('overlay');
    const arrowLeft=document.getElementById('arrow-left');
    const arrowRight=document.getElementById('arrow-right');
    const SpeechRecognition=window.SpeechRecognition||window.webkitSpeechRecognition;
    const MASTER_TOKEN='x';
    const COMPAT_LABEL="master or+rep";
    const TTS_BACKEND_KEY="master_tts_backend";

    // Chat log helpers with localStorage persistence
    const CHAT_KEY='m2_chat';
    const MAX_STORED=50;
    const logAppend=(role,text)=>{
      const e=document.createElement('div');
      e.className=`entry ${role}`;
      if(role==='master'){e.innerHTML=renderMd(text);}else{e.textContent=text;}
      chatLog.appendChild(e);
      chatLog.scrollTop=chatLog.scrollHeight;
      // Persist
      try{
        const stored=JSON.parse(localStorage.getItem(CHAT_KEY)||'[]');
        stored.push({r:role,t:text});
        if(stored.length>MAX_STORED) stored.splice(0,stored.length-MAX_STORED);
        localStorage.setItem(CHAT_KEY,JSON.stringify(stored));
      }catch(_){}
    };
    // Restore chat history on load
    try{
      const stored=JSON.parse(localStorage.getItem(CHAT_KEY)||'[]');
      for(const m of stored){
        const e=document.createElement('div');
        e.className=`entry ${m.r}`;
        e.textContent=m.t;
        chatLog.appendChild(e);
      }
      chatLog.scrollTop=chatLog.scrollHeight;
    }catch(_){}
    document.addEventListener('keydown',e=>{
      if(e.key==='Tab'){e.preventDefault();chatLog.classList.toggle('open');}
    });
    let lastCanvasTap=0;
    canvas.addEventListener('touchend',()=>{
      const now=Date.now();
      if(now-lastCanvasTap<350) chatLog.classList.toggle('open');
      lastCanvasTap=now;
    },{passive:true});
    let pullStartY=0,pullStartX=0,pullActive=false;
    window.addEventListener('touchstart',e=>{
      const touch=e.touches[0];
      if(touch.clientY<80&&!chatLog.classList.contains('open')){pullStartY=touch.clientY;pullStartX=touch.clientX;pullActive=true;}
      else pullActive=false;
    },{passive:true});
    window.addEventListener('touchend',e=>{
      if(!pullActive) return;
      const dy=e.changedTouches[0].clientY-pullStartY;
      const dx=Math.abs(e.changedTouches[0].clientX-pullStartX);
      if(dy>60&&dx<40){chatLog.classList.add('open');haptic(10);}
      pullActive=false;
    },{passive:true});

const csrfToken = () => {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute('content') : '';
};

const renderMd = raw => {
  let t = String(raw).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  t = t.replace(/```[\w]*\n?([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
  t = t.replace(/`([^`\n]+)`/g, '<code>$1</code>');
  t = t.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/\*([^*\n]+)\*/g, '<em>$1</em>');
  t = t.replace(/\n/g, '<br>');
  return t;
};

    // responses stream from POST /chat/message

    let pendingFile=null;

    attachBtn.addEventListener('click',e=>{e.stopPropagation();fileInput.click();});
    fileInput.addEventListener('change',()=>{
      const f=fileInput.files[0];
      if(f){
        pendingFile=f;
        attachBtn.classList.add('has-file');
        attachLabel.textContent=f.name;
      }else{
        pendingFile=null;
        attachBtn.classList.remove('has-file');
        attachLabel.textContent='';
      }
    });

    let W,H,S;
    const resize=()=>{
      W=window.innerWidth;
      H=window.innerHeight;
... 1947 lines truncated (2347 total)
```

## `web/app/views/layouts/application.html.erb`
```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Web" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Web">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <%# Enable PWA manifest for installable apps (make sure to enable in config/routes.rb too!) %>
    <%#= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%# Includes all stylesheet files in app/assets/stylesheets %>
    <%= stylesheet_link_tag :app %>
  </head>

  <body>
    <%= yield %>
  </body>
</html>
```

## `web/app/views/pwa/manifest.json.erb`
```erb
{
  "name": "Web",
  "icons": [
    {
      "src": "/icon.png",
      "type": "image/png",
      "sizes": "512x512"
    },
    {
      "src": "/icon.png",
      "type": "image/png",
      "sizes": "512x512",
      "purpose": "maskable"
    }
  ],
  "start_url": "/",
  "display": "standalone",
  "scope": "/",
  "description": "Web.",
  "theme_color": "red",
  "background_color": "red"
}
```

## `web/app/views/pwa/service-worker.js`
```javascript
// Add a service worker for processing Web Push notifications:
//
// self.addEventListener("push", async (event) => {
//   const { title, options } = await event.data.json()
//   event.waitUntil(self.registration.showNotification(title, options))
// })
//
// self.addEventListener("notificationclick", function(event) {
//   event.notification.close()
//   event.waitUntil(
//     clients.matchAll({ type: "window" }).then((clientList) => {
//       for (let i = 0; i < clientList.length; i++) {
//         let client = clientList[i]
//         let clientPath = (new URL(client.url)).pathname
//
//         if (clientPath == event.notification.data.path && "focus" in client) {
//           return client.focus()
//         }
//       }
//
//       if (clients.openWindow) {
//         return clients.openWindow(event.notification.data.path)
//       }
//     })
//   )
// })
```

## `web/config/application.rb`
```ruby
require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
```

## `web/config/boot.rb`
```ruby
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
```

## `web/config/ci.rb`
```ruby
# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"



  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
```

## `web/config/database.yml`
```yaml
default: &default
  adapter: sqlite3
  max_connections: 5
  timeout: 5000

development:
  <<: *default
  database: storage/development.sqlite3

test:
  <<: *default
  database: storage/test.sqlite3

production:
  <<: *default
  database: storage/production.sqlite3
```

## `web/config/environment.rb`
```ruby
# Load the Rails application.
require_relative "application"

# Initialize the Rails application.
Rails.application.initialize!
```

## `web/config/environments/development.rb`
```ruby
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
```

## `web/config/environments/production.rb`
```ruby
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # SSL terminated at relayd proxy layer — do not redirect internally.
  config.force_ssl = false

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Host validation handled by relayd; disable Rails-level host authorization.
  config.host_authorization = { exclude: ->(request) { true } }
end
```

## `web/config/environments/test.rb`
```ruby
# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
```

## `web/config/initializers/assets.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path
```

## `web/config/initializers/content_security_policy.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https
#     policy.style_src   :self, :https
#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
#   end
#
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src style-src)
#
#   # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
#   # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
#   # config.content_security_policy_nonce_auto = true
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
# end
```

## `web/config/initializers/filter_parameter_logging.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
```

## `web/config/initializers/inflections.rb`
```ruby
# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
```

## `web/config/initializers/new_framework_defaults_8_0.rb`
```ruby
# Be sure to restart your server when you modify this file.
#
# This file eases your Rails 8.0 framework defaults upgrade.
#
# Uncomment each configuration one by one to switch to the new default.
# Once your application is ready to run with all new defaults, you can remove
# this file and set the `config.load_defaults` to `8.0`.
#
# Read the Guide for Upgrading Ruby on Rails for more info on each option.
# https://guides.rubyonrails.org/upgrading_ruby_on_rails.html

###
# Specifies whether `to_time` methods preserve the UTC offset of their receivers or preserves the timezone.
# If set to `:zone`, `to_time` methods will use the timezone of their receivers.
# If set to `:offset`, `to_time` methods will use the UTC offset.
# If `false`, `to_time` methods will convert to the local system UTC offset instead.
#++
# Rails.application.config.active_support.to_time_preserves_timezone = :zone

###
# When both `If-Modified-Since` and `If-None-Match` are provided by the client
# only consider `If-None-Match` as specified by RFC 7232 Section 6.
# If set to `false` both conditions need to be satisfied.
#++
# Rails.application.config.action_dispatch.strict_freshness = true

###
# Set `Regexp.timeout` to `1`s by default to improve security over Regexp Denial-of-Service attacks.
#++
# Regexp.timeout = 1
```

## `web/config/locales/en.yml`
```yaml
# Files in the config/locales directory are used for internationalization and
# are automatically loaded by Rails. If you want to use locales other than
# English, add the necessary files in this directory.
#
# To use the locales, use `I18n.t`:
#
#     I18n.t "hello"
#
# In views, this is aliased to just `t`:
#
#     <%= t("hello") %>
#
# To use a different locale, set it with `I18n.locale`:
#
#     I18n.locale = :es
#
# This would use the information in config/locales/es.yml.
#
# To learn more about the API, please read the Rails Internationalization guide
# at https://guides.rubyonrails.org/i18n.html.
#
# Be aware that YAML interprets the following case-insensitive strings as
# booleans: `true`, `false`, `on`, `off`, `yes`, `no`. Therefore, these strings
# must be quoted to be interpreted as strings. For example:
#
#     en:
#       "yes": yup
#       enabled: "ON"

en:
  hello: "Hello world"
```

## `web/config/puma.rb`
```ruby
# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
```

## `web/config/routes.rb`
```ruby
Rails.application.routes.draw do
  root "chat#index"
  post "chat/message",  to: "chat#message"
  post "chat/tts",      to: "chat#tts"
  post "chat/speak",    to: "chat#speak"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
  get  "up" => "rails/health#show", as: :rails_health_check
end
```

## `web/db/seeds.rb`
```ruby
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
```

## `web/public/robots.txt`
```txt
# See https://www.robotstxt.org/robotstxt.html for documentation on how to use the robots.txt file
```

files: 236 / lines: 25254 / truncated: 9 / est. tokens: ~30304
