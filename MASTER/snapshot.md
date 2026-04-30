# MASTER Snapshot
Generated: 2026-04-30T19:13:06Z
Files: 137

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

# Optional placeholders for future extensions
windows:
  audio: powershell
  firewall: windows_defender
  http_server: iis
  package_manager: winget
  privilege: runas
  service_manager: sc
  shell: powershell

# End of platform definitions
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
  last_run_at: 1777530792
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
  state: done
  last_run_at: 1777575780
```

## data/sweep_prompts.yml
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

## data/web/favicon.svg
```text
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#0f172a"/>
  <path d="M16 44V20h8l8 12 8-12h8v24h-8V32l-8 10-8-10v12h-8z" fill="#38bdf8"/>
</svg>
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

## exe/master
```text
#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
$stdout.set_encoding("UTF-8")
$stderr.set_encoding("UTF-8")

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "master"

# Boot the web UI alongside the CLI.
# Kills any leftover process on the web port before starting fresh.
# Both CLI and web UI read port/host from the same config.
def boot_web_ui(config)
  port = config["web_port"] || 10002
  host = config["web_host"] || "0.0.0.0"

  if Master::Platform.openbsd?
    # Kill stale falcon/ruby processes on the port before rcctl start.
    system("doas pkill -TERM -f 'falcon.*#{port}' 2>/dev/null || true")
    sleep 0.5
    system("doas rcctl restart master > /dev/null 2>&1")
  else
    # Non-OpenBSD: kill anything on the port, then spawn Falcon directly.
    require "open3"
    Open3.capture3("lsof -ti:#{port} 2>/dev/null | xargs -r kill -TERM 2>/dev/null")
    sleep 0.5
    web_dir = File.expand_path("../web", __dir__)
    if Dir.exist?(web_dir)
      spawn(
        { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" },
        "bundle", "exec", "falcon", "serve", "--bind", "http://#{host}:#{port}",
        chdir: web_dir,
        out: File::NULL, err: File::NULL
      )
    end
  end
rescue StandardError => e
  $stderr.puts "web_ui: #{e.message}"
end

cli = nil

trap("INT")  { cli&.container&.dig(:session)&.save! rescue nil; $stderr.puts "\nsaved"; exit 0 }
trap("TERM") { cli&.container&.dig(:session)&.save! rescue nil; exit 0 }

if $stdin.tty?
  cli = Master.boot(root: Dir.pwd, argv: ARGV)
  boot_web_ui(cli.container[:config])

  message = ARGV.join(" ").strip
  cli.run(message.empty? ? nil : message)
else
  container = Master.build(root: Dir.pwd)
  cli       = Master::CLI.new(container:)
  $stdout.sync = true
  $stdin.each_line { |line| cli.pipe(line) }
end
```

## lib/master/agent.rb
```ruby
# frozen_string_literal: true

require "ruby_llm"
require "digest"
require_relative "agent/llm_dispatch"

module Master
  class Agent
    include LlmDispatch

    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN = 0.000_015

    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze

    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = Master.load_yaml(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re.freeze
    MAX_TOOL_TURNS = 5
    MIN_API_KEY_LENGTH = 20
    TOOL_CALL_RE = /(?:<use_tool>\s*(.*?)\s*<\/use_tool>|^ACTION:\s*(\{.*?\})\s*$|^TOOL:\s*(\{.*?\})\s*$)/m.freeze
    NEMOTRON3_RE = /nemotron-3/i.freeze
    LLAMA_NEMOTRON_RE = /llama.*nemotron|nemotron.*llama/i.freeze

    LLM_TOOL_MAP = {
      Tools::ReadFile        => Tools::LLM::ReadFile,
      Tools::WriteFile       => Tools::LLM::WriteFile,
      Tools::StrReplace      => Tools::LLM::StrReplace,
      Tools::ListDir         => Tools::LLM::ListDir,
      Tools::SearchFiles     => Tools::LLM::SearchFiles,
      Tools::Shell           => Tools::LLM::Shell,
      Tools::WebSearch       => Tools::LLM::WebSearch,
      Tools::AskLlm          => Tools::LLM::AskLlm,
      Tools::GitContext      => Tools::LLM::GitContext,
      Tools::AstEdit         => Tools::LLM::AstEdit,
      Tools::SearchKnowledge => Tools::LLM::SearchKnowledge
    }.freeze

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
    end

    def chat(message, stream: true, escalation_depth: 0, &blk)
      @context_window&.check_and_compact!
      @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
      @session.add_message(role: :user, content: message)
      candidate_models = routed_models
      prompt = apply_reasoning_mode(message)
      context = conversation_context
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

def ask(prompt, context: nil)
      messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
      selected_model = routed_models.first
      result = send_with_cache(selected_model, messages, stream: false)
      raise result.message if result.respond_to?(:err?) && result.err?
      result.to_s
    end

    def ask_once(prompt, system: nil)
      send_with_cache(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    def ask_once_with_model(prompt, model:, system: nil)
      send_with_cache(model, [{ role: "user", content: prompt.to_s }], system: system, stream: false).to_s
    end

    def call(ctx)
      on_chunk = ctx[:on_chunk]
      task_type = ctx[:task_type]&.to_s
      with_task_type(task_type) do
        on_chunk ? chat(ctx[:message].to_s, stream: true, &on_chunk) : chat(ctx[:message].to_s)
      end
    end

    def model = routed_models.first
    def model=(val)
      @config["model"] = val
    end

    def wire_context_window(ctx_window)
      @context_window = ctx_window
    end

    private

    def with_task_type(type)
      return yield unless type && !type.empty?
      old = @config["task_type"]
      @config["task_type"] = type
      yield
    ensure
      @config["task_type"] = old
    end

    def apply_reasoning_mode(message)
      return message unless @reasoning_modes
      @reasoning_modes.wrap(message, mode: @config.reasoning_mode)
    end

    def system_prompt
      parts = []
      parts << @personality.system_prompt if @personality
      parts << @code_index.summary if @code_index&.built?
      parts << @memory.context_summary if @memory&.context_summary
      parts.empty? ? nil : parts.join("\n\n")
    end

    def conversation_context(max_messages: DEFAULT_MESSAGE_WINDOW_SIZE)
      messages = @session.messages
      return [] unless messages.respond_to?(:each)
      messages.last(max_messages + 1)[0...-1] || []
    end
  end
end
```

## lib/master/agent/llm_dispatch.rb
```ruby
# frozen_string_literal: true

module Master
  class Agent
    # LlmDispatch — low-level LLM request routing, caching, escalation.
    # Extracted from Agent to keep the public API class focused.
    module LlmDispatch
      private

      def attempt_chat_with_fallbacks(candidate_models, prompt, context, stream, &blk)
        capable = candidate_models.select { |m|
          replicate_model?(m) || ferrum_model?(m) || tool_capable?(m)
        }
        if capable.empty?
          return Result.err(
            "no tool-capable model available",
            category: :validation
          )
        end

        last_response = nil
        capable.each_with_index do |selected_model, index|
          response = send_with_cache(
            selected_model,
            context + [{ role: "user", content: prompt }],
            stream: stream, &blk
          )
          last_response = response
          if response.respond_to?(:ok?) && response.ok?
            @bus&.publish(
              "llm:response",
              model: selected_model, success: true,
              tokens_approx: response.to_s.bytesize / 4
            )
          end
          break response unless response.respond_to?(:err?) && response.err? && index < capable.length - 1
        end
        last_response
      end

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
        escalated = chat(
          original_message, stream: stream,
          escalation_depth: escalation_depth + 1, &blk
        )
        escalated.respond_to?(:err?) && escalated.err? ? last_response : escalated
      end

      def send_with_cache(selected_model, messages, system: nil, stream: false, &blk)
        cache_key = cache_key_for(messages.last[:content], messages[0...-1])
        breaker_for(selected_model).call(estimate_cost(messages.last[:content])) {
          @cache.fetch(cache_key, selected_model) {
            send_llm_request(selected_model, messages, system: system, stream: stream, &blk)
          }
        }
      rescue StandardError => err
        Result.err("llm_request: #{err.message}", category: :llm_call_failure)
      end

      def send_llm_request(selected_model, messages, system: nil, stream: false, &blk)
        sys = system || system_prompt
        if ferrum_model?(selected_model)
          return send_ferrum(selected_model, messages)
        elsif replicate_model?(selected_model)
          return send_replicate(selected_model, messages, sys, stream, &blk)
        end

        send_ruby_llm(selected_model, messages, sys, stream, &blk)
      end

      def send_ferrum(selected_model, messages)
        alias_name = selected_model.split(":", 3).last
        response = Bridges::FerrumWebChat.new.ask(
          model_alias: alias_name, prompt: messages.last[:content]
        )
        return response if response.respond_to?(:err?) && response.err?
        Result.ok(
          response.respond_to?(:ok?) && response.ok? ? response.value! : response.to_s
        )
      end

      def send_replicate(selected_model, messages, sys, stream, &blk)
        reply = Bridges::Replicate.new.chat(
          model: selected_model, messages: messages, system: sys,
          stream: stream, &(stream ? blk : nil)
        )
        Result.ok(reply.content.to_s)
      end

      def send_ruby_llm(selected_model, messages, sys, stream, &blk)
        chat_session = RubyLLM.chat(model: selected_model)
        final_sys = nemotron_system_prompt(selected_model, sys)
        chat_session.with_instructions(final_sys) if final_sys
        messages.each { |msg|
          chat_session.add_message(role: msg[:role].to_s, content: msg[:content].to_s)
        }

        available_tools = llm_tools(selected_model)
        chat_session.with_tools(*available_tools) unless available_tools.empty?

        reply = if stream && blk
          chat_session.ask(messages.last[:content]) { |chunk|
            blk.call(chunk.content.to_s) if chunk.content
          }
        else
          chat_session.ask(messages.last[:content])
        end
        Result.ok(extract_response(reply, selected_model))
      end

      def routed_models
        return [@config.model] unless @model_router
        @model_router.fallback_chain(task_type: @config.task_type.to_sym)
      rescue StandardError => e
        @bus&.publish("llm:route_error", error: e.message) if defined?(@bus)
        [@config.model]
      end

      def breaker_for(model_id)
        @circuit_breaker.respond_to?(:for) ? @circuit_breaker.for(model_id) : @circuit_breaker
      end

      def replicate_model?(model_id)
        return false unless ENV["REPLICATE_API_KEY"].to_s.length >= MIN_API_KEY_LENGTH
        REPLICATE_OWNERS.include?(model_id.to_s.split("/").first)
      end

      def ferrum_model?(model_id)
        model_id.to_s.start_with?("ferrum:webchat:")
      end

      def tool_capable?(model_id)
        TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)
      end

      def extract_response(reply, selected_model)
        return reply.to_s unless reply.respond_to?(:content)
        if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
          thinking = reply.reasoning_content.to_s.strip
          content = reply.content.to_s
          return thinking.empty? ? content : "#{content}\n\n<think>\n#{thinking}\n</think>"
        end
        reply.content.to_s
      end

      def nemotron_system_prompt(selected_model, base = nil)
        sys = base || system_prompt
        return sys unless LLAMA_NEMOTRON_RE.match?(selected_model)
        thinking_on = @config["reasoning_mode"] != "none"
        directive = thinking_on ? "detailed thinking on" : "detailed thinking off"
        [directive, sys].compact.join("\n\n")
      end

      CACHE_WINDOW = 4
      def cache_key_for(message, context)
        return Digest::SHA256.hexdigest(message) if context.empty?
        window = context.last(CACHE_WINDOW).map { |msg|
          "#{msg[:role]}:#{msg[:content]}"
        }.join("\n")
        Digest::SHA256.hexdigest("#{message}\n#{window}")
      end

      def estimate_cost(prompt)
        (prompt.bytesize / 4) * COST_PER_TOKEN
      end

      def llm_tools(selected_model = model)
        return [] unless tool_capable?(selected_model)
        @llm_tools ||= build_llm_tools
      end

      def build_llm_tools
        @tools.filter_map do |tool|
          wrapper = LLM_TOOL_MAP[tool.class]
          wrapper&.new(tool)
        end
      rescue StandardError => err
        @bus&.publish("agent:llm_tools_error", error: err.message)
        []
      end
    end
  end
end
```

