# MASTER Snapshot — data/
Generated: 2026-05-04T10:21:42Z

## data/council.yml
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
  prompt: Assess clarity, friction, error recovery, and overall user outcomes.
```

## data/council_patterns.yml
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
  - '\b(bash)\s+-o\s+(errexit|pipefail|noclobber|noglob)\b' # bash errexit etc.
```

## data/exemplars.yml
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
    why: "Coordinates LLM code generation, isolates side‑effects, clear contract"
```

## data/heartbeat.yml
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

## data/infer_patterns.yml
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

## data/mcp_servers.yml
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

## data/models.yml
```yaml
# Model routing profile — Gemini primary, Mistral/DeepSeek/OpenRouter fallback.

routing:
  enabled: true
  strategy: weighted
  escalation_enabled: true
  escalation_tier: strong
  provider: gemini

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
  gemini_flash: &gemini_flash
    id: gemini-2.5-flash
    <<: *model_defaults
    score: { quality: 0.88, speed: 0.90, cost: 0.95 }
  gemini_pro: &gemini_pro
    id: gemini-2.5-pro
    <<: *model_defaults
    score: { quality: 0.95, speed: 0.70, cost: 0.80 }
  mistral_large: &mistral_large
    id: mistral-large-latest
    <<: *model_defaults
    score: { quality: 0.90, speed: 0.75, cost: 0.70 }
  mistral_small: &mistral_small
    id: mistral-small-latest
    <<: *model_defaults
    score: { quality: 0.78, speed: 0.85, cost: 0.90 }
  deepseek_chat: &deepseek_chat
    id: deepseek-chat
    <<: *model_defaults
    score: { quality: 0.88, speed: 0.70, cost: 0.95 }
  deepseek_coder: &deepseek_coder
    id: deepseek-coder
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.70, cost: 0.95 }
  claude_sonnet: &claude_sonnet
    id: anthropic/claude-sonnet-4-6
    <<: *model_defaults
    score: { quality: 0.95, speed: 0.75, cost: 0.60 }
  nemotron_super: &nemotron_super
    id: nvidia/nemotron-3-super-120b-a12b:free
    <<: *model_defaults
    score: { quality: 0.90, speed: 0.75, cost: 1.0 }
  qwen_coder: &qwen_coder
    id: qwen/qwen3-coder:free
    <<: *model_defaults
    score: { quality: 0.75, speed: 0.65, cost: 1.0 }
  llama_70b: &llama_70b
    id: meta-llama/llama-3.3-70b-instruct:free
    <<: *model_defaults
    score: { quality: 0.78, speed: 0.70, cost: 1.0 }
  hermes_405b: &hermes_405b
    id: nousresearch/hermes-3-llama-3.1-405b:free
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.50, cost: 1.0 }
  gpt_4o: &gpt_4o
    id: openai/gpt-4o
    <<: *model_defaults
    score: { quality: 0.93, speed: 0.80, cost: 0.55 }

models:
  default:
    - *gemini_flash
    - *mistral_large
    - *deepseek_chat
    - *nemotron_super
    - *qwen_coder
  strong:
    - *gemini_pro
    - *mistral_large
    - *claude_sonnet
    - *gpt_4o
    - *gemini_flash
  cheap:
    - *gemini_flash
    - *mistral_small
    - *deepseek_chat
    - *llama_70b
    - *qwen_coder

routes:
  code_generation: default
  refactoring: default
  architecture: strong
  review: default
  explanation: cheap
  exploration: cheap
  fallback_default: cheap

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

continuity:
  enabled: true
  updated_at: "2026-05-01T00:00:00Z"

openrouter:
  free_latest:
    - nvidia/nemotron-3-super-120b-a12b:free
    - qwen/qwen3-coder:free

```

## data/openbsd.yml
```yaml
# openbsd.yml — OpenBSD config validators
# Restored from master.yml v49.75; extended for OpenBSD 7.8

man_base_url: "https://man.openbsd.org"
cache_ttl: 86400

configs:
  pf.conf:
    daemon: pf
    man: pf.conf.5
    required_patterns:
      - "set skip on lo"
    warnings:
      - pattern: "pass all"
        message: "Overly permissive — add interface/protocol guards"

  nsd.conf:
    daemon: nsd
    man: nsd.conf.5
    required_patterns:
      - "server:"
      - "zone:"
    warnings:
      - pattern: "rrl-size"
        absent_message: "Missing RRL config — vulnerable to amplification DDoS"
      - pattern: "hide-version"
        absent_message: "Consider hide-version: yes"

  httpd.conf:
    daemon: httpd
    man: httpd.conf.5
    required_patterns:
      - "server"

  smtpd.conf:
    daemon: smtpd
    man: smtpd.conf.5
    required_patterns:
      - "listen on"
      - "action"
      - "match"
    warnings:
      - pattern: "match from any"
        message: "Open relay risk — restrict to authenticated senders"

  relayd.conf:
    daemon: relayd
    man: relayd.conf.5
    required_patterns:
      - "relay"

  acme-client.conf:
    daemon: acme-client
    man: acme-client.conf.5
    required_patterns:
      - "authority"
      - "domain"

  doas.conf:
    daemon: doas
    man: doas.conf.5
    required_patterns:
      - "permit"
    warnings:
      - pattern: "nopass"
        message: "Allows passwordless privilege escalation"

  sshd_config:
    daemon: sshd
    man: sshd_config.5
    warnings:
      - pattern: "PermitRootLogin yes"
        message: "Security risk — use PermitRootLogin prohibit-password"
      - pattern: "PasswordAuthentication yes"
        message: "Consider key-only auth"

  ntpd.conf:
    daemon: ntpd
    man: ntpd.conf.5
    required_patterns:
      - "server"

  unbound.conf:
    daemon: unbound
    man: unbound.conf.5
    required_patterns:
      - "server:"

```

## data/openbsd_patterns.yml
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
    warnings: []
```

## data/platform.yml
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

windows:
  audio: powershell
  firewall: windows_defender
  http_server: iis
  package_manager: winget
  privilege: runas
  service_manager: sc
  shell: powershell
```

## data/prompts/mode_direct.yml
```yaml
system: |
  Direct mode only.
  No meta‑conversation.
  Answer with minimal words.
  No explanations, apologies, or padding.
  Invoke tools immediately, without preamble.

template: |
  %{message}
```

## data/prompts/mode_react.yml
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
  %<action>s
```

## data/prompts/mode_rewoo.yml
```yaml
system: |
  Generate a concise, numbered plan. Each step must reference at least one evidence slot (e.g., [slot 12]). Conclude with a single, decisive answer.

template: |
  [Mode: ReWOO]
  Task:
  %{message}
```