## lib/master/audit_log.rb
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only audit trail of every tool invocation.
  # Subscribes to tool:before events on the shared EventBus.
  # Written to .master/audit.log — one line per call, machine-readable.
  class AuditLog
    LOG_PATH = ".master/audit.log".freeze
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

## lib/master/autoloop.rb
```ruby
# frozen_string_literal: true

require "open3" # No longer directly used, moving to Master::GitOperations
require_relative "git_operations"

require_relative "autoloop/fix_evaluator"

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
    RATE_LIMIT_SLEEP = 15     # ONE_SOURCE: no more hardcoded `sleep 15`.freeze
    MAX_FIX_RETRIES  = 3
    SCORE_INCREMENT  = 0.25
    MAX_SIZE_RATIO   = 2.0
    MIN_SIZE_RATIO       = 0.80   # Reject fix if output < 80% of original file size.freeze
    CONFIDENCE_THRESHOLD = 0.60   # Below this, escalate to a reflective retry.freeze
    MAX_FILE_BYTES   = 16_000 # Raised from 4_000 so core files (agent.rb, cli.rb) are fixable.freeze

    # Rules that cannot be safely auto-fixed by rewriting a single file.
    # duplicate_code requires cross-file refactoring; conceptual/adversarial are LLM-only.
    SKIP_RULES = %w[duplicate_code conceptual adversarial axiom_coverage immutable self_explaining long_method pola srp cqs].freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    # Transient error signatures that trigger a reflected retry
    # rather than abandon the fix. 429 = rate limit, 503 = overload.
    TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze

    def initialize(agent:, scanner:, root:, event_bus: nil, soul: nil, learnings: nil)
      @agent           = agent
      @scanner         = scanner
      @root            = root
      @bus             = event_bus
      @soul            = soul
      @learnings       = learnings
      @rule_recurrence = Hash.new(0) # rule_id => consecutive_cycle_count
      @git             = GitOperations.new(root)
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
          (@learnings || Learnings.new(root: @root)).tap do |l|
            fixes.each_value { |v, _| l.record(trigger: v[:rule].to_s, strategy: "autoloop_fix", outcome: "commit") }
          end
        end
        track_recurrence(violations)
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    include FixEvaluator
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
      result = Reflexion.run(agent: @agent, task: base_prompt, max: MAX_FIX_RETRIES) do |prompt, attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        begin
          fix = extract_code(@agent.ask(prompt).to_s)
          next nil if fix.nil?
          next nil if confidence_score(fix, src) < CONFIDENCE_THRESHOLD
          fix
        rescue StandardError => e
          err = e.message.to_s
          if TRANSIENT_RE.match?(err) && attempt < MAX_FIX_RETRIES - 1
            @bus&.publish("autoloop:rate_limit", sleep: RATE_LIMIT_SLEEP * (attempt + 1), attempt: attempt + 1)
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: err[0, 120])
          end
          nil
        end
      end
      result.respond_to?(:ok?) && result.ok? ? result.value! : nil
    end
  end
end
```

## lib/master/autoloop/fix_evaluator.rb
```ruby
# frozen_string_literal: true

module Master
  class AutoLoop
    module FixEvaluator
      private

      def build_fix_prompt(violation, src)
        "Fix this Ruby violation in #{violation[:file]}.\n" \
          "Rule: #{violation[:rule]}\n" \
          "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
          "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
          "```ruby\n#{src}\n```"
      end

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

      def confidence_score(code, original_src)
        return 0.0 if code.nil? || code.strip.empty?
        score = 0.0
        score += SCORE_INCREMENT if code.include?("# frozen_string_literal: true")
        score += SCORE_INCREMENT if code.match?(/\A.*?(?:module |class )[A-Z]/m)
        ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
        score += SCORE_INCREMENT if ratio >= MIN_SIZE_RATIO && ratio <= MAX_SIZE_RATIO
        score += SCORE_INCREMENT if syntax_ok?(code)
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
      rescue StandardError
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
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end
    end
  end
end
```

## lib/master/axioms.rb
```ruby
# frozen_string_literal: true


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

    def preserve
      @preserve ||= (voice["preserve"] || {}).freeze
    end

    def constitution
      @constitution ||= begin
        constitution_data = {}
        constitution_data["golden_rule"] = @data["golden_rule"]
        constitution_data["protection"] = @data["protection"]
        constitution_data["banned_output"] = voice["banned_output"]
        constitution_data["anti_simulation"] = voice["anti_simulation"]
        constitution_data["communication_style"] = voice["style"]
        constitution_data.freeze
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

      Master.load_yaml(path, permitted_classes: [], permitted_symbols: [], aliases: true)
    rescue StandardError
      nil
    end
  end
end
```

## lib/master/builder.rb
```ruby
# frozen_string_literal: true

require_relative "builder/infra_helpers"

module Master
  # Builder — assembles the dependency container.
  # Three phases: infrastructure → AI stack → pipeline + gateway.
  module Builder
    RING_SIZE = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS = %w[exe lib/master data].freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai_stack(root, infra)
      pipeline, gateway = build_pipeline_and_gateway(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    def build_infrastructure(root)
      config = Config.new(root)
      config["model"] ||= Master.default_model

      bus = EventBus.new
      ring = RingBuffer.new(RING_SIZE)
      logging = Logging.new(ring_buffer: ring, event_bus: bus)
      session = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
      undo = Undo.new(session:, event_bus: bus, root:)
      breaker = CircuitBreakerRegistry.new(
        budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
      )
      cache = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
      governor = Governor.new(config:, event_bus: bus)
      renderer = Renderer.new(config:)
      metrics = Metrics.new(root:, event_bus: bus)
      AuditLog.new(root:, event_bus: bus)

      code_index = CodeIndex.new(root:, event_bus: bus)
      diff_stager = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
      mcp = McpCoordinator.new(root:, event_bus: bus)
      mcp.connect_all
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }

      memory = Memory.new(root:)
      personality = Personality.new(
        config["persona"]&.to_sym || Personality::DEFAULT, root:
      )

      phase_gates = PhaseGates.new(root:, event_bus: bus)
      {
        config:, ring:, bus:, logging:, session:, undo:, breaker:, cache:,
        governor:, renderer:, metrics:, code_index:, diff_stager:, mcp:,
        memory:, personality:, phase_gates:
      }
    end

    def build_ai_stack(root, infra)
      config = infra[:config]
      bus = infra[:bus]

      tools = build_tools(root:, infra:)
      tools += infra[:mcp].tools
      router = Routing::ModelRouter.new(config:)
      modes = Reasoning::Modes.new
      agent = Agent.new(
        config:, session: infra[:session], tools:,
        circuit_breaker: infra[:breaker], cache: infra[:cache],
        event_bus: bus, model_router: router, reasoning_modes: modes,
        memory: infra[:memory], personality: infra[:personality],
        code_index: infra[:code_index]
      )
      soul_doc = Soul.new(root:, agent:)
      tools << Tools::AskLlm.new(
        agent:, governor: infra[:governor],
        circuit_breaker: infra[:breaker], cache: infra[:cache],
        event_bus: bus
      )

      ctx_window = ContextWindow.new(
        session: infra[:session], agent:, model_context: CTX_WINDOW_SIZE
      )
      ctx_window.check_and_compact!
      agent.wire_context_window(ctx_window)

      scanner = build_scanner(root:, agent:, bus:)
      swarm = Swarm::Coordinator.new(agent:, event_bus: bus)
      personas = Council::Personas.load(File.join(ROOT, "data", "council.yml"))
      deliberation = Council::Deliberation.new(personas:, agent:, event_bus: bus)
      council_stage = Stages::Council.new(deliberation:, config:)

      standing = StandingOrders.new(pipeline: nil, event_bus: bus)
      learnings = Learnings.new(root:)
      autoloop = AutoLoop.new(agent:, scanner:, root:, event_bus: bus, soul: soul_doc, learnings:)
      skills = Skills.new(root:, event_bus: bus)
      skills.discover!
      heartbeat = Heartbeat.new(root:, agent:, scanner:, memory: infra[:memory], event_bus: bus)
      triggers = Triggers.new(event_bus: bus, scanner:, agent:)
      triggers.install_defaults!

      {
        agent:, soul: soul_doc, scanner:, swarm:, deliberation:,
        council_stage:, standing:, autoloop:, learnings:,
        guard: Security::InjectionGuard.new,
        heartbeat:, skills:, triggers:
      }
    end

    def build_pipeline_and_gateway(root, infra, ai)
      config = infra[:config]
      bus = infra[:bus]
      commands = CommandRegistry.build(infra:, ai:, root:)

      stages = [
        Stages::Intake.new,
        Stages::Infer.new,
        Stages::Route.new(commands:, agent: ai[:agent]),
        Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Stages::Execute.new,
        Pipeline::SkipOnPressure.new(Pipeline::ParallelGroup.new(
          ai[:council_stage],
          Stages::Lint.new(scanner: ai[:scanner], config:, autoloop: ai[:autoloop], root:)
        )),
        Pipeline::SkipOnPressure.new(Stages::Prune.new),
        Stages::Memo.new(memory: infra[:memory], event_bus: bus),
        Stages::Render.new(renderer: infra[:renderer])
      ]

      pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
      ai[:standing].wire_pipeline(pipeline)

      gateway = Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(ctx) { gateway.channels }

      [pipeline, gateway]
    end

    def build_tools(root:, infra:)
      bus = infra[:bus]
      undo = infra[:undo]
      governor = infra[:governor]
      [
        Tools::ReadFile.new(root:, undo:, event_bus: bus),
        Tools::WriteFile.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::StrReplace.new(root:, undo:, governor:, event_bus: bus, diff_stager: infra[:diff_stager]),
        Tools::ListDir.new(root:, event_bus: bus),
        Tools::SearchFiles.new(root:, event_bus: bus),
        Tools::WebSearch.new(governor:, event_bus: bus),
        Tools::Shell.new(root:, governor:, event_bus: bus),
        Tools::BatchReplace.new(root:, governor:, event_bus: bus),
        Tools::GitContext.new(root:, event_bus: bus),
        Tools::AstEdit.new(root:, undo:, event_bus: bus),
        Tools::Tree.new(root:, event_bus: bus),
        Tools::SymbolLookup.new(code_index: infra[:code_index], event_bus: bus),
        Tools::Clean.new(root:, governor:, event_bus: bus),
        Tools::SearchKnowledge.new(root:, event_bus: bus)
      ]
    end

  end
end
```

## lib/master/builder/infra_helpers.rb
```ruby
# frozen_string_literal: true