## data/ruby_style.yml
```yaml
# Ruby, shell, and git style rules enforced by MASTER.
# Scan rules reference these; Personality injects them into every LLM system prompt.

ruby:
  quotes: double  # always double-quoted strings; single only inside regex or '\1' backrefs
  frozen_string: true  # every .rb file must start with # frozen_string_literal: true

  comments:
    max_lines: 1           # class/module/method comments: 1 line or none
    require_why: true      # only add when WHY is non-obvious (hidden constraint, workaround)
    forbidden:
      - what_comments      # never describe what the code does — identifiers do that
      - yard_doc_blocks    # no # Public:, # Returns, # param - style blocks
      - section_separators # no # ----, # ====, # ---- Public API ---- etc.
      - numbered_steps     # no # 1., # 2. inline step comments
      - multi_line_prose   # cut verbosity; one line survives, paragraph does not

  bugs_to_avoid:
    - pattern: "Dir.chdir"
      reason: "process-wide; thread-unsafe in multi-threaded agents"
      fix: "pass -C root to git; expand paths with File.expand_path"

    - pattern: "Prism.parse(src, freeze: true)"
      reason: "freeze: kwarg dropped in Ruby 3.4"
      fix: "Prism.parse(src)"

    - pattern: "next if condition inside flat_map"
      reason: "next if returns nil into flat_map, producing nil entries in output"
      fix: "next [] if condition"

    - pattern: "rescue => e (multi-line bare rescue)"
      reason: "unclear; explicitly name StandardError for clarity"
      fix: "rescue StandardError => e"

    - pattern: "rescue nil (inline rescue returning nil)"
      reason: "inline rescue already catches StandardError; rescue nil is correct idiom"
      note: "do NOT change to rescue StandardError — that returns the class object, not nil"

    - pattern: "@bus&.publish(...) || value"
      reason: "when bus is present, returns bus result (truthy), masking the real value"
      fix: "call @bus&.publish(...) on its own line; return value separately"

    - pattern: "backtick shell commands with interpolation"
      reason: "shell injection risk"
      fix: "Open3.capture2e('cmd', '-flag', arg) with arg arrays"

    - pattern: "system/Open3 with string interpolation"
      reason: "shell injection risk"
      fix: "Open3.capture2e(*%w[cmd -flag], variable) with separate arguments"

    - pattern: "mutate state before publishing event that reads old state"
      reason: "event receives new state instead of previous state"
      fix: "capture prev = current before mutation; use prev in publish/return"

  blank_lines:
    max_consecutive: 1     # no double blank lines anywhere

shell:
  decorations_forbidden:
    - "=== banner ===" # no ASCII section banners
    - "--- separator ---"
    - "*** header ***"
    - "emoji in print/echo output"  # no ✅ ❌ 🚀 etc. in scripts
    - "numbered step comments"      # no # Step 1:, # Phase 2: etc.

  credentials_forbidden: true  # never hardcode passwords/tokens in scripts

  prefer:
    - "pure zsh parameter expansion over external tools (see zsh_patterns.yml)"
    - "Open3.capture2e with arg arrays in Ruby over shell interpolation"
    - "File.expand_path over pwd + concatenation"

git:
  commit_style:
    voice: active           # "Fix bug" not "Fixed bug", "Add feature" not "Added feature"
    format: "type: short summary\n\nBody if needed."
    subject_max: 72
    no_what_if_diff_shows: true  # don't describe what changed if the diff makes it obvious
    separate_concerns: true      # don't mix bug fixes with style changes in one commit

  forbidden:
    - "Dir.chdir in Ruby before git commands"
    - "string-interpolated git commands"
    - "rm -rf in deploy scripts without explicit guard"

```