module Master
  module Builder
    module_function
    def build_scanner(root:, agent:, bus:)
      scanner = Scan::Scanner.new(event_bus: bus)
      [
        Scan::Rules::FrozenStringRule, Scan::Rules::BareRescueRule,
        Scan::Rules::ExplicitRule, Scan::Rules::ImmutableRule,
        Scan::Rules::CqsRule, Scan::Rules::SelfExplainingRule,
        Scan::Rules::LongMethodRule, Scan::Rules::GodClassRule,
        Scan::Rules::DuplicateCodeRule, Scan::Rules::PruneRule,
        Scan::Rules::SrpRule, Scan::Rules::PolaRule,
        Scan::Rules::NielsenRule, Scan::Rules::AxiomCoverageRule
      ].each { |klass| scanner.add_rule(klass.new) }
      scanner.add_rule(Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Scan::Rules::ConceptualRule.new(agent:))
      scanner.add_rule(Scan::Rules::AdversarialRule.new(agent:))
      scanner
    end

    def boot_snapshot(container)
      root = container[:root]
      out = File.join(root, ".master", "snapshot.md")
      dirs = SNAPSHOT_DIRS.map { |d| File.join(root, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                  .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
      header = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      body = files.flat_map do |f|
        rel = f.sub("#{root}/", "")
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
  end
end
```

## lib/master/circuit_breaker.rb
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

## lib/master/circuit_breaker_registry.rb
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
end
```

## lib/master/cli.rb
```ruby
# frozen_string_literal: true

require_relative "cli/tts"
require_relative "cli/signals"

require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
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
      @session.load! if @session.exists?
      scan_in_background
      puts @renderer.splash(@agent.model)
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      stripped = input.strip
      return if stripped.empty?

      run_input(stripped)
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
        tokens = @session.token_est
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
      @session.save!
    end

    def exit_cli = (@session.save!; @running = false)

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
  end
end
```

## lib/master/cli/signals.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    private

    def setup_signals
      trap("USR1") do
        begin
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@renderer.render("reloaded", mode: :success)}"
        rescue StandardError => e
          puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
        end
      end
      trap("INT") do
        if Time.now - @interrupt_at < 1
          @scan_thread&.kill
          @session.save!
          exit(0)
        else
          @interrupt_at = Time.now
          puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
        end
      end
    end
  end
end
```

## lib/master/cli/tts.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    TTS_CHAR_LIMIT = 400

    private

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?
        audio_path = Speech.synthesize(plain)
        next unless audio_path
        played = Speech.play(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        File.unlink(audio_path) rescue nil if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain.gsub(/```.*?```/m, "")[0..TTS_CHAR_LIMIT]
    end
  end
end
```

## lib/master/code_index.rb
```ruby
# frozen_string_literal: true

require "prism"
require "set"
require "monitor"
require_relative "code_index/symbol_visitor"


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
      @lock = Monitor.new
      @build_thread = nil
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
      @mtimes[f] = File.mtime(f) rescue Errno::ENOENT
    end
  else
    changed = 0

    (@mtimes.keys - files).each do |gone|
      @symbols.delete_if { |_, s| s.file == gone }
      @references.reject! { |r| r.from_file == gone }
      @mtimes.delete(gone)
    end

    files.each do |f|
      mt = File.mtime(f) rescue Errno::ENOENT
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

  def build_async
    @build_thread = Thread.new { build }
    self
  end

  def ready?
    @built_at != nil
  end

  def wait_for_build
    @build_thread&.join
  end

    # Re‑index a single file, removing stale data first.
    def reindex(file)
      full = File.expand_path(file, @root)
      @symbols.delete_if { |_, s| s.file == full }
      @references.reject! { |r| r.from_file == full }
      index_file(full) if File.file?(full)
    rescue StandardError => e
      @bus&.publish("code_index:reindex_error", path: file, error: e.message)
    end

    def symbols_in(file)
      wait_for_build unless ready?
      full = File.expand_path(file, @root)
      @symbols.values.select { |s| s.file == full }
    end

    def find(name)
      wait_for_build unless ready?
      exact = @symbols[name]
      return [exact] if exact

      suffix = name.to_s
      @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
    end

    def references_to(fqn)
      wait_for_build unless ready?
      @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") }
    end

    def impact(fqn)
      wait_for_build unless ready?
      refs = references_to(fqn)
      files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
      callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
      { fqn:, reference_count: refs.size, files:, callers: }
    end

    # Classes‑only summary injected into the agent system prompt.
    def summary(limit: nil)
      wait_for_build unless ready?
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
      wait_for_build unless ready?
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
      result = Prism.parse(src, freeze: true)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError => e
      @bus&.publish("code_index:parse_error", path: file, error: e.message)
    end

  end
end
```

## lib/master/code_index/symbol_visitor.rb
```ruby
# frozen_string_literal: true

module Master
  class CodeIndex
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
end
```

## lib/master/command_registry.rb
```ruby
# frozen_string_literal: true

require_relative "command_registry/agent_commands"
require_relative "command_registry/memory_commands"
require_relative "command_registry/service_commands"

module Master
  # CommandRegistry — all pipeline-routable commands in one place.
  module CommandRegistry
    module_function

    def build(infra:, ai:, root:)
      session_commands(infra).merge(
        mode_commands(infra[:config]),
        agent_commands(ai:, root:, infra:),
        memory_commands(infra[:memory], ai[:agent]),
        service_commands(ai),
        utility_commands(ai[:agent], root, infra[:cache]),
        control_commands(ai[:standing], ai[:soul]),
        "help" => ->(_ctx) {
          "just talk. intent is inferred automatically.\n" \
          "exit with /exit or ctrl-C twice."
        }
      )
    end

    def session_commands(infra)
      session = infra[:session]
      undo = infra[:undo]
      logging = infra[:logging]
      config = infra[:config]
      {
        "clear"  => ->(_ctx) { session.clear!; "context cleared" },
        "save"   => ->(_ctx) { session.save!; "session saved" },
        "tokens" => ->(_ctx) { "~#{session.token_est} tokens" },
        "undo"   => ->(_ctx) { result = undo.undo!; result.ok? ? "reverted: #{result.value!}" : result.message },
        "dmesg"  => ->(_ctx) { logging.dmesg },
        "cost"   => ->(_ctx) { "$#{"%.4f" % session.cost}" },
        "config" => ->(_ctx) { config.data.inspect }
      }
    end

    def mode_commands(config)
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
          when "on"  then config["auto_testing"] = true; config.save!; "autotest: on"
          when "off" then config["auto_testing"] = false; config.save!; "autotest: off"
          else "autotest: #{config.auto_testing? ? "on" : "off"}"
          end
        },
        "persona" => ->(ctx) {
          arg = ctx[:args].to_s.strip.to_sym
          names = Personality::PERSONAS.keys
          if names.include?(arg)
            config["persona"] = arg.to_s
            config.save!
            "persona: #{arg}"
          else
            "persona: #{config["persona"] || "dark_malay"} -- available: #{names.join(", ")}"
          end
        }
      }
    end

  end
end
```

## lib/master/command_registry/agent_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def agent_commands(ai:, root:, infra:)
      agent = ai[:agent]
      scanner = ai[:scanner]
      config = infra[:config]
      bus = infra[:bus]
      metrics = infra[:metrics]
      deliberation = ai[:deliberation]
      council_stage = ai[:council_stage]
      swarm = ai[:swarm]
      {
        "council" => ->(ctx) {
          case ctx[:args].to_s.strip
          when "on"  then council_stage.enable!; "council: enabled"
          when "off" then council_stage.disable!; "council: disabled"
          else "council: #{council_stage.enabled? ? "on" : "off"}"
          end
        },
        "swarm" => ->(ctx) {
          args = ctx[:args].to_s.strip.split(" ", 2)
          role = args[0]&.to_sym
          task = args[1].to_s
          if role.nil? || task.empty?
            "usage: /swarm <role> <task>  roles: #{swarm.worker_roles.join(", ")}"
          else
            result = swarm.dispatch(role, task:, context_slice: {})
            result.ok? ? result.value!.inspect : result.message
          end
        },
        "explain" => ->(_ctx) {
          map = Introspection::SelfMap.new(root:)
          info = map.describe
          coverage = map.axiom_coverage
          cov_lines = coverage.map { |ax, n| "  #{ax}: #{n}" }.join("\n")
          stages = "Intake->Infer->Route->Guard->Execute->Council->Lint->Prune->Memo->Render"
          "MASTER -- #{info[:files]} files, #{info[:lines]} lines\npipeline: #{stages}\n\naxiom coverage:\n#{cov_lines}"
        },
        "autoloop" => ->(ctx) {
          max = ctx[:args].to_s.strip.to_i
          max = AutoLoop::MAX_CYCLES if max <= 0
          looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = looper.run(max_cycles: max) { |cycle, violations|
            log << "  cycle #{cycle}: #{violations.size} violation(s)"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "sweep" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          target = arg.empty? ? root : File.expand_path(arg, root)
          sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
          log = []
          result = sweeper.run(target) { |cycle, file, delta|
            log << "  cycle #{cycle}  #{file}  +#{delta}"
          }
          ([result.ok? ? result.value! : result.message] + log).join("\n")
        },
        "model" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "list"
            yml_path = File.join(root, "data", "models.yml")
            if File.exist?(yml_path)
              data = Master.load_yaml(yml_path)
              tiers = data["models"] || {}
              model_lines = tiers.flat_map { |tier, ms|
                ms.to_a.map { |mod| "  [#{tier}] #{mod["id"]}" }
              }
              quality_lines = metrics&.model_quality&.map { |mod, stat|
                "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
              } || []
              sections = ["available models:"] + model_lines
              sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
              sections.join("\n")
            else
              "model: #{agent.model}"
            end
          elsif arg.empty?
            "model: #{agent.model}"
          else
            agent.model = arg
            config.save!
            "model: #{arg}"
          end
        },
        "why" => ->(ctx) {
          rule = ctx[:args].to_s.strip
          if rule.empty?
            "usage: /why <rule_name>"
          else
            prompt = "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                     "give a before/after Ruby example, and state why it matters."
            agent.ask_once(prompt)
          end
        },
        "scan" => ->(ctx) {
          depth = ctx[:args].to_s.include?("deep") ? :deep : :standard
          raw_arg = ctx[:args].to_s.sub("deep", "").strip
          target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
          pairs = if target_arg && File.file?(target_arg)
            fr = scanner.scan(target_arg, depth:)
            [[target_arg, fr]]
          elsif target_arg && File.directory?(target_arg)
            r = scanner.scan_dir(target_arg, depth:, glob: "**/*")
            next "scan failed" unless r.ok?
            r.value!
          else
            r = scanner.scan_dir(File.join(root, "lib"), depth:)
            next "scan failed" unless r.ok?
            r.value!
          end
          result = Result.ok(pairs)
          next "scan failed" unless result.ok?
          by_rule = Hash.new { |h, k| h[k] = [] }
          result.value!.each do |_file, file_result|
            next unless file_result.respond_to?(:ok?) && file_result.ok?
            file_result.value!.each { |v| by_rule[v[:rule].to_s] << v }
          end
          total = by_rule.values.sum(&:size)
          next "clean -- no violations" if total.zero?
          lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
            ["[#{rule}] #{vs.size}"] +
              vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
          end
          lines << "#{total} total violations"
          lines.join("\n")
        }
      }
    end
  end
end
```

## lib/master/command_registry/memory_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def memory_commands(memory, agent)
      {
        "memory" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("forget ")
            key = arg.sub("forget ", "").strip
            memory.forget(key)
            "forgot: #{key}"
          elsif arg.start_with?("remember ")
            parts = arg.sub("remember ", "").split("=", 2)
            key = parts[0].strip
            val = parts[1]&.strip
            val ? (memory.remember(key, val); "remembered: #{key}") : "usage: /memory remember key=value"
          elsif arg.start_with?("search ")
            query = arg.sub("search ", "").strip
            hits = if memory.respond_to?(:semantic_recall)
                     memory.semantic_recall(query)
                   else
                     memory.all.select { |k, v| k.to_s.include?(query) || v.to_s.include?(query) }
                   end
            hits.empty? ? "(no matches: #{query})" : hits.map { |k, v| "#{k}: #{v}" }.join("\n")
          elsif arg.empty?
            entries = memory.all
            entries.empty? ? "(no memories)" : entries.map { |k, v| "#{k}: #{v}" }.join("\n")
          else
            val = memory.recall(arg)
            val ? "#{arg}: #{val}" : "(not found: #{arg})"
          end
        },
        "dreams" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg == "consolidate"
            memory.respond_to?(:consolidate!) ? memory.consolidate!(agent:) : "dreaming not available"
          else
            entries = memory.all
            archived = entries.count { |k, _| k.to_s.start_with?("archive/") }
            active = entries.count { |k, _| !k.to_s.start_with?("archive/") }
            summary = memory.recall("_consolidated_summary")
            lines = ["active: #{active} memories, archived: #{archived}"]
            lines << "last consolidation: #{summary}" if summary
            lines.join("\n")
          end
        }
      }
    end
  end
end
```

## lib/master/command_registry/service_commands.rb
```ruby
# frozen_string_literal: true

module Master
  module CommandRegistry
    module_function

    def control_commands(standing, soul)
      {
        "orders" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "list", ""
            standing.list
          when /\Aenable (.+)\z/
            standing.enable($1.strip)
          when /\Adisable (.+)\z/
            standing.disable($1.strip)
          when /\Aadd name=(\S+) cmd=(.+)\z/
            standing.upsert(name: $1, command: $2.strip)
          when "run"
            results = standing.run_due!
            if results.empty?
              "no orders due"
            else
              results.map { |r|
                "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}"
              }.join("\n")
            end
          when /\Areset (.+)\z/
            standing.reset($1.strip)
          else
            "usage: /orders  /orders enable|disable|reset <name>  /orders run"
          end
        },
        "soul" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "", "show" then soul.summary
          when "version", "changelog" then soul.changelog
          when "diff" then soul.diff
          when "approve" then soul.approve
          when "reject" then soul.reject
          when "rollback" then soul.rollback
          when /\Apropose (.+)\z/ then soul.propose($1.strip)
          else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
          end
        }
      }
    end

    def service_commands(ai)
      heartbeat = ai[:heartbeat]
      skills = ai[:skills]
      {
        "heartbeat" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "run"   then heartbeat ? heartbeat.run_due!.map { |r| "#{r[:name]}: #{r[:result]}" }.join("\n") : "no heartbeat"
          when "start" then heartbeat&.start!; "heartbeat started"
          when "stop"  then heartbeat&.stop!; "heartbeat stopped"
          else heartbeat&.list || "no heartbeat"
          end
        },
        "skills" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.empty?
            skills&.list || "(no skills)"
          else
            found = skills&.find(arg)
            found ? "#{found[:name]}: #{found[:description]}" : "(not found: #{arg})"
          end
        }
      }
    end

    def utility_commands(agent, root, cache)
      {
        "snapshot" => ->(_ctx) {
          stamp = Time.now.strftime("%Y%m%d_%H%M%S")
          out = File.expand_path("~/master_snapshot_#{stamp}.md")
          dirs = %w[exe lib/master web/app web/config data].map { |d| File.join(root, d) }
          files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                      .select { |f| File.file?(f) && File.size(f) < CTX_WINDOW_SIZE }
                      .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                      .reject { |f| File.binread(f, 512).include?("\x00") rescue true }
                      .sort
          lines = ["# MASTER Codebase Snapshot", "Generated: #{Time.now.utc.iso8601}", ""]
          files.each do |f|
            rel = f.sub("#{root}/", "")
            lang = FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
            src = File.read(f, encoding: "UTF-8", invalid: :replace)
            lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
          rescue StandardError => e
            lines << "## #{rel}" << "[skipped: #{e.message}]" << ""
          end
          File.write(out, lines.join("\n"))
          "snapshot: #{files.size} files written to #{out}"
        },
        "cache" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          case arg
          when "clear"
            cache.invalidate_all!
            "cache cleared"
          else
            stats = cache.stats
            suffix = arg == "stats" ? "" : "  (use /cache clear to purge)"
            "cache: #{stats[:entries]} entries, #{stats[:size_kb]} KB#{suffix}"
          end
        },
        "diff" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          base = arg.empty? ? "HEAD" : arg
          out = `git -C #{root.shellescape} diff #{base} --stat 2>&1`.strip
          out.empty? ? "(no changes since #{base})" : out
        },
        "commit" => ->(_ctx) {
          diff = `git -C #{root.shellescape} diff --cached --stat 2>&1`.strip
          diff = `git -C #{root.shellescape} diff --stat 2>&1`.strip if diff.empty?
          next "nothing to commit" if diff.empty?
          prompt = "Write a concise git commit message (1 line, imperative mood) for these changes:\n#{diff}"
          msg = agent.ask_once(prompt).strip.lines.first.to_s.strip.gsub(/"/, "'")
          `git -C #{root.shellescape} add -u 2>&1 && git -C #{root.shellescape} commit -m "#{msg}" 2>&1`.strip
        },
        "knowledge" => ->(ctx) {
          arg = ctx[:args].to_s.strip
          if arg.start_with?("add ")
            url = arg.sub("add ", "").strip
            require "open-uri"
            require "shellwords"
            next "usage: /knowledge add <url>" if url.empty?
            slug = url.gsub(/[^a-z0-9._-]/i, "_").downcase[0, 60]
            kdir = File.join(root, "knowledge", "web")
            FileUtils.mkdir_p(kdir)
            dest = File.join(kdir, "#{slug}.txt")
            content = URI.open(url, read_timeout: 15, &:read)
                         .encode("UTF-8", invalid: :replace, undef: :replace)
            File.write(dest, content, encoding: "UTF-8")
            "saved #{content.bytesize} bytes to knowledge/web/#{slug}.txt"
          else
            "usage: /knowledge add <url>"
          end
        }
      }
    end
  end
end
```

## lib/master/config.rb
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  class Config
    BUDGET_MAX_DEFAULT = 10.0
    HISTORY_MAX = 500
    DEFAULT_WEB_PORT = 10_002

    DEFAULTS = {
      'model'          => 'nvidia/nemotron-3-super-120b-a12b:free',
      'web_host'       => '0.0.0.0',
      'web_public_url' => 'http://ai.brgen.no:3000',
      'web_port'       => DEFAULT_WEB_PORT,
      'budget_max'     => BUDGET_MAX_DEFAULT,
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
      @root  = root
      @path  = File.join(root, '.master', 'config.yml')
      @mutex = Mutex.new
      @data  = load_config
    end

    # Hash‑style access
    def [](key)         = @data[key.to_s]
    def []=(key, value) ; @mutex.synchronize { @data[key.to_s] = value } ; end

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
      @mutex.synchronize { @data = load_config }
    end

    # Export as plain hash (deep dup to avoid external mutation)
    def to_h = Marshal.load(Marshal.dump(@data))

    private

    def load_config
      return deep_dup(DEFAULTS) unless File.exist?(@path)

      raw = Master.load_yaml(@path); loaded = raw.is_a?(Hash) ? raw : {}
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
end
```

## lib/master/context_window.rb
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
end
```

## lib/master/convergence_loop.rb
```ruby
# frozen_string_literal: true

module Master
  # ConvergenceLoop — unified scan→fix→converge loop.
  # Replaces the separate AutoLoop (surgical patches) and Sweep (full rewrites).
  # Strategy selects the fix approach; convergence logic is shared.
  #
  # Stopping criteria (arxiv:2602.21833):
  #   1. violation delta < threshold for window consecutive cycles
  #   2. max_cycles reached
  #   3. oscillation detected (score goes up then down repeatedly)
  class ConvergenceLoop
    MAX_CYCLES  = 16
    THRESHOLD   = 0.05
    WINDOW      = 2

    STRATEGIES = %i[surgical rewrite].freeze

    def initialize(target:, scanner:, agent:, root:, strategy: :surgical,
                   intensity: :standard, max_cycles: MAX_CYCLES,
                   threshold: THRESHOLD, window: WINDOW, event_bus: nil)
      @target     = target
      @scanner    = scanner
      @agent      = agent
      @root       = root
      @strategy   = strategy
      @intensity  = intensity
      @max_cycles = max_cycles
      @threshold  = threshold
      @window     = window
      @bus        = event_bus
      @history    = []
    end

    def run
      @max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("convergence_loop:cycle", cycle:, strategy: @strategy, target: @target)

        violations = scan
        score = score_from(violations)
        @history << score

        @bus&.publish("convergence_loop:score", cycle:, score:, violations: violations.size)

        break if converged?
        break if oscillating?

        apply_fixes(violations)
      end

      Result.ok(cycles: @history.size, final_score: @history.last)
    end

    private

    def scan
      dirs = Array(@target).map { |t| File.expand_path(t, @root) }
      dirs.flat_map { |d| @scanner.scan_dir(d, depth: @intensity) }
    end

    def score_from(violations)
      return 100.0 if violations.empty?
      penalty = violations.sum { |v| severity_weight(v[:severity]) }
      [100.0 - penalty, 0.0].max
    end

    def severity_weight(sev)
      { critical: 5.0, error: 3.0, warning: 1.0, info: 0.2 }.fetch(sev.to_sym, 1.0)
    end

    def converged?
      return false if @history.size < @window
      recent = @history.last(@window)
      deltas = recent.each_cons(2).map { |a, b| (b - a).abs }
      deltas.all? { |d| d < @threshold }
    end

    def oscillating?
      return false if @history.size < 4
      last4 = @history.last(4)
      last4[0] < last4[1] && last4[1] > last4[2] && last4[2] < last4[3]
    end

    def apply_fixes(violations)
      case @strategy
      when :surgical then apply_surgical(violations)
      when :rewrite  then apply_rewrite
      end
    end

    def apply_surgical(violations)
      files = violations.map { |v| v[:path] }.uniq.compact.first(5)
      files.each do |path|
        next unless File.exist?(path)
        file_violations = violations.select { |v| v[:path] == path }
        prompt = build_surgical_prompt(path, file_violations)
        result = @agent.ask(prompt)
        next unless result.respond_to?(:ok?) && result.ok?
        apply_patch(path, result)
      end
    end

    def apply_rewrite
      # Delegate to Sweep for full-file rewrite strategy
      sweep = Sweep.new(@agent, @scanner, @root, @bus)
      sweep.run_single_cycle(target: @target)
    end

    def build_surgical_prompt(path, violations)
      code = File.read(path, encoding: "utf-8") rescue ""
      msgs = violations.map { |v| "  line #{v[:line]}: #{v[:message]}" }.join("\n")
      "Fix violations in #{path}:\n#{msgs}\n\nCurrent code:\n```ruby\n#{code}\n```\nReturn corrected file only."
    end

    def apply_patch(path, result)
      content = result.is_a?(String) ? result : result.to_s
      return if content.strip.empty?
      return if content.lines.size < (File.readlines(path).size * 0.8)
      File.write(path, content)
    rescue StandardError
      nil
    end
  end
end
```

## lib/master/council/deliberation.rb
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

        threads = @personas.map do |persona|
          Thread.new do
            response = @agent.ask(build_prompt(persona, code, context))
            entry = { persona: persona.name, role: persona.role,
                      veto_role: veto_role?(persona), feedback: response }
            @bus&.publish(:council_feedback, entry)
            entry
          end
        end
        feedback = threads.map { |t| t.join(20) ? t.value : nil }.compact

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
end
```

## lib/master/council/personas.rb
```ruby
# frozen_string_literal: true


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
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",
           prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil advocate",
          bias: "Caution",    prompt: "Find what could go wrong. Challenge every assumption.",                veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",
           bias: "Shipping",   prompt: "Is this shippable? Flag over-engineering.",                            veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",
              prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",
              bias: "Usability",  prompt: "Does this serve the user? Are error messages actionable?",             veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",
              bias: "Clarity",    prompt: "Is this code readable? Do names reveal intent?",                       veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = Master.load_yaml(data_path, symbolize_names: true)
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
end
```

## lib/master/decision_engine.rb
```ruby
# frozen_string_literal: true

module Master
  # DecisionEngine — universal priority scorer.
  # Formula: (impact * confidence) / cost
  # Used by: ModelRouter (model selection), Heartbeat (job ordering),
  #          AutoLoop (file ordering), Swarm (worker result weighting).
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      ranked(candidates).first
    end

    def ranked(candidates)
      Array(candidates).map do |c|
        c = { value: c } unless c.is_a?(Hash)
        c.merge(de_score: score(
          impact:     c.fetch(:impact,     c.fetch("impact",     1.0)),
          confidence: c.fetch(:confidence, c.fetch("confidence", 1.0)),
          cost:       c.fetch(:cost,       c.fetch("cost",       1.0))
        ))
      end.sort_by { |c| -c[:de_score] }
    end

    def converged?(previous:, current:, min_delta: 0.001)
      return false if previous.nil?
      (current.to_f - previous.to_f).abs < min_delta.to_f
    end
  end
end
```

## lib/master/diff_stager.rb
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
      @mutex   = Mutex.new
      @pending = []
      @counter = 0
    end

    # Called by tools instead of writing directly. Returns a Result.
    def stage(path:, new_content:, tool: "unknown")
      old_content = File.exist?(path) ? File.read(path) : ""
      return Result.ok("no change") if old_content == new_content

      @mutex.synchronize do
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
      end
      persist_entry(entry)
      @bus&.publish("stage:queued", id: entry.id, path: entry.path, stats: entry.diff_stats)
      Result.ok({ staged: true, id: entry.id, path: entry.path, stats: entry.diff_stats })
    end

    def pending = @pending.dup
    def empty?  = @pending.empty?
    def size    = @pending.size

    # Apply one or all entries. Returns array of applied paths.
    def apply(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      applied = []
      targets.each do |entry|
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.new_content)
        @mutex.synchronize { @pending.delete(entry) }
        remove_persisted(entry)
        @bus&.publish("stage:applied", id: entry.id, path: entry.path)
        applied << entry.path
      end
      applied
    end

    # Discard one or all without writing.
    def discard(id: :all)
      targets = @mutex.synchronize { id == :all ? @pending.dup : @pending.select { |e| e.id == id } }
      targets.each do |entry|
        @mutex.synchronize { @pending.delete(entry) }
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
    rescue StandardError => e
      @bus&.publish("diff_stager:persist_error", error: e.message)
    end

    def remove_persisted(entry)
      persist_file = File.join(stage_dir, "#{entry.id}.json")
      # Safe to delete: this persisted staging file is being removed after the entry
      # has been either applied (written to the actual file) or discarded (abandoned).
      File.delete(persist_file) if File.exist?(persist_file)
    rescue StandardError => e
      @bus&.publish("diff_stager:cleanup_error", error: e.message)
    end
  end