## data/rules.yml
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
    hedges: ["will", "would", "might", "could", "perhaps", "seems", "appears"]
    endings: ["as a result.", "for this reason.", "thus.", "in effect.", "accordingly."]
    code_preambles: ["# TODO: clarify intent", "# FIXME: review edge cases", "# NOTE: performance considerations", "# HACK: temporary workaround", "# REVIEW: assess after refactor"]
  inverted_pyramid:
    - "Lead with the outcome."
    - "Provide key evidence next."
    - "Add implementation detail last."

  preserve:
    boot_message: "5-line dmesg style, never collapse to one line"
    diagnostic_output: "structured multi-line output is intentional, never compress to abbreviations"
    help_text: "include command name, description, and at least one example"
    spinner_feedback: "show elapsed time and status, do not remove progress indicators"
    refinement_scope:
      streamline: "remove redundancy, not information"
      polish: "refine wording, not delete output"
      minimize: "applies to prompt tokens, not diagnostic output"

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
    - UniversalRule
  standard: &standard
    - FrozenStringRule
    - BareRescueRule
    - UniversalRule
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
    - ArityRule
    - TellDontAskRule
    - ThresholdDriftRule
    - RubocopRule
    - ReekRule
  deep: &deep
    - AdversarialRule
    - ConceptualRule
    - DuplicateCodeRule
    - FrozenStringRule
    - BareRescueRule
    - UniversalRule
    - ExplicitRule
    - ImmutableRule
    - CqsRule
    - SelfExplainingRule
    - LongMethodRule
    - GodClassRule
    - SrpRule
    - PolaRule
    - NielsenRule
    - ArityRule
    - TellDontAskRule
    - ThresholdDriftRule
    - OpportunityRule
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

    - id: PROPERTY_BASED_TESTING
      name: "Test properties and invariants, not just examples"
      tier: verification
      severity: info
      autofix: false
      detect_conceptual: "Are tests only checking specific examples instead of universal properties? Is QA only sampling instead of testing invariants?"
      fix: "Define properties that must always hold. Generate many inputs. Verify the property survives all."

  file:

    - id: GUARD_EXPENSIVE
      name: "Check preconditions before costly work"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this file perform expensive operations (API calls, disk IO) without checking preconditions?"
      fix: "Guard clause before costly work. Estimate cost. Confirm if destructive."

    - id: SMALL_FILES
      name: "Files under 300 lines"
      tier: clean_code
      severity: warning
      autofix: false
      detect_lexical: null
      detect_conceptual: "Does this file exceed 300 lines?"
      fix: "Split at module boundaries."

    - id: CONSISTENT_FILE_STRUCTURE
      name: "Consistent file structure order"
      tier: clarity
      severity: info
      autofix: false
      detect_conceptual: "Does this file follow the order: magic comments, requires, module, constants, public, private, end?"
      fix: "Reorder to match convention."
      languages: [ruby]

    - id: FROZEN_STRING_LITERAL
      name: "frozen_string_literal magic comment required"
      tier: core
      severity: warning
      autofix: true
      detect_lexical: "\\A(?!# frozen_string_literal)"
      fix: "Add '# frozen_string_literal: true' as first line."
      languages: [ruby]

    - id: SINGLE_PRIVATE_SECTION
      name: "One private keyword at bottom"
      tier: design
      severity: info
      autofix: false
      detect_lexical: "private\\s+:\\w+"
      fix: "Use a single 'private' keyword with methods below it."
      languages: [ruby]

    - id: STRICT_MODE_ZSH
      name: "set -euo pipefail at script top"
      tier: core
      severity: error
      autofix: true
      detect_lexical: "^#!/.*(?:ba|z)sh\\n(?!set -)"
      fix: "Add 'set -euo pipefail' after shebang."
      languages: [zsh]

    - id: HTML_LANG
      name: "lang attribute on <html>"
      tier: accessibility
      severity: error
      autofix: true
      detect_lexical: "<html(?!\\s+[^>]*lang=)"
      fix: "Add lang=\"en\" or appropriate locale."
      languages: [html]

    - id: SEMANTIC_ELEMENTS
      name: "Use semantic HTML5 elements"
      tier: accessibility
      severity: warning
      autofix: true
      detect_lexical: "<div\\s+class=\"(header|footer|nav|main|sidebar|article|section)\""
      fix: "Use <header>, <footer>, <nav>, <main>, <aside>, <article>, <section>."
      languages: [html]

    - id: MOBILE_FIRST
      name: "Mobile-first media queries"
      tier: design
      severity: warning
      autofix: false
      detect_lexical: "@media\\s*\\(\\s*max-width"
      fix: "Use min-width (mobile-first, progressive enhancement)."
      languages: [css]

    - id: NO_IMPORT_SCSS
      name: "Replace @import with @use/@forward"
      tier: design
      severity: warning
      autofix: false
      detect_lexical: "@import\\s+[\"']"
      fix: "@import is deprecated. Use @use/@forward."
      languages: [scss]

    - id: NO_IMPORTANT
      name: "No !important"
      tier: design
      severity: warning
      autofix: false
      detect_lexical: "!\\s*important"
      fix: "Restructure selectors to avoid specificity bankruptcy."
      languages: [css]

    - id: SQUINT_TEST
      name: "Structure evident at a glance"
      tier: aesthetic
      severity: info
      autofix: true
      detect_lexical: "\\n{4,}"
      detect_conceptual: "Does this file have dense blocks with no visual breaks, or ragged indentation?"
      fix: "One blank line between sections, never more than two consecutive."

    - id: WHITESPACE_PUNCTUATION
      name: "Whitespace as layout tool"
      tier: aesthetic
      severity: info
      autofix: true
      detect_lexical: "\\n{4,}"
      fix: "One blank line between sections, never more than two."

    - id: NO_MULTIPLE_LANGUAGES
      name: "One medium per artifact"
      tier: clean_code
      severity: warning
      autofix: false
      detect_lexical: "<%|<script|<style|SQL|HEREDOC"
      detect_conceptual: "Does this file embed multiple languages or notations? Does this document mix incompatible frameworks?"
      fix: "One language per layer. Separate into distinct files or clearly demarcated sections."

    - id: ARTIFICIAL_COUPLING
      name: "Things that do not depend on each other must not be grouped together"
      tier: clean_code
      severity: warning
      autofix: false
      detect_conceptual: "Are unrelated concepts coupled by proximity or shared container? In a filing, are unrelated claims bundled into one count?"
      fix: "Separate into independent units. Each removable without affecting others."

  unit:

    - id: SIMPLEST_WORKS
      name: "Fewest moving parts that solve the problem"
      tier: kernel
      severity: error
      autofix: false
      detect_conceptual: "Does this unit introduce unnecessary complexity?"
      fix: "Delete abstractions until it hurts. KISS."

    - id: FAIL_VISIBLY
      name: "Surface errors immediately"
      tier: kernel
      severity: error
      autofix: false
      detect_lexical: "rescue\\s*$|rescue\\s+Exception"
      detect_conceptual: "Does this code swallow exceptions or fail silently?"
      fix: "Catch specific errors, log context, re-raise or return Result."

    - id: BE_CONCISE
      name: "Avoid unnecessary words, tokens, or lines"
      tier: kernel
      severity: warning
      autofix: true
      detect_conceptual: "Does this unit contain unnecessary verbosity?"
      fix: "Omit needless words. Omit needless code."

    - id: SRP
      name: "Single Responsibility"
      tier: solid
      severity: warning
      autofix: false
      detect_conceptual: "Does this class have more than one reason to change?"
      fix: "Extract concerns into focused classes."

    - id: OPEN_CLOSED
      name: "Open for extension, closed for modification"
      tier: solid
      severity: info
      autofix: false
      detect_conceptual: "Must you modify core code to extend this?"
      fix: "Strategy pattern, dependency injection, hooks."

    - id: LISKOV
      name: "Subtypes must substitute for base types"
      tier: solid
      severity: info
      autofix: false
      detect_conceptual: "Does a subclass break the parent's contract?"
      fix: "Use composition if substitutability fails."

    - id: INTERFACE_SEGREGATION
      name: "No fat interfaces"
      tier: solid
      severity: info
      autofix: false
      detect_conceptual: "Does this interface force implementors to stub unused methods?"
      fix: "Split into smaller role-based interfaces."

    - id: DEPENDENCY_INVERSION
      name: "Depend on abstractions, not concretions"
      tier: solid
      severity: warning
      autofix: false
      detect_conceptual: "Does this class directly instantiate its dependencies?"
      fix: "Inject dependencies through constructor."

    - id: ONE_JOB
      name: "Each module has one clear reason to change"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Does this module handle unrelated responsibilities?"
      fix: "Split into focused modules."

    - id: NO_SURPRISES
      name: "Predictable over clever"
      tier: philosophy
      severity: warning
      autofix: false
      detect_conceptual: "Would a reader be surprised by this behavior?"
      fix: "Rename or split to match expectations."

    - id: COMPOSABLE
      name: "Small pieces that combine cleanly"
      tier: philosophy
      severity: info
      autofix: false
      detect_conceptual: "Is this monolithic where it could be composed from smaller parts?"
      fix: "Build small pieces that combine cleanly."

    - id: CQS
      name: "Separate queries from state mutations"
      tier: design
      severity: warning
      autofix: true
      detect_lexical: null
      detect_conceptual: "Does a method both return data and change state?"
      fix: "Split: query() + command(). Never mix."
      languages: [ruby]

    - id: LAW_OF_DEMETER
      name: "Only talk to immediate friends"
      tier: design
      severity: warning
      autofix: true
      detect_lexical: "\\w+\\.\\w+\\.\\w+\\.\\w+"
      detect_conceptual: "Does this code reach through multiple objects?"
      fix: "Add delegate method. Talk only to direct collaborators."

    - id: COMPOSITION_OVER_INHERITANCE
      name: "Favor has_a over is_a"
      tier: design
      severity: info
      autofix: false
      detect_conceptual: "Is inheritance used for code reuse rather than substitutability?"
      fix: "Use composition. Mixins for shared behavior."

    - id: SMALL_FUNCTIONS
      name: "Methods under 10 lines ideal, max 20"
      tier: clean_code
      severity: warning
      autofix: true
      detect_conceptual: "Does this method exceed 20 lines?"
      fix: "Extract: validate(), calculate(), persist()."

    - id: FEW_ARGUMENTS
      name: "Ideal is zero to two arguments"
      tier: clean_code
      severity: warning
      autofix: true
      detect_lexical: "def \\w+\\([^)]*,[^:)]+,[^:)]+,[^:)]+\\)"
      fix: "Group into keyword arguments or parameter object."
      languages: [ruby]

    - id: ONE_ABSTRACTION_LEVEL
      name: "Each function at one abstraction level"
      tier: clean_code
      severity: info
      autofix: false
      detect_conceptual: "Does this function mix high-level policy with low-level detail?"
      fix: "Extract low-level detail into helper methods."

    - id: STEPDOWN
      name: "Functions call only one level below"
      tier: clean_code
      severity: info
      autofix: false
      detect_conceptual: "Does this code read top-down like a newspaper?"
      fix: "Public methods at top, private helpers below."

    - id: BOUNDARY_ISOLATION
      name: "Wrap third-party code at the edge"
      tier: clean_code
      severity: warning
      autofix: false
      detect_conceptual: "Does third-party API surface leak into core logic?"
      fix: "Wrap in adapter. Keep it from leaking."

    - id: NO_MAGIC
      name: "No unexplained constants or flags"
      tier: clean_code
      severity: warning
      autofix: true
      detect_conceptual: "Are there unexplained numeric literals or boolean flags?"
      fix: "Extract to named constants."

    - id: FAIL_FAST
      name: "Report errors at detection point"
      tier: reliability
      severity: warning
      autofix: true
      detect_conceptual: "Does this code defer error reporting instead of failing immediately?"
      fix: "Raise or return Result.err at point of detection."

    - id: IDEMPOTENT
      name: "Same operation, same result"
      tier: reliability
      severity: info
      autofix: false
      detect_conceptual: "Would repeating this operation produce different results?"
      fix: "Use set_value() instead of increment(). Add idempotency keys."

    - id: DEFENSIVE_INPUT
      name: "Never trust input at system boundaries"
      tier: reliability
      severity: warning
      autofix: true
      detect_conceptual: "Is external input used without validation?"
      fix: "Validate at boundaries. Whitelist, sanitize."

    - id: GRACEFUL_DEGRADATION
      name: "Partial functionality beats total failure"
      tier: reliability
      severity: warning
      autofix: false
      detect_conceptual: "Does one failure crash everything?"
      fix: "Circuit breakers, timeouts, fallback to stale data."

    - id: NO_SIDE_EFFECTS
      name: "Functions should not change state they do not own"
      tier: functional
      severity: info
      autofix: false
      detect_conceptual: "Does this function modify external state silently?"
      fix: "Make side effects explicit. Return values instead of mutating."

    - id: IMMUTABLE
      name: "Default to immutable data"
      tier: functional
      severity: info
      autofix: true
      detect_lexical: "^\\s*[A-Z][A-Z_]*\\s*=\\s*[\\[{](?!.*\\.freeze)"
      detect_conceptual: "Are mutable objects shared across threads or scopes?"
      fix: "Freeze collections. Use frozen/const by default."
      languages: [ruby]

    - id: PURE_FUNCTIONS
      name: "Same input, same output"
      tier: functional
      severity: info
      autofix: true
      detect_conceptual: "Does this function depend on hidden state?"
      fix: "Pass all dependencies as parameters."

    - id: PRIMITIVE_OBSESSION
      name: "Replace repeated primitives with value objects"
      tier: refactoring
      severity: info
      autofix: false
      detect_conceptual: "Are primitives used where a value object would be clearer?"
      fix: "Create a value object."

    - id: MESSAGE_CHAIN
      name: "Avoid a.b.c.d chains"
      tier: refactoring
      severity: warning
      autofix: true
      detect_lexical: "\\w+\\.\\w+\\.\\w+\\.\\w+"
      fix: "Talk only to immediate collaborators."

    - id: MIDDLE_MAN
      name: "Eliminate pure-delegation classes"
      tier: refactoring
      severity: info
      autofix: false
      detect_conceptual: "Does this class delegate most methods to another?"
      fix: "Remove middle man. Talk directly."

    - id: LAZY_CLASS
      name: "Remove classes too small to justify existence"
      tier: refactoring
      severity: info
      autofix: false
      detect_conceptual: "Is this class doing too little to earn its existence?"
      fix: "Inline into caller."

    - id: DIVERGENT_CHANGE
      name: "Split classes changed for unrelated reasons"
      tier: refactoring
      severity: warning
      autofix: false
      detect_conceptual: "Is this class modified for multiple unrelated reasons?"
      fix: "Split by axis of change."

    - id: SPECULATIVE_GENERALITY
      name: "Remove code for hypothetical needs"
      tier: refactoring
      severity: info
      autofix: true
      detect_conceptual: "Is this code written for a future requirement that does not exist yet?"
      fix: "Delete it. YAGNI."

    - id: INAPPROPRIATE_INTIMACY
      name: "Do not access another class's private data"
      tier: refactoring
      severity: warning
      autofix: false
      detect_conceptual: "Does this code access internals of another class?"
      fix: "Use public interface. Enforce boundaries."

    - id: SYSTEM_STATUS
      name: "Keep users informed of progress"
      tier: ux
      severity: info
      autofix: true
      detect_conceptual: "Does this long operation provide feedback to the user?"
      fix: "Spinner, progress bar, status message."

    - id: USER_CONTROL
      name: "Support undo and emergency exits"
      tier: ux
      severity: info
      autofix: false
      detect_conceptual: "Can the user undo or cancel this operation?"
      fix: "Add undo support. Confirm destructive actions."

    - id: ERROR_RECOVERY
      name: "Error messages must name the problem and suggest a fix"
      tier: ux
      severity: warning
      autofix: false
      detect_conceptual: "Do error messages explain what went wrong and what to do?"
      fix: "Name the problem. Suggest a fix. Show context."

    - id: AESTHETIC_MINIMALISM
      name: "Show only relevant information"
      tier: ux
      severity: info
      autofix: false
      detect_conceptual: "Does this output contain information that does not earn its place?"
      fix: "Every element must earn its place."

    - id: CONSISTENCY
      name: "Same term means same thing everywhere"
      tier: ux
      severity: warning
      autofix: false
      detect_conceptual: "Are the same concepts named differently in different places?"
      fix: "Follow conventions. One name per concept."

    - id: COST_TRANSPARENCY
      name: "Show LLM costs in real-time"
      tier: llm
      severity: warning
      autofix: true
      detect_conceptual: "Are API calls made without showing token count or cost?"
      fix: "Display [$0.0023, 847 tokens] after each call."

    - id: CACHE_LLM
      name: "Cache deterministic LLM responses"
      tier: llm
      severity: info
      autofix: true
      detect_conceptual: "Is the same prompt sent multiple times without caching?"
      fix: "Hash prompt, cache response with bounded TTL."

    - id: GUARD_EXPENSIVE_OPS
      name: "Confirm before costly or destructive operations"
      tier: safety
      severity: error
      autofix: true
      detect_conceptual: "Does this execute an expensive or destructive operation without confirmation?"
      fix: "Cost estimate before execution. Require opt-in for danger."

    - id: NO_FLAG_ARGUMENTS
      name: "A flag that selects behavior means two things hiding as one"
      tier: clean_code
      severity: warning
      autofix: false
      detect_lexical: "def \\w+\\([^)]*\\btrue\\b|def \\w+\\([^)]*\\bfalse\\b"
      detect_conceptual: "Does a boolean cause this unit to do two different things? In a contract, does one condition branch into contradictory obligations?"
      fix: "Split into two distinct units. Each does one thing."

    - id: NO_OUTPUT_ARGUMENTS
      name: "Return results, never secretly modify what was passed in"
      tier: clean_code
      severity: warning
      autofix: false
      detect_conceptual: "Does this modify its arguments instead of returning a result? Does this clause silently alter a definition from a prior section?"
      fix: "Return the result. Leave inputs untouched."

    - id: NO_SELECTOR_ARGUMENTS
      name: "Arguments that switch behavior indicate hidden multiplicity"
      tier: clean_code
      severity: warning
      autofix: false
      detect_conceptual: "Is an argument used as a switch to select between behaviors? Does a field mean different things in different contexts?"
      fix: "Separate functions, separate types, separate document sections."

    - id: DESIGN_BY_CONTRACT
      name: "State what you expect, what you promise, what must remain true"
      tier: reliability
      severity: info
      autofix: false
      detect_conceptual: "Are preconditions, postconditions, and invariants left implicit? Does this API lack documentation of valid inputs and guaranteed outputs?"
      fix: "Make contracts explicit. Preconditions, postconditions, invariants."

    - id: CRASH_EARLY
      name: "A dead process does less damage than a corrupted one"
      tier: reliability
      severity: warning
      autofix: false
      detect_conceptual: "Does this limp along in a broken state instead of stopping cleanly? Does this continue after contraindication signals?"
      fix: "Stop when invariants break. A clean crash is recoverable. Corruption is not."

    - id: DEFINE_ERRORS_OUT
      name: "Design so error conditions cannot arise"
      tier: design
      severity: info
      autofix: false
      detect_conceptual: "Is this handling errors that could be eliminated by redesigning the interface? Does this validation reject input that better design would prevent?"
      fix: "Redesign so the error cannot occur."

    - id: SURFACE_AREA
      name: "Minimize the boundary between inside and outside"
      tier: design
      severity: warning
      autofix: false
      detect_conceptual: "Is the public interface larger than necessary? Does this contract have more exceptions than rules?"
      fix: "Fewer public methods. Fewer clauses. Fewer points of contact mean fewer points of failure."

    - id: PROGRESSIVE_DISCLOSURE
      name: "Reveal complexity only as needed"
      tier: ux
      severity: info
      autofix: false
      detect_conceptual: "Does this present all complexity at once? Does this front-load definitions before stating obligations?"
      fix: "Lead with the simple case. Reveal depth on demand."

    - id: FEEDBACK_LOOPS
      name: "Every action must produce observable feedback"
      tier: ux
      severity: warning
      autofix: false
      detect_conceptual: "Does this perform work without reporting progress? Does this protocol lack checkpoints?"
      fix: "Close the loop. Every action produces feedback. Every milestone gets measured."

    - id: DATA_CLASS
      name: "Data without behavior is a missed abstraction"
      tier: refactoring
      severity: info
      autofix: false
      detect_conceptual: "Does this hold data but contain no behavior? Is logic scattered across other modules? Is this a spreadsheet of raw numbers with formulas elsewhere?"
      fix: "Push behavior into the data. Methods belong with the data they operate on."

    - id: PARALLEL_INHERITANCE
      name: "Two hierarchies that must change in lockstep"
      tier: refactoring
      severity: warning
      autofix: false
      detect_conceptual: "Does adding a type in one hierarchy require adding one in another? Does a new product line require changes in both catalog and billing?"
      fix: "Merge the hierarchies or use composition."

    - id: REFUSED_BEQUEST
      name: "Inheriting what you do not use"
      tier: refactoring
      severity: info
      autofix: false
      detect_conceptual: "Does this variant ignore most of what it inherits? Does this addendum negate most of the base agreement?"
      fix: "Use composition instead of inheritance."

  line:

    - id: EXPLICIT
      name: "Explicit contracts over implicit coupling"
      tier: kernel
      severity: warning
      autofix: true
      detect_conceptual: "Is this line relying on implicit behavior?"
      fix: "Make it explicit."

    - id: SELF_EXPLAINING
      name: "Names reduce need for comments"
      tier: kernel
      severity: info
      autofix: true
      detect_conceptual: "Does this name clearly reveal intent?"
      fix: "Rename to reveal intent."

    - id: GUARD_CLAUSE
      name: "Favor guard clauses over nested conditionals"
      tier: clean_code
      severity: info
      autofix: false
      detect_lexical: "^\\s*def \\w+.*\\n\\s*if .+\\n(?:.*\\n)*?\\s*else\\n(?:.*\\n)*?\\s*end\\s*$"
      fix: "Flatten to: return ... unless condition"
      languages: [ruby]

    - id: SAFE_NAVIGATION
      name: "Use &. consistently"
      tier: style
      severity: warning
      autofix: true
      detect_lexical: "(\\w+)\\s*&&\\s*\\1\\.\\w+"
      fix: "Rewrite to x&.foo&.bar"
      languages: [ruby]

    - id: EACH_WITH_OBJECT
      name: "Prefer each_with_object over inject for hash building"
      tier: style
      severity: warning
      autofix: false
      detect_lexical: "\\.(inject|reduce)\\(\\s*\\{\\s*\\}\\s*\\)"
      fix: "Use .each_with_object({}) — eliminates mutable-return footgun."
      languages: [ruby]

    - id: KEYWORD_ARGS
      name: "Keyword arguments for 3+ parameters"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "def \\w+\\([^)]*,\\s*[^:)]+,\\s*[^:)]+,\\s*[^:)]+\\)"
      fix: "Use keyword arguments for clarity and safety."
      languages: [ruby]

    - id: KERNEL_COERCION
      name: "Use Array(), Hash(), String() coercions"
      tier: style
      severity: info
      autofix: true
      detect_lexical: "(\\w+)\\s*\\.\\s*nil\\?\\s*\\?\\s*\\[\\]\\s*:\\s*\\1|(\\w+)\\s*\\|\\|\\s*\\[\\]"
      fix: "Use Array(x) instead of x.nil? ? [] : x"
      languages: [ruby]

    - id: PERCENT_LITERAL
      name: "Use %i[] and %w[] for symbol/string arrays"
      tier: style
      severity: info
      autofix: true
      detect_lexical: "\\[:[a-z_]+,\\s*:[a-z_]+,\\s*:[a-z_]+"
      fix: "Use %i[a b c] for symbol arrays."
      languages: [ruby]

    - id: HASH_FETCH
      name: "Prefer Hash#fetch over [] with ||"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "\\w+\\[:\\w+\\]\\s*\\|\\|"
      fix: "Use hash.fetch(:key, default) for nil-vs-false safety."
      languages: [ruby]

    - id: TRANSFORM_KEYS
      name: "Use transform_keys/transform_values"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "\\.each_with_object\\(\\{\\}\\)\\s*\\{\\s*\\|\\(k,\\s*v\\),\\s*h\\|"
      fix: "Use .transform_values { |v| ... }"
      languages: [ruby]

    - id: USE_THEN
      name: "Use .then for pipeline transforms"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "(\\w+)\\s*=\\s*\\w+\\(.*\\)\\n\\s*\\w+\\(\\1\\)"
      fix: "Chain with .then { |r| next_step(r) }"
      languages: [ruby]

    - id: RESCUE_ON_DEF
      name: "Move begin/rescue to def line"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "^\\s*def \\w+.*\\n\\s*begin\\n(?:.*\\n)*?\\s*rescue"
      fix: "Put rescue directly on the def block."
      languages: [ruby]

    - id: BARE_RESCUE
      name: "Never rescue bare or rescue Exception"
      tier: safety
      severity: error
      autofix: false
      detect_lexical: "rescue\\s*$|rescue\\s+Exception"
      fix: "Rescue StandardError or a specific class."
      languages: [ruby]

    - id: N_PLUS_ONE
      name: "Detect N+1 queries"
      tier: performance
      severity: warning
      autofix: false
      detect_lexical: "\\.(each|map|collect)\\s*(do|\\{).*\\.\\w+\\.\\w+"
      fix: "Add .includes(:association)."
      languages: [rails]

    - id: FIND_EACH
      name: "Use find_each for batch processing"
      tier: performance
      severity: warning
      autofix: false
      detect_lexical: "\\.(all\\.each|where\\(.*\\)\\.each)\\b"
      fix: "Use .find_each(batch_size: 1000)."
      languages: [rails]

    - id: NO_UPDATE_ATTRIBUTE
      name: "Replace update_attribute with update!"
      tier: safety
      severity: error
      autofix: true
      detect_lexical: "\\.update_attribute\\("
      fix: "update_attribute skips validations. Use update!"
      languages: [rails]

    - id: PLUCK_OVER_MAP
      name: "Prefer pluck over map for single columns"
      tier: performance
      severity: info
      autofix: false
      detect_lexical: "\\.\\w+\\.map\\(&:\\w+\\)"
      fix: "Use .pluck(:column) to avoid AR object instantiation."
      languages: [rails]

    - id: CONST_BY_DEFAULT
      name: "Use const unless reassigned"
      tier: style
      severity: warning
      autofix: false
      detect_lexical: "\\blet\\s+(\\w+)\\s*="
      fix: "Use const unless the variable is reassigned."
      languages: [javascript]

    - id: OPTIONAL_CHAINING
      name: "Use ?. over && chains"
      tier: style
      severity: warning
      autofix: true
      detect_lexical: "(\\w+)\\s*&&\\s*\\1\\.\\w+"
      fix: "Rewrite to obj?.foo?.bar"
      languages: [javascript]

    - id: NULLISH_COALESCING
      name: "Use ?? over || for defaults"
      tier: style
      severity: info
      autofix: false
      detect_lexical: "(\\w+)\\s*\\|\\|\\s*\\w+"
      fix: "Use ?? when 0 or '' are valid values."
      languages: [javascript]

    - id: TEMPLATE_LITERALS
      name: "Use template literals over concatenation"
      tier: style
      severity: warning
      autofix: true
      detect_lexical: "[\"']\\s*\\+\\s*\\w+\\s*\\+\\s*[\"']"
      fix: "Use `Hello ${name}!` template literals."
      languages: [javascript]

    - id: ASYNC_AWAIT
      name: "Prefer async/await over .then chains"
      tier: style
      severity: warning
      autofix: false
      detect_lexical: "\\.then\\(.*\\.then\\(.*\\.then\\("
      fix: "Use async/await for readability."
      languages: [javascript]

    - id: FOR_OF
      name: "Use for...of instead of for...in for arrays"
      tier: safety
      severity: error
      autofix: true
      detect_lexical: "for\\s*\\(\\s*(const|let|var)\\s+\\w+\\s+in\\s+"
      fix: "for...in iterates prototype properties. Use for...of."
      languages: [javascript]

    - id: QUOTE_VARIABLES
      name: "Always quote $variables"
      tier: safety
      severity: error
      autofix: true
      detect_lexical: "(?<![\"'\\\\])\\$\\w+(?![\"'])"
      fix: "Use \"$VAR\" to prevent word splitting."
      languages: [zsh]

    - id: DOUBLE_BRACKET
      name: "Use [[ ]] over [ ]"
      tier: safety
      severity: warning
      autofix: true
      detect_lexical: "(?<!\\[)\\[\\s+[^[]"
      fix: "Use [[ ... ]] for safe conditionals."
      languages: [zsh]

    - id: DOLLAR_PAREN
      name: "Replace backticks with $(command)"
      tier: style
      severity: warning
      autofix: true
      detect_lexical: "`[^`]+`"
      fix: "Use $(command) — nestable and readable."
      languages: [zsh]

    - id: IMG_ALT
      name: "Require alt on every <img>"
      tier: accessibility
      severity: error
      autofix: false
      detect_lexical: "<img\\s+(?![^>]*alt=)"
      fix: "Add alt= attribute."
      languages: [html]

    - id: BUTTON_OVER_ANCHOR
      name: "Use <button> for actions, not <a href=\"#\">"
      tier: accessibility
      severity: warning
      autofix: false
      detect_lexical: "<a\\s+href=[\"']#[\"']"
      fix: "Use <button>. Accessible by default."
      languages: [html]

    - id: ARIA_INTERACTIVE
      name: "ARIA on non-semantic interactive elements"
      tier: accessibility
      severity: warning
      autofix: false
      detect_lexical: "<(div|span)\\s+[^>]*onclick"
      fix: "Add role= and tabindex= for accessibility."
      languages: [html]

    - id: LAZY_IMAGES
      name: "loading=\"lazy\" on below-fold images"
      tier: performance
      severity: info
      autofix: true
      detect_lexical: "<img\\s+(?![^>]*loading=)"
      fix: "Add loading=\"lazy\"."
      languages: [html]

    - id: NO_INLINE_STYLES
      name: "Replace inline styles with classes"
      tier: design
      severity: warning
      autofix: false
      detect_lexical: "\\bstyle=\"[^\"]*\""
      fix: "Extract to CSS class."
      languages: [html]

    - id: LOGICAL_PROPERTIES
      name: "Prefer logical properties for RTL support"
      tier: design
      severity: info
      autofix: true
      detect_lexical: "(margin|padding)-(left|right):"
      fix: "Use margin-inline-start/end, padding-inline-start/end."
      languages: [css]

    - id: CLAMP_TYPOGRAPHY
      name: "Use clamp() for fluid typography"
      tier: design
      severity: info
      autofix: false
      detect_lexical: "@media.*\\{[^}]*font-size:"
      fix: "Use font-size: clamp(1rem, 2.5vw, 1.5rem)."
      languages: [css]

    - id: MEANINGFUL_NAMES
      name: "Names reveal intent"
      tier: clarity
      severity: info
      autofix: true
      detect_lexical: "\\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\\b\\s*="
      fix: "Use domain-specific names. user_profile, error_message."

    - id: WHY_NOT_WHAT
      name: "Comments explain why, not what"
      tier: clarity
      severity: info
      autofix: false
      detect_lexical: "#\\s*(increment|set|get|update|return|initialize|create|add)\\s+\\w+"
      fix: "Comments should explain intent, not restate the code."

    - id: DEAD_CODE
      name: "Eliminate unreachable code"
      tier: clean_code
      severity: warning
      autofix: true
      detect_lexical: "(return|exit|raise|throw)\\s+.*\\n\\s*\\w+"
      fix: "Remove code after return/exit/raise/throw."

    - id: TRAILING_COMMAS
      name: "Trailing commas in multi-line collections"
      tier: style
      severity: info
      autofix: true
      detect_conceptual: "Does this multi-line collection lack a trailing comma?"
      fix: "Add trailing comma so additions produce one-line diffs."

    - id: TYPOGRAPHIC_EXCELLENCE
      name: "Typographic excellence in user-facing text"
      tier: aesthetic
      severity: info
      autofix: true
      detect_lexical: "[\"']\\.\\.\\.[\"']|[\"']--[\"']"
      fix: "Use ellipsis, em dash, curly quotes in UI strings."

    - id: SILENCE_ON_SUCCESS
      name: "Successful operations produce minimal output"
      tier: interface
      severity: info
      autofix: false
      detect_conceptual: "Does this output say more than necessary for a successful operation?"
      fix: "Default to silence on success. One line for routine completions."

    - id: TYPOGRAPHY_DISCIPLINE
      name: "Hierarchy via weight and brightness, not decoration"
      tier: interface
      severity: info
      autofix: true
      detect_lexical: "[-=]{3,}|[╭╮╰╯│─]"
      fix: "No ASCII separators. No box drawing. Whitespace is the layout tool."

    - id: PRECOMPUTE_MATH
      name: "Precompute expensive math"
      tier: performance
      severity: info
      autofix: true
      detect_conceptual: "Are trig functions or noise lookups called per-frame per-object?"
      fix: "Precompute tables. Cache distance. Use squared distance comparison."

    - id: AUDIO_SMOOTHING
      name: "Smooth audio-reactive visuals"
      tier: aesthetic
      severity: info
      autofix: false
      detect_conceptual: "Do visual elements jump erratically with raw audio data?"
      fix: "Exponential smoothing. Separate decay rates. Attack-decay envelope."

    - id: GRACEFUL_LOAD
      name: "Degrade quality under load, do not crash"
      tier: performance
      severity: warning
      autofix: true
      detect_conceptual: "Does this run at full quality until it crashes instead of scaling down?"
      fix: "EWMA frame timing. Dynamic resolution scaling. Emergency brake."

    - id: ANALOG_WARMTH
      name: "Perfect is sterile"
      tier: aesthetic
      severity: info
      autofix: true
      detect_conceptual: "Is generated imagery clinically perfect with zero texture?"
      fix: "Film grain. Vintage lens softness. Subtle color cast."

    - id: DOMAIN_LANGUAGE
      name: "Speak in the vocabulary of the problem, not the implementation"
      tier: clarity
      severity: warning
      autofix: false
      detect_conceptual: "Does this code use generic programming terms (manager, handler, processor, data) instead of domain terms (patient, invoice, genome, verdict)? Does this legal document use lay terms where precise legal terms exist? Does this medical report use colloquial language instead of standard nomenclature?"
      fix: "Use the ubiquitous language of the domain. Every domain has precise terms — use them."

    - id: LOAD_BEARING_NAMES
      name: "Names carry structural weight — choose them to bear it"
      tier: clarity
      severity: warning
      autofix: false
      detect_conceptual: "Are names vague, generic, or misleading? Does 'data' mean input, output, or both? Does 'process' mean validate, transform, or persist? Does 'miscellaneous' appear as a category? In law, are terms used loosely that have precise legal meaning? In medicine, is a diagnosis vague where a specific code exists?"
      fix: "Names are load-bearing walls. They define how people think about the system. Choose names that carry the full weight of their meaning."

    - id: ERROR_CONTEXT
      name: "Every error must carry enough context to locate and understand its origin"
      tier: reliability
      severity: warning
      autofix: false
      detect_conceptual: "Does this error message lack context about where and why it occurred? Does this rejection letter fail to state which requirement was not met? Does this lab result omit which sample or protocol produced the anomaly?"
      fix: "Wrap low-level errors with domain context. State what was attempted, what failed, and what to do next."

    - id: COMMENTS_AS_DEODORANT
      name: "Explanations that mask bad structure instead of fixing it"
      tier: clean_code
      severity: warning
      autofix: false
      detect_conceptual: "Is this comment explaining what bad code does instead of rewriting the code to be self-evident? In prose, is a footnote compensating for an unclear sentence? In a contract, is a definition section papering over ambiguous clauses?"
      fix: "Rewrite the artifact so explanation is unnecessary. If it needs a comment, it needs a rewrite."