end
```

## lib/master/event_bus.rb
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
      @pattern_cache.shift if @pattern_cache.size >= 512
        re = @pattern_cache[pattern] ||= Regexp.new(
        "\\A" + Regexp.escape(pattern).gsub('\\*\\*', '.*').gsub('\\*', '[^:]*') + "\\z"
      )
      re.match?(event)
    end
  end
end
```

## lib/master/gateway.rb
```ruby
# frozen_string_literal: true

module Master
  # Gateway -- multi-channel message router.
  # Core of the system; CLI/Web/IRC/Matrix/API are adapters registered here.
  # Each adapter implements render(text, metadata) for output delivery.
  class Gateway
    CHANNELS = %i[cli web irc matrix api].freeze

    # Contract for channel adapters.
    module Adapter
      def render(text, metadata = {})
        raise NotImplementedError, "#{self.class}#render not implemented"
      end
    end

    def initialize(pipeline:, session:, event_bus: nil)
      @pipeline = pipeline
      @session  = session
      @bus      = event_bus
      @adapters = {}
    end

    # Register an adapter (must respond to :render) or a bare Proc handler.
    def register(channel, adapter_or_proc = nil, &block)
      h = adapter_or_proc || block
      @adapters[channel.to_sym] = h
    end

    def receive(channel:, message:, metadata: {})
      channel = channel.to_sym
      return Result.err("unknown channel: #{channel}", category: :validation) unless CHANNELS.include?(channel)

      @bus&.publish("gateway:receive", channel: channel, size: message.bytesize)

      ctx = { user_message: message.to_s.strip, channel: channel, metadata: metadata }
      result = @pipeline.call(Result.ok(ctx))

      if (adapter = @adapters[channel])
        text = result.respond_to?(:ok?) && result.ok? ? extract_text(result) : result.to_s
        adapter.respond_to?(:render) ? adapter.render(text, metadata) : adapter.call(text, metadata)
      end

      result
    end

    def channels
      CHANNELS.map do |ch|
        status = @adapters.key?(ch) ? "active" : "available"
        "#{ch}: #{status}"
      end.join("
")
    end

    private

    def extract_text(result)
      val = result.value!
      val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
    rescue StandardError => e
      @bus&.publish("gateway:extract_error", error: e.message)
      result.to_s
    end
  end
end
```

## lib/master/git_operations.rb
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
end
```

## lib/master/governor.rb
```ruby
# frozen_string_literal: true

require "tty-prompt"

module Master
  class Governor
    RATE_WINDOW = 60.0
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
      when :deny    then @bus&.publish("tool:denied",
        tool: tool_name); Result.err("denied by user", category: :validation)
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

## lib/master/heartbeat.rb
```ruby
# frozen_string_literal: true

require "yaml"

module Master
  class Heartbeat
    POLL_INTERVAL = 60
    JOURNAL_KEEP = 50
    DATA_PATH  = File.join(Master::ROOT, "data", "heartbeat.yml").freeze
    STATE_PATH = ".master/heartbeat_state.yml".freeze

    JOB_HANDLERS = {
      "prune_memory" => :prune_memory,
      "check_models" => :check_model_availability,
      "self_test"    => :run_self_test,
      "prune_undo"   => :prune_undo_journal,
      "snapshot"     => :run_snapshot
    }.freeze

    def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil)
      @root    = root
      @agent   = agent
      @scanner = scanner
      @memory  = memory
      @bus     = event_bus
      @jobs    = load_jobs
      @state   = load_state
      @thread  = nil
      @stop    = false
    end

    def start!
      return if @jobs.empty?

      @stop   = false
      @thread = Thread.new do
        loop do
          break if @stop
          run_due!
          sleep POLL_INTERVAL
        end
      rescue StandardError => e
        @bus&.publish("heartbeat:error", message: e.message)
      end
    end

    def stop!
      @stop = true
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
      method_name = JOB_HANDLERS[job["action"]]
      return "unknown action: #{job["action"]}" unless method_name

      send(method_name)
    rescue StandardError => e
      "error: #{e.message}"
    end

    def prune_memory
      @memory&.consolidate!(agent: @agent) || "no memory"
    end

    def check_model_availability
      models_path = File.join(@root, "data", "models.yml")
      return "no models.yml" unless File.exist?(models_path)

      data = Master.load_yaml(models_path)
      tiers = data["models"] || {}
      ids = tiers.values.flatten.map { |m| m["id"] }.compact
      alive = ids.select { |id| model_reachable?(id) }
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

      count = result.value!.sum do |_, fr|
        fr.respond_to?(:ok?) && fr.ok? ? fr.value!.size : 0
      end
      @bus&.publish("heartbeat:self_test", violations: count)
      "self-test: #{count} violations"
    end

    def prune_undo_journal
      journal_path = File.join(@root, ".master", "undo.jsonl")
      return "no journal" unless File.exist?(journal_path)

      lines = File.readlines(journal_path)
      return "journal empty" if lines.empty?

      keep = [lines.size / 2, JOURNAL_KEEP].max
      File.write(journal_path, lines.last(keep).join)
      "pruned undo: kept #{keep}/#{lines.size} entries"
    end

    def run_snapshot
      container = { root: @root, bus: @bus }
      Builder.boot_snapshot(container)
      "snapshot: generated"
    end

    def load_jobs
      path = File.join(@root, "data", "heartbeat.yml")
      return default_jobs unless File.exist?(path)

      result = Master.load_yaml(path); result.is_a?(Array) ? result : default_jobs
    rescue StandardError
      default_jobs
    end

    def default_jobs
      [
        { "name" => "prune_memory", "action" => "prune_memory", "interval_seconds" => 3600 },
        { "name" => "self_test", "action" => "self_test", "interval_seconds" => 7200 },
        { "name" => "prune_undo", "action" => "prune_undo", "interval_seconds" => 86_400 },
        { "name" => "snapshot", "action" => "snapshot", "interval_seconds" => 14_400 }
      ]
    end

    def load_state
      path = File.join(@root, STATE_PATH)
      return {} unless File.exist?(path)

      Master.load_yaml(path) || {}
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

## lib/master/learnings.rb
```ruby
# frozen_string_literal: true

require "json"

module Master
  # Learnings — append-only cross-session procedural memory.
  # Episodic memory (conversation context) lives in Memory.
  # Procedural memory (fix strategies that worked) lives here.
  #
  # Schema per entry:
  #   trigger:    what situation prompted this (e.g. "NameError in Zeitwerk")
  #   strategy:   what worked (e.g. "check loader.ignore list for reopen files")
  #   outcome:    :fixed | :partial | :failed
  #   confidence: 0.0-1.0 (rises with reuse_count)
  #   reuse_count: times this entry was applied
  #   timestamp:  unix epoch
  class Learnings
    STORE_PATH = "data/learnings.jsonl"
    MAX_ENTRIES = 500
    CONFIDENCE_DECAY_DAYS = 30

    def initialize(root:)
      @path = File.join(root, STORE_PATH)
      @entries = load_entries
    end

    def record(trigger:, strategy:, outcome:)
      existing = @entries.find { |e| e["trigger"] == trigger.to_s && e["strategy"] == strategy.to_s }
      if existing
        existing["reuse_count"] = existing["reuse_count"].to_i + 1
        existing["confidence"]  = [existing["confidence"].to_f + 0.05, 1.0].min
        existing["outcome"]     = outcome.to_s
        existing["timestamp"]   = Time.now.to_i
      else
        @entries << {
          "trigger"     => trigger.to_s,
          "strategy"    => strategy.to_s,
          "outcome"     => outcome.to_s,
          "confidence"  => outcome == :fixed ? 0.7 : 0.4,
          "reuse_count" => 0,
          "timestamp"   => Time.now.to_i
        }
      end
      prune_old!
      persist
    end

    def search(trigger_fragment, limit: 3)
      fragment = trigger_fragment.to_s.downcase
      @entries
        .select { |e| e["trigger"].to_s.downcase.include?(fragment) && e["outcome"] != "failed" }
        .sort_by { |e| -e["confidence"].to_f }
        .first(limit)
    end

    def all = @entries.dup

    def prune_stale!
      cutoff = Time.now.to_i - (CONFIDENCE_DECAY_DAYS * 86_400)
      before = @entries.size
      @entries.reject! { |e| e["reuse_count"].to_i == 0 && e["timestamp"].to_i < cutoff }
      persist if @entries.size < before
    end

    private

    def load_entries
      return [] unless File.exist?(@path)
      File.readlines(@path, chomp: true)
          .map { |l| JSON.parse(l) rescue nil }
          .compact
    rescue StandardError
      []
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      tmp = ".tmp"
      File.write(tmp, @entries.map { |e| JSON.generate(e) }.join("\n") + "\n")
      File.rename(tmp, @path)
    end

    def prune_old!
      @entries = @entries.last(MAX_ENTRIES) if @entries.size > MAX_ENTRIES
    end
  end
end
```

## lib/master/logging.rb
```ruby
# frozen_string_literal: true

module Master
  class Logging
    DEFAULT_DMESG_LINES = 50
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:)
      @buffer      = ring_buffer
      @bus         = event_bus
      wire_events
    end

    def dmesg(lines = DEFAULT_DMESG_LINES)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event].to_s
      rest  = payload.except(:event, :ts)
      component, action = event.split(":", 2)
      action  ||= "ready"
      details   = rest.map { |k, v| "#{k}=#{v}" }.join(" ")
      details.empty? ? "#{component}: #{action}" : "#{component}: #{action} #{details}"
    end
  end
end
```

## lib/master/mcp_coordinator.rb
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
      data = Master.load_yaml(path) || {}
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

## lib/master/memory.rb
```ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"

require_relative "memory/search"

module Master
  # Memory — persistent cross-session store with TF-IDF semantic search.
  # Stored at .master/memory.yml. Survives restarts.
  class Memory
    TTL_DAYS = 90
    CONSOLIDATE_THRESHOLD = 40
    SECONDS_PER_DAY = 86_400
    MAX_INJECT_TOKENS = 2000
    MAX_INJECT_ENTRIES = 5

    include Search

    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @mutex = Mutex.new
      @store = load_store
    end

    def remember(key, value)
      @mutex.synchronize do
        prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
        @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
      end
      persist
    end

    def recall(key)
      @store.dig(key.to_s, "value")
    end

    def forget(key)
      @mutex.synchronize { @store.delete(key.to_s) }
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
        { key: key, value: value, score: 1.0 / (1.0 + age_d / TTL_DAYS.to_f) }
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
      cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
      @store.each do |k, v|
        next if k.to_s.start_with?("archive/") || k == "_consolidated_summary"
        ts = v.is_a?(Hash) ? v["ts"].to_i : 0
        next unless ts > 0 && ts < cutoff
        @store["archive/#{k}"] = @store.delete(k)
      end
    end

    def load_store
      return {} unless File.exist?(@path)
      loaded = Master.load_yaml(@path, symbolize_names: false); loaded.is_a?(Hash) ? loaded : {}
    rescue StandardError
      {}
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, @store.to_yaml)
    end

  end
end
```

## lib/master/memory/search.rb
```ruby
# frozen_string_literal: true

module Master
  class Memory
    module Search
      def semantic_recall(query, top_n: 3)
        return [] if @store.empty?

        query_terms = tokenize(query)
        return [] if query_terms.empty?

        scored = @store.filter_map do |key, data|
          value = data.is_a?(Hash) ? data["value"].to_s : data.to_s
          score = tfidf_score(query_terms, tokenize("#{key} #{value}"))
          next if score.zero?
          { key: key, value: value, score: score }
        end

        scored.sort_by { |e| -e[:score] }.first(top_n)
      end

      private

      def tokenize(text) = text.downcase.scan(/\b[a-z]{2,}\b/)

      def tfidf_score(query_terms, doc_terms)
        return 0.0 if doc_terms.empty?
        freq = doc_terms.tally
        query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
      end
    end
  end
end
```

## lib/master/metrics.rb
```ruby
# frozen_string_literal: true

require "json"

module Master
  class Metrics
    SLOW_REQUEST_MS = 5000
    METRICS_PREFIX = "metrics0".freeze
    DIFF_SIZE_LIMIT_DEFAULT = 200
    MAX_DIFF_SIZE_LIMIT = DIFF_SIZE_LIMIT_DEFAULT.freeze
    MAX_DIFF_SIZE_LINES = MAX_DIFF_SIZE_LIMIT.freeze
    ROLLBACK_RATE_THRESHOLD = 0.15
    DECISION_LATENCY_MS_THRESHOLD = 5000

    def initialize(root:, event_bus: nil)
      @path        = File.join(root, ".master", "metrics.jsonl")
      @bus         = event_bus
      @mutex       = Mutex.new
      @writes      = 0
      @undos       = 0
      @latencies   = []
      @diff_sizes  = []
      @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
      subscribe_to_bus(event_bus) if event_bus
    end

    def record_latency(ms)
      @mutex.synchronize { @latencies << ms }
      check_threshold(:decision_latency_ms, average(@latencies))
      append(decision_latency_ms: ms)
    end

    def record_diff(lines)
      @mutex.synchronize { @diff_sizes << lines; @writes += 1 }
      check_threshold(:diff_size_lines, average(@diff_sizes))
      append(diff_size_lines: lines)
    end

    def record_undo
      rate = @mutex.synchronize { @undos += 1; @writes > 0 ? @undos.to_f / @writes : 0.0 }
      check_threshold(:rollback_rate, rate)
      append(rollback_rate: rate.round(3))
    end

    # Called via llm:response EventBus subscription or directly.
    def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
      @mutex.synchronize do
        stats = @model_stats[model.to_s]
        stats[:calls]       += 1
        stats[:failures]    += 1 unless success
        stats[:escalations] += 1 if escalated
      end
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
      rescue StandardError => e
        @bus&.publish("metrics:record_error", error: e.message)
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
    rescue StandardError => e
      @bus&.publish("metrics:append_error", error: e.message)
    end
  end
end
```

## lib/master/personality.rb
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
    AXIOM_DISPLAY_LIMIT = 10

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
      phil = @axioms.philosophy(limit: AXIOM_DISPLAY_LIMIT)
      ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
      golden = constitution["golden_rule"]
      ls << "Rule: #{golden}." if golden

      # Hard formatting rules — [K] enforced
      ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**),
        no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
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

## lib/master/phase_gates.rb
```ruby
# frozen_string_literal: true

module Master
  # PhaseGates — 7-stage project planning FSM.
  # Governs session scope before implementation begins.
  # Distinct from execution pipeline (Intake->Render) and Standing Orders (UNCHANGE/REFACTOR).
  # Gates block phase advancement until conditions are met or user overrides.
  PHASES = %w[discover analyze ideate design implement validate deliver idle].freeze

  class PhaseGates
    STORE_PATH = "data/phase_state.yml"

    GATES = {
      "discover"  => %w[problem_stated success_measurable],
      "analyze"   => %w[components_distinct dependencies_noted],
      "ideate"    => %w[alternatives_gte_3],
      "design"    => %w[interfaces_noted errors_noted],
      "implement" => %w[],
      "validate"  => %w[tests_noted],
      "deliver"   => %w[deployed_noted],
      "idle"      => %w[]
    }.freeze

    def initialize(root:, event_bus: nil)
      @root  = root
      @bus   = event_bus
      @state = load_state
    end

    def current = @state["phase"] || "idle"

    def advance!(to: nil)
      target = to&.to_s || next_phase
      return Result.err("unknown phase: #{target}") unless PHASES.include?(target)

      unmet = unmet_gates(current)
      if unmet.any?
        return Result.err("phase #{current} gates unmet: #{unmet.join(",")} — override with /phase advance --force")
      end

      @state["phase"] = target
      @state["entered_at"] = Time.now.to_i
      persist
      @bus&.publish("phase:advanced", from: current, to: target)
      Result.ok("phase: #{current} -> #{target}")
    end

    def force!(phase)
      @state["phase"] = phase.to_s
      @state["entered_at"] = Time.now.to_i
      persist
      Result.ok("phase forced to #{phase}")
    end

    def meet_gate!(gate)
      @state["met_gates"] ||= []
      @state["met_gates"] |= [gate.to_s]
      persist
    end

    def status
      unmet = unmet_gates(current)
      met   = (@state["met_gates"] || []) & (GATES[current] || [])
      "phase=#{current} met=#{met.join(",")} unmet=#{unmet.join(",")}"
    end

    private

    def next_phase
      idx = PHASES.index(current) || 0
      PHASES[[idx + 1, PHASES.size - 1].min]
    end

    def unmet_gates(phase)
      required = GATES.fetch(phase, [])
      met = @state["met_gates"] || []
      required - met
    end

    def load_state
      path = File.join(@root, STORE_PATH)
      return { "phase" => "idle", "met_gates" => [] } unless File.exist?(path)
      data = Master.load_yaml(path)
      data.is_a?(Hash) ? data : { "phase" => "idle", "met_gates" => [] }
    rescue StandardError
      { "phase" => "idle", "met_gates" => [] }
    end

    def persist
      path = File.join(@root, STORE_PATH)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(@state))
    end
  end
end
```

## lib/master/pipeline.rb
```ruby
# frozen_string_literal: true

require "open3"

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


# Wraps a stage -- skips it transparently when ctx[:pressure] is truthy.
class SkipOnPressure
  def initialize(stage) = @stage = stage
  def call(ctx) = ctx[:pressure] ? Result.ok(ctx) : @stage.call(ctx)
end

    private

    def maybe_rollback(result)
      return unless result.respond_to?(:err?) && result.err?
      return unless ROLLBACK_CATEGORIES.include?(result.category)
      return unless @root && git_workspace?
      return unless dirty?

      @bus&.publish("pipeline:rollback", category: result.category, message: result.message[0, 120])
      system("git -C \#{@root} reset --hard HEAD > /dev/null 2>&1")
    end

    def git_workspace?
      @root && Dir.exist?(File.join(@root, ".git"))
    end

    def dirty?
      out, _, st = Open3.capture3("git", "-C", @root, "status", "--porcelain")
      st.success? && !out.strip.empty?
    end

    def stage_label(stage)
      stage.class.name.split("::").last
    end
  end
end
```

## lib/master/pledge.rb
```ruby
# frozen_string_literal: true