```

## data/soul.yml
```yaml
# soul.yml — machine-enforced constitutional schema
# Human-readable narrative lives in SOUL.md.
# ABSOLUTE sections require constitutional override to amend.
# Negotiable sections: soul propose -> soul approve -> bump version.

version: "2.1.0"
persona: dark_malay
voice: ms-MY-OsmanNeural
language:
  primary: english
  secondary: norwegian
  dialect: bokmal

absolute:
  golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
  anti_simulation:
    forbidden: [will, would, could, might]
    require_evidence:
      file_read: show content with SHA-256
      modification: show unified diff
      completion: show command output
  protection_tiers:
    ABSOLUTE: abort pipeline
    PROTECTED: emit warning continue
    NEGOTIABLE: allow if explicitly permitted
    FLEXIBLE: negotiate at runtime

negotiable:
  style: openbsd_dmesg
  default_model: openrouter/auto
  tts_voice: ms-MY-OsmanNeural
  language_detection: true

evolution_log:
  - version: "1.0.0"
    date: "2026-04-01"
    change: initial SOUL.md constitutional identity
    author: dev
  - version: "2.0.0"
    date: "2026-04-24"
    change: OpenClaw-inspired restructure
    author: dev
  - version: "2.1.0"
    date: "2026-04-27"
    change: restored from sweep corruption
    author: dev