require "fiddle"

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      extend Fiddle::Importer
      dlload "libc.so"
      extern "int pledge(const char *, const char *)"
      extern "int unveil(const char *, const char *)"

      def pledge(promises, execpromises = nil)
        ep = execpromises ? Fiddle::Pointer[execpromises] : Fiddle::NULL
        result = self.__pledge(promises, ep)
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

    # Stage 1: called before Builder.build -- widest promises, no lock
    def stage1_boot!(root)
      pledge("stdio rpath wpath cpath proc exec inet dns tty unveil")
      unveil("/", "")
      unveil(root, "rwc")
      unveil(Dir.home, "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      unveil("/usr/local/lib", "r")
      unveil("/usr/local/share", "r")
      [Dir.home + "/.local/share/gem", Dir.home + "/.gem"].each { |p| unveil(p, "r") if Dir.exist?(p) }
      unveil("/dev/urandom", "r")
    end

    # Stage 2: called after CLI is fully initialized -- lock filesystem
    def stage2_lock!
      pledge("stdio rpath wpath cpath proc exec inet dns tty")
      lock_unveil!
    end

    # Stage 3: scan-only sessions (no network, no exec)
    def stage3_scan_only!
      pledge("stdio rpath wpath cpath tty")
      lock_unveil!
    end

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
  end
end
```

## lib/master/reasoning/modes.rb
```ruby
# frozen_string_literal: true


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
        Master.load_yaml(path) || {}
      end
    end
  end
end
```

## lib/master/reflexion.rb
```ruby
# frozen_string_literal: true

module Master
  # Reflexion — structured retry with critique.
  # Ref: arxiv:2511.03153 (RefAgent), arxiv:2503.14340 (MANTRA).
  #
  # Full loop: attempt → evaluate → critique (fast model) → revise → repeat.
  # Distinct from raw retry (append error + retry) — critique step names the flaw
  # before revision, which lifts pass rates from ~45% to ~90% per RefAgent.
  module Reflexion
    MAX_REFLECTIONS = 3

    module_function

    # Wrap a block with reflexion. Yields attempt number; block must return Result.
    # On non-ok result, generates critique and passes it back for next attempt.
    def run(agent:, task:, fast_model: nil, max: MAX_REFLECTIONS)
      last_result = nil
      last_critique = nil

      (max + 1).times do |i|
        prompt = i.zero? ? task : build_revision_prompt(task, last_result, last_critique)
        last_result = yield(prompt, i)
        return last_result if last_result.respond_to?(:ok?) && last_result.ok?

        break if i >= max
        last_critique = critique(agent:, task:, result: last_result, fast_model:)
      end

      last_result
    end

    def critique(agent:, task:, result:, fast_model: nil)
      prompt = <<~PROMPT
        Task: #{task.to_s[0, 400]}
        Attempt output: #{result.to_s[0, 400]}
        What specifically went wrong? Name the constraint violated. What must change in the next attempt? One paragraph, no preamble.
      PROMPT
      resp = fast_model ? agent.ask_once_with_model(prompt, model: fast_model) : agent.ask(prompt)
      resp.respond_to?(:value!) ? resp.value! : resp.to_s
    rescue StandardError
      "previous attempt failed — try a different approach"
    end

    def build_revision_prompt(task, previous_result, critique)
      <<~PROMPT
        #{task}

        Previous attempt failed.
        Critique: #{critique}
        Previous output: #{previous_result.to_s[0, 200]}

        Revise based on the critique. Return only the corrected result.
      PROMPT
    end
  end
end
```

## lib/master/renderer.rb
```ruby
# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

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
      t     = Time.now
      host  = Socket.gethostname rescue "openbsd"
      ruby  = RUBY_VERSION
      up    = uptime_str
      url   = @config["web_public_url"] || "https://ai.brgen.no"
      mod   = short_model(model)
      rev   = git_rev

      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << @p.bold.red("MASTER") + @p.dim(" constitutional AI agent")
      lines << @p.dim("hostname #{host}  ruby #{ruby}  #{t.strftime('%Y-%m-%d %H:%M:%S')}")
      lines << @p.dim("model    #{mod}")
      lines << @p.dim("web      #{url}")
      lines << @p.dim("rev      #{rev}") if rev
      lines << @p.dim("uptime   #{up}") if up
      lines << ""
      lines << @p.bold.red("master") + @p.dim("@#{host} ready -- type ") + @p.bright_red("help") + @p.dim(" for commands")
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
      @p.dim(line.to_s)
    end

    private

    def uptime_str
      out = `uptime 2>/dev/null`.strip
      out.empty? ? nil : out.split(",").first.gsub(/.*up\s+/, "").strip
    rescue StandardError
      nil
    end

    def git_rev
      out, _, st = Open3.capture3("git", "-C", @config["root"] || Dir.pwd, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end

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
end
```

## lib/master/result.rb
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

## lib/master/ring_buffer.rb
```ruby
# frozen_string_literal: true

module Master
  # Fixed-capacity circular buffer. Overwrites oldest entry when full.
  class RingBuffer
    include Enumerable
    include MonitorMixin

    def initialize(capacity)
      super()
      @capacity = capacity
      @buf      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      synchronize do
      idx = (@start + @size) % @capacity
      if @size < @capacity
        @buf[idx] = item
        @size += 1
      else
        @buf[@start] = item
        @start = (@start + 1) % @capacity
      end
      end
      self
    end

    alias << push

    def each
      return enum_for(__method__) unless block_given?
      synchronize { @size.times { |i| yield @buf[(@start + i) % @capacity] } }
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

## lib/master/routing/continuity_index.rb
```ruby
# frozen_string_literal: true


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
            Master.load_yaml(path) || {}
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

## lib/master/routing/model_router.rb
```ruby
# frozen_string_literal: true

module Master
  module Routing
    class ModelRouter
      UNCERTAINTY_PHRASES = [
        "i'm not sure", "i don't know", "cannot determine",
        "unclear", "uncertain", "might be", "possibly",
        "probably not", "limited information", "i cannot",
        "i am unable", "i lack the", "not enough information",
        "i would need more"
      ].freeze

      ESCALATION_CHAIN = %w[cheap default strong].freeze
      DEFAULT_THRESHOLD = 0.3

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

        pref = preferred(task_type:)
        all = @rules.fetch("models", {}).values.flatten.map { |m| m["id"] }.compact
        continuity = @continuity_index.fallback_models
        ([pref] + all + continuity + [@config.model]).uniq
      end

      def escalate?(response, threshold: DEFAULT_THRESHOLD)
        return false unless @rules.dig("routing", "escalation_enabled")

        text = response.to_s.downcase
        hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
        hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
      end

      def stronger_model(task_type: :exploration)
        tier = @rules.dig("routing", "escalation_tier") || "strong"
        candidates = @rules.dig("models", tier).to_a
        return preferred(task_type:) if candidates.empty?

        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred(task_type:)
      end

      def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
        return nil unless escalate?(response)

        strong_model = stronger_model(task_type:)
        return nil if current_model == strong_model

        strong_model
      end

      def tier_for_model(model_id)
        @rules.fetch("models", {}).each do |tier, models|
          return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
        end
        "cheap"
      end

      def next_escalation_tier(current_tier)
        idx = ESCALATION_CHAIN.index(current_tier.to_s)
        return nil unless idx

        ESCALATION_CHAIN[idx + 1]
      end

      def confidence_threshold(task_type: :exploration)
        route = @rules.dig("routes", task_type.to_s)
        return DEFAULT_THRESHOLD unless route.is_a?(Hash)

        route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
      end

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        weights = @rules.fetch("weights", {})
        qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
        sw = [weights.fetch("speed",   1.0).to_f, 0.01].max
        cw = [weights.fetch("cost",    1.0).to_f, 0.01].max
        DecisionEngine.score(
          impact:     score.fetch("quality", 0.5).to_f * qw,
          confidence: [score.fetch("speed", 1.0).to_f * sw, 0.01].max,
          cost:       1.0 / [score.fetch("cost", 0.5).to_f * cw, 0.001].max
        )
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        Master.load_yaml(path) || {}
      rescue StandardError
        {}
      end
    end
  end
end
```

## lib/master/ruby_llm_patch.rb
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

## lib/master/scan/rule.rb
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

## lib/master/scan/rules/adversarial_rule.rb
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

## lib/master/scan/rules/axiom_coverage_rule.rb
```ruby
# frozen_string_literal: true

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

          data = Master.load_yaml(path)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
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

## lib/master/scan/rules/bare_rescue_rule.rb
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

## lib/master/scan/rules/conceptual_rule.rb
```ruby
# frozen_string_literal: true


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
          data = Master.load_yaml(RULES_PATH)
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

## lib/master/scan/rules/cqs_rule.rb
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
              depth += line.scan(/^\s*(?:if|case|begin|do)\b|\bdo\s*(?:\|[^|]*\|)?\s*$|\bdef\s/).size
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

## lib/master/scan/rules/duplicate_code_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DuplicateCodeRule < Rule
        BLOCK_MIN  = 4
        OCCUR_MIN  = 3

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
              message: "duplicate block #{count} times — extract to shared method (ONE_SOURCE)"
            )
          end

          findings.first(5)
        end
      end
    end
  end
end
```

## lib/master/scan/rules/explicit_rule.rb
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
            next if line.match?(/^\s*[A-Z][A-Z_0-9]*\s*=/)  # skip constant defs
            findings << finding(line: num, message: "magic number — extract to a named constant")                if line.match?(MAGIC_NUM) && !line.strip.start_with?("#")
            findings << finding(line: num,
              message: "single-letter variable obscures intent — use a descriptive name") if line.match?(OPAQUE_VAR) && !in_loop_context?(code, num)
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

## lib/master/scan/rules/frozen_string_rule.rb
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

## lib/master/scan/rules/god_class_rule.rb
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

## lib/master/scan/rules/immutable_rule.rb
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

## lib/master/scan/rules/long_method_rule.rb
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

## lib/master/scan/rules/nielsen_rule.rb
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

## lib/master/scan/rules/pola_rule.rb
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
            findings << finding(line: num,
              message: "negative attribute name — name what it IS, not what it ISN'T") if line.match?(NEG_BOOL_ATTR)

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
                findings << finding(line: pred_line,
                  message: "predicate method (?) mutates state — predicates must only query, never mutate (POLA)")
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

## lib/master/scan/rules/prune_rule.rb
```ruby
# frozen_string_literal: true


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
            data = File.exist?(DATA_PATH) ? Master.load_yaml(DATA_PATH) : {}
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

## lib/master/scan/rules/reek_rule.rb
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
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
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
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
          []
        end
      end
    end
  end
end
```

## lib/master/scan/rules/rubocop_rule.rb
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
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
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
        rescue StandardError => e
          # degrade gracefully — external tool unavailable
          []
        end
      end
    end
  end
end
```

## lib/master/scan/rules/self_explaining_rule.rb
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

## lib/master/scan/rules/srp_rule.rb
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

## lib/master/scan/scanner.rb
```ruby
# frozen_string_literal: true

require "etc"

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
          data = Master.load_yaml(RULES_PATH)
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

## lib/master/security/injection_guard.rb
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

## lib/master/security/permissions.rb
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
        BLOCKLIST.any? { |b| command.downcase.include?(b.downcase) }
      end
    end
  end
end
```

## lib/master/semantic_cache.rb
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
      @root = File.join(root, ".master", "cache")
      @ttl  = ttl
      @bus  = event_bus
      @lru  = []
      @lock = Monitor.new
      Dir.mkdir(@root) unless Dir.exist?(@root)
    end

    def fetch(prompt, model, &blk)
      key  = cache_key(prompt, model)
      path = cache_path(key)

      @lock.synchronize do
        hit = read_entry(path)
        return(@bus&.publish("cache:hit", key:) || hit) if hit
      end

      @bus&.publish("cache:miss", key:)
      result = blk.call
      @lock.synchronize { write_entry(path, result, key) }
      result
    end

    def invalidate!(prompt, model)
      path = cache_path(cache_key(prompt, model))
      @lock.synchronize { File.delete(path) if File.exist?(path) }
    end

    def invalidate_all!
      @lock.synchronize do
        Dir.glob(File.join(@root, "*.json")).each { |f| File.delete(f) rescue Errno::ENOENT }
        @lru.clear
      end
    end

    def stats
      @lock.synchronize do
        files = Dir.glob(File.join(@root, "*.json"))
        bytes = files.sum { |f| File.exist?(f) ? File.size(f) : 0 }
        { entries: files.size, size_kb: (bytes / BYTES_PER_KB).round(1) }
      end
    end

    private

    def cache_key(prompt, model) = Digest::SHA256.hexdigest("#{prompt}::#{model}")
    def cache_path(key) = File.join(@root, "#{key}.json")

    def stale?(entry) = Time.now.to_i - entry[:ts] > @ttl

    def expire_entry!(path)
      @lru.delete(path)
      File.delete(path) rescue Errno::ENOENT
      nil
    end

    def drop_entry!(path)
      File.delete(path) rescue Errno::ENOENT
      @lru.delete(path)
      nil
    end

    def read_entry(path)
      return nil unless File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      return expire_entry!(path) if stale?(entry)
      promote_lru(path)
      entry[:value]
    rescue JSON::ParserError
      drop_entry!(path)
    end

    def write_entry(path, value, key)
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
      File.delete(oldest) rescue Errno::ENOENT
    end
  end
end
```

## lib/master/session.rb
```ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  class Session
    TOKENS_PER_CHAR  = 4
    SESSION_NAME_MAX = 40
    COSTS_MAX_BYTES  = 102_400     # 100 KB.freeze

    attr_reader :name, :messages, :cost, :phase, :snapshots

    def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
      @root       = root
      @budget_max = budget_max
      @req_max    = req_max
      @mutex      = Mutex.new
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
      @mutex.synchronize do
        @messages << msg
        @name ||= auto_name(content) if role == :user
      end
      msg
    end

    def record_cost(amount, model:, tokens:)
      entry = nil
      @mutex.synchronize do
        @cost += amount
        entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
      end
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
      begin
        data = JSON.parse(File.read(@path), symbolize_names: true)
      rescue JSON::ParserError, Errno::ENOENT
        data = {}
      end
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

## lib/master/skills.rb
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
    SKILLS_DIR = "skills".freeze

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

## lib/master/soul.rb
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

        Draft ONLY the minimal changes needed. Preserve the anti-simulation rule,
          golden rule, and voice character unchanged.
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

## lib/master/speech.rb
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


PULSE_SOCKET = "/tmp/pulse/native".freeze
PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze
PAPLAY_CANDIDATES = %w[
  /data/data/com.termux/files/usr/bin/paplay
  /usr/bin/paplay
  /usr/local/bin/paplay
].freeze
FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze
DIRECT_PLAYERS = %w[aucat mpv ffplay aplay].freeze

def play(audio_path)
  return false unless audio_path && File.exist?(audio_path)
  play_via_pulse(audio_path) || play_direct(audio_path)
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

## lib/master/stages/council.rb
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
        data = Master.load_yaml(PATTERNS_PATH)
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
        existing = File.exist?(EXEMPLARS_PATH) ? (Master.load_yaml(EXEMPLARS_PATH) || []) : []
        File.write(EXEMPLARS_PATH, YAML.dump(existing + [entry]))
      rescue StandardError => e
        @bus&.publish("council:exemplar_error", error: e.message)
      end
    end
  end
end
```

## lib/master/stages/execute.rb
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

## lib/master/stages/guard.rb
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

## lib/master/stages/infer.rb
```ruby
# frozen_string_literal: true


module Master
  module Stages
    # Infer — promote natural-language messages to :command intent.
    #
    # Runs after Intake. When intent is :llm, matches the message against
    # patterns loaded from data/infer_patterns.yml (single source of truth —
    # adding a new inferred command never requires a code change).
    class Infer
      # Heuristic task-type detection — used by ModelRouter for tiered model selection.
      PRESSURE_PATTERN = /\b(?:urgent|asap|immediately|critical|now|hurry|fast|quick(?:ly)?|emergency|sos)\b/i.freeze

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
            return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd,
              entry[:capture], m, msg)))
          end
        end

        pressure = msg.match?(PRESSURE_PATTERN)
        Result.ok(ctx.merge(task_type: infer_task_type(msg), pressure: pressure || ctx[:pressure]))
      end

      private

      # Returns { "sweep" => { regexes: [Regexp, ...], capture: "path" }, ... }
      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        data = Master.load_yaml(PATTERNS_PATH) || {}
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

## lib/master/stages/intake.rb
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
end
```

## lib/master/stages/lint.rb
```ruby
# frozen_string_literal: true

module Master
  module Stages
    # Lint — always runs. Scans written files AND code blocks in chat output.
    # Violations are collected; if autofix is possible, feeds them back to
    # the autoloop for correction.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil, root: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
        @root     = root
      end

      def call(ctx)
        findings = []

        # 1. Scan any files that were written during Execute
        paths = Array(ctx[:written_files]).filter_map { |p| File.exist?(p) ? p : nil }
        paths = [File.join(@root, "lib")] if paths.empty? && defined?(@root) && @root
        paths.each do |scan_path|
          next unless File.exist?(scan_path)
          if File.directory?(scan_path)
            result = @scanner.scan_dir(scan_path, depth: :standard)
            findings.concat(result.value!.flat_map { |_, r| r.respond_to?(:ok?) && r.ok? ? r.value! : [] }) if result.respond_to?(:ok?) && result.ok?
          elsif scan_path.end_with?(".rb")
            result = @scanner.scan(scan_path, depth: :standard)
            findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
          end
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
      rescue StandardError => e
        @bus&.publish("lint:scan_error", error: e.message)
        []
      end
    end
  end
end
```

## lib/master/stages/memo.rb
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

## lib/master/stages/prune.rb
```ruby
# frozen_string_literal: true


module Master
  module Stages
    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
    class Prune
      RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      HEADER_RE     = %r{^\#{1,6}\s+}.freeze
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
          data = File.exist?(RULES_PATH) ? Master.load_yaml(RULES_PATH) : {}
          data.dig("voice", "strunk") || {}
        end
      rescue StandardError
        @rules = {}
      end
    end
  end
end
```

## lib/master/stages/render.rb
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

## lib/master/stages/route.rb
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

## lib/master/standing_orders.rb
```ruby
# frozen_string_literal: true

module Master
  class StandingOrders
    DAILY_INTERVAL  = 86_400
    WEEKLY_INTERVAL = 604_800
    STORE_PATH      = File.join(Master::ROOT, "data", "standing_orders.yml")
    VALID_STATES    = %w[pending running done error].freeze

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
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["state"] = "pending"
      order.delete("last_error")
      persist
      "'#{name}' reset -> pending"
    end

    def list
      return "no standing orders defined" if @orders.empty?
      @orders.map do |o|
        st   = state_of(o)
        flag = o["enabled"] ? "on" : "off"
        last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
        err  = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
        "#{o['name']} [#{flag}|#{st}] - #{o['description']} (last: #{last})#{err}"
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

    def toggle(name, enabled)
      order = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless order
      order["enabled"] = enabled
      persist
      "#{name} #{enabled ? 'enabled' : 'disabled'}"
    end

    def load_orders
      if File.exist?(STORE_PATH)
        orders = Master.load_yaml(STORE_PATH)
        unless orders.is_a?(Array)
          @bus&.publish("standing_orders:corrupt", path: STORE_PATH, got: orders.class.name)
          return builtin_orders
        end
        orders.select { |o| o.is_a?(Hash) }.each { |o| o["state"] ||= "done" }
      else
        builtin_orders
      end
    rescue Psych::Exception, Errno::ENOENT, TypeError, NoMethodError => e
      @bus&.publish("standing_orders:load_error", error: e.message)
      builtin_orders
    end

    def builtin_orders
      BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0, "state" => "pending") }
    end

    def persist
      return unless @orders.is_a?(Array)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(STORE_PATH))
      File.write(STORE_PATH, YAML.dump(@orders))
    end
  end
end
```

## lib/master/swarm/coordinator.rb
```ruby
# frozen_string_literal: true

require "timeout"

module Master
  module Swarm
    class Coordinator
      SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, keyword_init: true) do
        def ok?      = verdict != :error
        def approved? = verdict == :approved
      end

      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      WORKER_TIMEOUT = 30
      SHARED_DEADLINE = 60
      SYNTHESIS_TRUNCATE_LIMIT = 200

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

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
            th.kill rescue nil
            [:timeout, Result.err("worker timed out after #{timeout}s")]
          end
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                      synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok(sr)
      end

      def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error
            [t[:role], Result.err("worker exceeded shared deadline")]
          end
        end

        results = threads.map do |th|
          th.join(deadline)&.value || [nil, Result.err("join timeout")]
        end.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
        Result.ok(sr)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def build_swarm_result(results)
        successes = results.reject { |role, _| role == :timeout }
                           .select { |_, r| r.respond_to?(:ok?) && r.ok? }
        artifacts = successes.transform_values(&:value!)
        confidence = results.empty? ? 0.0 : successes.size.to_f / results.size
        lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
        reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")
        verdict = if confidence >= 0.8 then :approved
                 elsif confidence >= 0.5 then :mixed
                 elsif successes.empty? then :error
                 else :rejected
                 end
        SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:)
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

## lib/master/swarm/worker.rb
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
        @result, @confidence = parse_result(raw)

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
  conf = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
  [Result.ok({ text: text, confidence: conf }), conf]
end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k.to_s}: #{v.to_s}" }.join("\n")
      end
    end
  end
end
```

## lib/master/swarm/workers/analyst.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Reads code, produces structured analysis. Knows nothing about other workers.
      class Analyst < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
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

## lib/master/swarm/workers/coder.rb
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

## lib/master/swarm/workers/researcher.rb
```ruby
# frozen_string_literal: true

module Master
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
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

## lib/master/swarm/workers/reviewer.rb
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

## lib/master/sweep.rb
```ruby
# frozen_string_literal: true

require "open3"
require "tempfile"
require "set"
require_relative "sweep/rewriter"
require_relative "sweep/convergence"


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
    RENAME_WINDOW      = 3      # oscillation detected if A→B→A within 3 cycles.freeze
    TRAJECTORY_GAMMA   = 0.9    # γ for discounted improvement signal.freeze

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
      ".yml" => ->(p) { begin; Master.load_yaml(p); true; rescue => _e; false; end },
      ".erb" => ->(p) { begin; ERB.new(File.read(p)).result(binding); true; rescue SyntaxError; false; rescue => _e; true; end }
    }.freeze

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

    ERROR_PATTERNS = /
      \b(?:error|exception|traceback|failed|cannot|unable\sto|
      undefined\smethod|no\smethod|syntax\serror|
      internal\sserver|rate\slimit|quota\sexceeded|
      apologize|as\san\sai|i\scannot|i\sam\sunable|
circuit\sopen|retry\sin|llm_request)\b
    /ix.freeze

    PROMPTS_PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze

    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /\b(?:def\s+(\w+)|class\s+([A-Z]\w*)|[A-Z][A-Z_]+)\b/.freeze

    include Rewriter
    include Convergence

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
  end
end
```

## lib/master/sweep/convergence.rb
```ruby
# frozen_string_literal: true

module Master
  class Sweep
    module Convergence
      private

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        removed_now = extract_names(old_src) - extract_names(new_src)
        added_now   = extract_names(new_src) - extract_names(old_src)
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |e|
          (e[:removed] & added_now).any? && (e[:added] & removed_now).any?
        }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < CONVERGE_THRESHOLD
      end

      # γ-discounted improvement signal. Stalled when weighted sum ≈ 0.
      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        v = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, i| d * (TRAJECTORY_GAMMA**i) }
        v.abs < 1.0
      end

      def commit(msg)
        Dir.chdir(@root) do
          system("git add -A 2>/dev/null")
          system("git commit -m #{msg} 2>/dev/null")
        end
      end

      def git_dirty?
        out, = Open3.capture3("git -C #{@root} status --porcelain")
        !out.strip.empty?
      end
    end
  end
end
```

## lib/master/sweep/rewriter.rb
```ruby
# frozen_string_literal: true

require "tempfile"

module Master
  class Sweep
    module Rewriter
      private

      def load_prompts = Master.load_yaml(PROMPTS_PATH)

      def build_codebase_map
        files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                   .reject { |f| f.include?("/vendor/") }
                   .map    { |f| f.delete_prefix("#{@root}/") }
                   .sort
        "## Codebase (#{files.size} Ruby files)\n" +
          files.map { |f| "  #{f}" }.join("\n")
      end

      def collect_files(dir, types)
        types.flat_map { |t| Dir.glob(File.join(dir, GLOBS[t].to_s)) }
             .reject { |f| f.include?("/data/") }
             .uniq.sort
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
        return nil if text.bytesize < 500 && ERROR_PATTERNS.match?(text)
        fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?\n(.*?)```/m
        return text.match(fence_re)[1]         if text.match?(fence_re)
        return text.match(/```\n(.*?)```/m)[1] if text.match?(/```\n(.*?)```/m)
        text.strip.empty? ? nil : text
      end

      def syntax_ok?(path, content)
        checker = SYNTAX_CHECKERS[File.extname(path)]
        return true unless checker
        Tempfile.open(["sweep", File.extname(path)]) do |f|
          f.write(content); f.flush; checker.call(f.path)
        end
      end

      def violations_in(path)
        return 0 unless path.end_with?(".rb") && File.exist?(path)
        scan_result = @scanner.scan(path, depth: :deep)
        scan_result.ok? ? scan_result.value!.size : 0
      rescue StandardError
        0
      end

      def violations_in_text(content, ref_path)
        return 0 unless ref_path.end_with?(".rb")
        Tempfile.open(["vcheck", ".rb"]) do |f|
          f.write(content); f.flush
          scan_result = @scanner.scan(f.path, depth: :deep)
          scan_result.ok? ? scan_result.value!.size : 0
        end
      rescue StandardError
        0
      end
    end
  end
end
```

## lib/master/text_hygiene.rb
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

## lib/master/tools/ask_llm.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AskLlm — delegate sub-questions to the LLM agent mid-pipeline.
    class AskLlm
      TIER        = :guarded
      NAME        = "ask_llm".freeze
      DESCRIPTION = "Ask the LLM a sub-question and return the answer as a string.".freeze

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

## lib/master/tools/ast_edit.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # AST-aware editing tool using Ruby's Ripper (stdlib) for parsing.
    # Supports: find_method, rename_method, extract_lines_to_method, add_after_method.
    # Uses Ripper::SexpBuilder for structure-awareness without external gem dependencies.
    class AstEdit
      TIER        = :guarded
      NAME        = "ast_edit".freeze
      DESCRIPTION = "AST-aware code editing: find, rename, or restructure Ruby methods safely.".freeze

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

## lib/master/tools/batch_replace.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # BatchReplace — apply multiple search-and-replace operations in one pass.
    class BatchReplace
      TIER        = :guarded
      NAME        = "replace".freeze
      DESCRIPTION = "Find and replace text across all files in a directory.".freeze

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

## lib/master/tools/clean.rb
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

## lib/master/tools/git_context.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # Git context tool — query history, blame, diff, and status.
    # All commands are read-only (TIER :safe). No writes.
    class GitContext
      TIER        = :safe
      NAME        = "git_context".freeze
      DESCRIPTION = "Query git log, blame, diff, and status for the project.".freeze

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
        return Result.err("git_context blame: file not found: #{path}",
          category: :validation) unless File.exist?(File.join(@root, safe))
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

## lib/master/tools/list_dir.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # ListDir — list directory contents with filtering and depth control.
    class ListDir
      TIER        = :safe
      NAME        = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
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

## lib/master/tools/llm.rb
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
        description "Search the local knowledge base: ruby_llm docs, OpenBSD man pages, system prompts, gem docs. Topics: ruby_llm,
          openbsd, system_prompts, gems, awesome."
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

## lib/master/tools/path_guard.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    module PathGuard
      SACRED_PATHS = %w[data/ SOUL.md CLAUDE.md .claude/].freeze

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)

        rel = full.delete_prefix(@root + "/")
        if sacred?(rel)
          return Result.err(
            "#{rel} is sacred-tier (constitutional). Amend via `soul propose`.",
            category: :validation
          )
        end

        Result.ok(full)
      end

      private

      def sacred?(rel_path)
        SACRED_PATHS.any? { |s| rel_path.start_with?(s) || rel_path == s.chomp("/") }
      end
    end
  end
end
```

## lib/master/tools/read_file.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
        include PathGuard
      TIER        = :safe
      MAX_LINES   = 2000
      NAME        = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers. Guarded to project root.".freeze

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

## lib/master/tools/search_files.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # SearchFiles — regex search across project files with context lines.
    class SearchFiles
      TIER        = :safe
      NAME        = "search_files".freeze
      DESCRIPTION = "Search for a pattern in files under the project root.".freeze
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

## lib/master/tools/search_knowledge.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # Search the local knowledge base: cloned docs, man pages, system prompts, gem READMEs.
    class SearchKnowledge
      TIER        = :safe
      NAME        = "search_knowledge".freeze
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
        unless Dir.exist?(search_dir) && File.realpath(search_dir).start_with?(@knowledge_root)
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

## lib/master/tools/shell.rb
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
      NAME        = "zsh".freeze
      DESCRIPTION = "Execute a zsh command in the project root.".freeze
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

## lib/master/tools/str_replace.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # StrReplace — surgical string replacement in files with undo support.
    class StrReplace
        include PathGuard
      TIER        = :guarded
      NAME        = "str_replace".freeze
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times.".freeze

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

## lib/master/tools/symbol_lookup.rb
```ruby
# frozen_string_literal: true

module Master
  module Tools
    # SymbolLookup — lets the LLM query the live codebase symbol graph.
    # Returns definition location, callers, and impact analysis for any symbol.
    class SymbolLookup
      NAME        = "symbol_lookup".freeze
      DESCRIPTION = "Look up a Ruby class, module, or method in the codebase. " \
                    "Returns file, line, and all cross-file references (callers/usages). " \
                    "Use before refactoring to understand impact.".freeze
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

## lib/master/tools/tree.rb
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

## lib/master/tools/web_search.rb
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

      NAME        = "web_search".freeze
      DESCRIPTION = "Search DuckDuckGo instant answers API.".freeze
      ENDPOINT    = "https://api.duckduckgo.com/".freeze
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

## lib/master/tools/write_file.rb
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    # WriteFile — create or overwrite files with TextHygiene normalization.
    class WriteFile
        include PathGuard
      TIER        = :guarded
      NAME        = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot.".freeze

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

## lib/master/triggers.rb
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

## lib/master/undo.rb
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
    rescue StandardError => e
      @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
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

## lib/master/unwrap_error.rb
```ruby
# frozen_string_literal: true

module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end
end
```