```

## data/standing_orders.yml
```yaml
---
- name: nightly_dreams
  description: Consolidate memories during low-activity periods
  trigger: scheduled
  interval_s: 86400
  command: dreams consolidate
  enabled: true
  state: done
  last_run_at: 1777836021
- name: weekly_scan
  description: Weekly codebase axiom scan for regressions
  trigger: scheduled
  interval_s: 604800
  command: scan
  enabled: false
  state: pending
  last_run_at: 0
- name: data_integrity_check
  description: Detect and recover from corrupted data/ YAML files (LLM error strings
    written as file content)
  trigger: scheduled
  interval_s: 3600
  command: "/scan data/"
  enabled: true
  state: running
  last_run_at: 1777590915

```

## data/sweep_prompts.yml
```yaml
# Sweep stage prompt building blocks

axioms: |
  Constitutional constraints (non-negotiable):
  - Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
  - Default to no change if improvement is uncertain (PRESERVE_FIRST)
  - Minimum change that eliminates the violation (SIMPLEST_WORKS)
  - Raise/log errors; never swallow them silently (FAIL_VISIBLY)
  - Config in data/*.yml; code reads from there (ONE_SOURCE_OF_TRUTH)
  - rescue SpecificError => e; never bare rescue (SPECIFIC_RESCUE)
  - Extract literals to named constants; no magic numbers
  - Read current behavior before changing anything (zen: observe)
  - Change one axis at a time with clear boundaries (zen: isolate)

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
  - SPLIT
```

## data/templates.yml
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
    exit 0
```

## data/workflow.yml
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
    prune: "Loads patterns from data/rules.yml (voice.strunk) — single source of truth."
    conceptual: "Loads philosophy from data/rules.yml (zen + voice) — single source of truth."
    deep_caution: "deep adds 2 LLM calls per file. With 90 files at 8 req/min free tier = 22+ minutes."

principle_groups:
  axioms:      [frozen_string, explicit, immutable, self_explaining]
  solid:       [srp, cqs, pola]
  clean_code:  [long_method, god_class, duplicate_code, bare_rescue]
  interface:   [nielsen, prune]
  llm_rules:   [conceptual, adversarial]
  heavy:       [rubocop, reek]
  quick:       [frozen_string, bare_rescue, explicit, long_method, god_class]
  critical:    [frozen_string, bare_rescue, explicit, immutable, srp, cqs]

scan_profiles:
  quick:
    depth: standard
    rules: quick
    description: "Fast scan — core violations only"
  full:
    depth: deep
    rules: "*"
    description: "All rules, deep LLM analysis"
  critical:
    depth: standard
    rules: critical
    description: "Critical issues blocking ship"
  solid:
    depth: standard
    rules: solid
    description: "SOLID principles focus"
  axioms:
    depth: standard
    rules: axioms
    description: "Constitutional axioms only"

conflicts:
  strategy: highest_priority_wins
  rules:
    - condition: "dry conflicts with wet or aha"
      resolution: "favor wet/aha if fewer than 3 duplications exist"
    - condition: "clarity conflicts with simplicity"
      resolution: "favor clarity"
    - condition: "fix introduces higher priority violation"
      resolution: "reject fix, report to autoloop"

universal_scope:
  policy: ALL_PRINCIPLES_ALL_FILES
  statement: >
    All axioms, principles, and philosophies apply to every file in the codebase
    regardless of file type: Ruby, YAML, Zsh, HTML, CSS, JavaScript, Markdown.
    Language-specific rules apply only to their target language; universal rules
    (SQUINT_TEST, TYPOGRAPHY_DISCIPLINE, MEANINGFUL_NAMES, etc.) apply everywhere.
  scan_glob: "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}"
  conceptual_rules: all_known_languages
  adversarial_rules: all_known_languages

autoloop:
  scan_depth: standard
  fix_depth: llm
  batch_size: 3
  max_cycles: 12
  rate_limit_sleep: 15
  max_file_bytes: 16000
  max_fix_retries: 3
  confidence_threshold: 0.60
  targets:
    - lib/
    - test/
    - data/
    - web/
    - DEPLOY/
  excludes:
    - vendor/
    - knowledge/
    - fix_
    - patch_
  skip_rules:
    - duplicate_code
    - conceptual
    - adversarial
    - axiom_coverage
    - immutable
    - self_explaining
    - long_method
    - pola
    - srp
    - cqs

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
    - data/soul.yml
    - data/rules.yml
    - data/ruby_style.yml
    - data/workflow.yml
    - data/standing_orders.yml
  check_standing_orders: "Verify FSM state before any mutation -- UNCHANGE blocks refactoring"
  scan_before_analysis: "Use /scan deep via MASTER, not external agents, for code analysis"
  ssh_edit_pattern: "Write to /tmp, run ruby /tmp/patch.rb -- never ruby -i with heredoc"

corruption_prevention:
  llm_error_in_file: "git checkout HEAD -- data/ && rcctl restart master -- LLM error strings silently overwrite YAML data files when circuit is open and agent#ask returns error string instead of raising"
  sweep_excludes_data: "Sweep must never rewrite data/*.yml -- these are structured config, not code to refactor"
  yaml_type_guards: "All load_yaml calls must type-check result before use (is_a?(Array/Hash)) -- circuit-open strings parse as valid YAML scalars"
  ask_raises_on_error: "agent#ask must raise StandardError when result.err? -- callers must rescue, never silently propagate error strings as LLM output"

```

## data/zsh_patterns.yml
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
  benefit: "Model reasons locally instead of globally across pipeline"
```
