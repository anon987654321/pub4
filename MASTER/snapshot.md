# MASTER — Architecture Snapshot
# 2026-04-24T00:48:05Z
# Ruby constitutional AI coding agent. OpenBSD VPS. ~6K LOC core.

## `CLAUDE.md`
```md
# Disable host‑key checking only when you trust the network.
# Prefer a dedicated SSH key pair and configure it in ~/.ssh/config
# rather than embedding passwords in scripts.
set -euo pipefail
ssh -i ~/.ssh/id_rsa_brgen \
    -o StrictHostKeyChecking=no \
    dev@brgen.no \
    -- 'cmd'
```

## `Gemfile`
```rb
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

## `data/axioms.yml`
```yml
# Kernel axioms— enforced by scan rules, pipeline stages, or tool guards
kernel:
  PRESERVE_FIRST: "Never break working code; read before write."
  SIMPLEST_WORKS: "Use fewest moving parts that solve the problem."
  FAIL_VISIBLY: "Surface errors immediately; never swallow exceptions."
  ONE_SOURCE: "One authoritative representation per concept."
  DECOUPLE: "Make hidden dependencies explicit."
  GUARD_EXPENSIVE: "Check preconditions before costly work."
  DEGRADE_GRACEFULLY: "Operate under partial failures."
  BE_CONCISE: "Avoid unnecessary words, tokens, or lines."
# Philosophy layer [P] — advisory only, never blocking.
philosophy:
  prioritized_top_25:
    - id: ONE_JOB
      priority: 1
      statement: "Each module has one clear reason to change."
    - id: NO_SURPRISES
      priority: 2
      statement: "Prefer predictable behavior over clever behavior."
    - id: EXTEND_DONT_MODIFY
      priority: 3
      statement: "Add capability via composition before rewriting stable parts."
    - id: COMPOSABLE
      priority: 4
      statement: "Build small pieces that combine cleanly."
    - id: LEAVE_BETTER
      priority: 5
      statement: "Leave touched code cleaner than found."
    - id: TEST_FIRST
      priority: 6
      statement: "Design for testability before implementation complexity."
    - id: REVERSIBLE
      priority: 7
      statement: "Prefer steps that are easy to roll back."
    - id: ONE_CHANGE
      priority: 8
      statement: "Keep each patch focused on one coherent intent."
    - id: EXPLICIT
      priority: 9
      statement: "Prefer explicit contracts over implicit coupling."
    - id: IDEMPOTENT
      priority: 10
      statement: "Operations should be safe to repeat."
    - id: CQS
      priority: 11
      statement: "Separate queries from state mutations."
    - id: IMMUTABLE
      priority: 12
      statement: "Default to immutable data flow where practical."
    - id: APPEND_ONLY
      priority: 13
      statement: "Favor append‑only logs for auditability."
    - id: CACHE_FIRST
      priority: 14
      statement: "Cache high‑cost deterministic work with bounded TTL."
    - id: SELF_EXPLAINING
      priority: 15
      statement: "Names and structure should reduce need for comments."
    - id: ACCESSIBLE_FIRST
      priority: 16
      statement: "Design outputs for broad readability and accessibility."
    - id: SQUINT_TEST
      priority: 17
      statement: "Structure should be evident at a glance."
    - id: JUST_ENOUGH
      priority: 18
      statement: "Avoid overbuilding before proof of need."
    - id: CHESTERTONS_FENCE
      priority: 19
      statement: "Understand why something exists before removing it."
    - id: GALLS_LAW
      priority: 20
      statement: "Complex systems evolve from simple working systems."
    - id: OCCAMS_RAZOR
      priority: 21
      statement: "Prefer simpler hypotheses and designs first."
    - id: PARETO
      priority: 22
      statement: "Ship the 20 % that delivers 80 % value first."
    - id: FINISH_FIRST
      priority: 23
      statement: "Close the loop before opening new threads."
    - id: MEASURE_THEN_OPTIMIZE
      priority: 24
      statement: "Benchmark before optimization work."
    - id: BLAME_SELF
      priority: 25
      statement: "Assume your change introduced the bug until disproven."
  anti_patterns:
    - god_class
    - shotgun_surgery
    - speculative_abstraction
    - hidden_global_state
    - duplicate_logic
    - n_plus_one_queries
    - silent_rescue
    - temporal_coupling
  zen_method:
    observe: "Read current behavior before changing anything."
    simplify: "Reduce moving parts before adding new components."
    isolate: "Change one axis at a time with clear boundaries."
    verify: "Run checks and gather objective evidence."
    reflect: "Capture learning and improve defaults."
  strunk_white:
    - "Omit needless words."
    - "Use definite, specific, concrete language."
    - "Put statements in positive form."
    - "Use active voice by default."
  inverted_pyramid:
    - "Lead with the outcome."
    - "Provide key evidence next."
    - "Add implementation detail last."
  rails_doctrine:
    - "Convention over configuration"
    - "Optimize for programmer happiness"
    - "The menu is omakase"
    - "Value integrated systems"
# Nielsen Norman Group — 10 Usability Heuristics
ux:
  nielsen_heuristics:
    - id: SYSTEM_STATUS
      priority: 1
      statement: "Keep users informed of progress with timely feedback."
    - id: REAL_WORLD_MATCH
      priority: 2
      statement: "Speak the user's language; match their mental model."
    - id: USER_CONTROL
      priority: 3
      statement: "Support undo and emergency exits; users make mistakes."
    - id: CONSISTENCY
      priority: 4
      statement: "Follow conventions; same term means same thing everywhere."
    - id: ERROR_PREVENTION
      priority: 5
      statement: "Design to prevent problems; confirm destructive actions."
    - id: RECOGNITION_NOT_RECALL
      priority: 6
      statement: "Minimize memory load; make options visible."
    - id: FLEXIBILITY
      priority: 7
      statement: "Serve novices and experts; provide accelerators."
    - id: AESTHETIC_MINIMALISM
      priority: 8
      statement: "Show only relevant information; each element must earn its place."
    - id: ERROR_RECOVERY
      priority: 9
      statement: "Error messages must name the problem and suggest a fix."
    - id: HELP_AND_DOCS
      priority: 10
      statement: "Make help easy to find, concrete, and task‑focused."
# Clean Code — Robert C. Martin
clean_code:
  - id: ONE_ABSTRACTION_LEVEL
    statement: "Each function operates at one abstraction level; no mixing high‑level policy with low‑level detail."
  - id: STEPDOWN_RULE
    statement: "Functions call only functions one level below them."
  - id: BOUNDARY_ISOLATION
    statement: "Wrap third‑party code at the edge; keep it from leaking."
  - id: CLEAN_TESTS
    statement: "Treat tests as first‑class code; isolate them from production logic."
  - id: NO_MAGIC
    statement: "Eliminate unexplained constants, flags, or mode switches."
# Refactoring — Martin Fowler
refactoring_smells:
  - id: PRIMITIVE_OBSESSION
    statement: "Replace repeated primitives with value objects."
  - id: MESSAGE_CHAIN
    statement: "Avoid a.b.c.d chains; talk only to immediate collaborators."
  - id: MIDDLE_MAN
    statement: "Eliminate classes that delegate most methods to another."
  - id: LAZY_CLASS
    statement: "Remove classes too small to justify their existence."
  - id: TEMP_FIELD
    statement: "Extract instance variables set in some paths into a new object."
  - id: DIVERGENT_CHANGE
    statement: "Split classes changed for unrelated reasons."
  - id: SHOTGUN_SURGERY
    statement: "One conceptual change spanning many files signals missing abstraction."
  - id: INAPPROPRIATE_INTIMACY
    statement: "Do not access another class's private data; enforce boundaries."
  - id: ALTERNATIVE_CLASSES
    statement: "Unify classes that perform the same function under different names."
  - id: SPECULATIVE_GENERALITY
    statement: "Remove code written for hypothetical needs that is never used."
```

## `data/constitution.yml`
```yml
protection_levels:
  ABSOLUTE: "Abort pipeline"
  PROTECTED: "Emit warning, continue"
  NEGOTIABLE: "Allow if explicitly permitted"
  FLEXIBLE: "Negotiate at runtime"
golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
anti_simulation:
  forbidden_claims:
    - will
    - would
    - could
    - might
  required_evidence:
    file_read: "show file content with SHA‑256"
    modification: "show unified diff"
    completion: "show command output"
communication_style: openbsd_dmesg
banned_output:
  - headlines
  - section_markers
  - bullet_lists_without_content
  - filler_phrases
  - hedging
  - sycophancy
preserve:
  boot_message:
    format: "5‑line OpenBSD dmesg"
    reason: "Diagnostic trace"
    never: "single cryptic line"
  diagnostic_output:
    rule: "Structured multi‑line output"
    never: "compressed abbreviations"
  help_text:
    rule: "Scannable, complete"
    minimum_info:
      - "Command name and syntax"
      - "Brief description"
      - "At least one usage example"
  polish_rules:
    - "'Streamline' removes redundancy, never essential information"
    - "'Polish' refines wording without deleting output"
    - "'Minimize' applies to prompt tokens, not to diagnostic output"
```

## `data/council.yml`
```yml
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

## `data/council_patterns.yml`
```yml
# Patterns that auto‑trigger Council deliberation.
# Loaded as Regexp at runtime – keep them plain strings.
# Each entry is a Ruby‑style regex pattern; the leading  and trailing 
# ensure whole‑word matches where appropriate.
# Anchors are reused via YAML anchors for readability.
common: &common
  - 'evals+('
  - 'execs+('
  - 'systems+('
dangerous:
  - *common
  - 'rms+-rf'
  - 'sudo'
  - '(?:drop|truncate)s+table'
  - 'chmods+777'
  - '(?:delete|remove)s+all'
  - 'opens*(s*[''"][|]'                         # suspicious file open with pipe
  - '(popen|spawn)s*('                           # process creation shortcuts
  - '(fork|execve?)'                              # low‑level process forks
  - 'base64s+decode'                            # potential data exfiltration
  - '(base64|binhex)s+decode'                   # duplicate safety net
  - 'openssls+encs+-d'                         # decryption shortcuts
  - '(gzip|gunzip)s+-d'                         # decompression that may hide payloads
  - '(base64|urlencode)s+decode'                # double‑decode attacks
  - 'crontabs+-[eE]'                            # schedule manipulation
  - 'iptabless+-[FI]'                           # firewall rule changes
  - 'semanages+fcontext'                        # SELinux label changes
  - '(systemctl|service)s+(stop|restart|disable)' # service disruption
  - '(rm|unlink)s+--no-preserve-root'           # aggressive deletes
  - 'dds+if=.*s+of=.*s+bs=.*s+count=.*'       # raw disk ops
  - '(mkfs|fdisk|parted)'                        # filesystem manipulation
  - 'chattrs+[-+]i'                             # immutable attribute toggling
  - '(setfacl|getfacl)'                          # ACL abuse
  - '(chcon|restorecon)'                         # SELinux context changes
  - 'securitylimits'                             # limits.conf editing
  - 'passwds+-[dl]'                             # password lock/unlock
  - '(yum|apt|dnf|pacman)s+.*'                  # package manager abuse
  - 'pips+installs+--upgrade'                  # python package escalation
  - 'rubys+gems+installs+--pre'               # ruby gem pre‑release install
  - 'npms+installs+-g'                         # global node modules
  - 'sudos+-[S]'                                # sudo without password prompt
  - 'sus+-s*root'                              # direct root switch
  - '(wget|curl)s+.*s+-Os+/w+'               # download to root
  - '(tars+.*s+--wildcards)'                   # tar extraction with wildcards
  - '(zip|unzip)s+.*s+-ds+/w+'               # archive extraction to root
  - '(pg_dump|mysqldump)'                        # database dumps
  - 'sqlite3s+.*s+.dump'                      # sqlite dump
  - '(ssh|scp)s+.*s+@.*'                        # remote command execution
  - '(netcat|nc)s+.*'                           # raw socket commands
  - '(lsof|fuser)'                               # process/file descriptor probing
  - '(strace|ltrace|gdb)'                        # tracing/debugging utilities
  - 'dockers+runs+--rm'                        # container escape attempts
  - 'kubectls+exec'                             # k8s pod exec
  - 'crontabs+-[lr]'                            # crontab listing/modifying
  - 'at'                                         # at jobs
  - 'powershells+-Command'                      # cross‑platform shell
  - 'wmics+.*'                                  # Windows management
  - 'regs+add'                                  # registry edits
  - 'netshs+firewall'                           # Windows firewall
  - 'scs+config'                                # Windows service config
  - '(setx|set)'                                 # environment variable changes
  - 'exports+[^=]+=.*'                          # shell env changes
  - 'envs+.*'                                   # env command misuse
  - '(bash|zsh|ksh|sh)s+-c'                     # nested shells
  - '(python|perl|ruby|node)s+-e'               # language exec
  - 'javas+-jar'                                # java jar execution
  - 'javacs+.*'                                 # compile on the fly
  - 'gits+(pushs+--force|remotes+add|checkouts+-b|resets+--hard|rebases+-i|pushs+origins+HEAD:refs/heads/.*|pushs+--tags|clones+--depth|fetchs+--all|pulls+--all|remotes+set-url|configs+--global|configs+--system|lfs|submodule|rev-parse|merge|reflog|show|diff|status|log|checkout|add|commit|branch|tag|fetch|pull|push|remote|init|clone|config)'
  - 'greps+--binary-files=without-match'        # binary grep avoidance
  - 'seds+-n'                                   # selective sed
  - 'awk'                                              # awk command
  - 'tails+-f'                                  # log following
  - 'heads+-n'                                  # head count
  - 'curls+.*s+(-Xs+DELETE|-os+/.+)'          # HTTP delete / write to root
  - 'wgets+.*s+(--method=DELETE|--output-document=/.+)' # HTTP delete / write to root
  - 'scps+.*s+/w+'                            # copy to root
  - 'rsyncs+.*s+/w+'                          # sync to root
  - '(chown|chgrp)s+.*s+/w+'                  # ownership changes on root files
  - 'lns+-sfs+.*s+/w+'                       # symlink overwrite
  - '(mv|cp)s+.*s+/w+'                        # move/copy to root
  - '(distrobox|toolbox|podman|docker)s+run'    # container escape
  - '(lxc-exec|lxc-attach)'                    # LXC exec
  - 'virshs+console'                            # libvirt console
  - 'qemu-system-x86_64'                       # qemu VM launch
  - 'vboxmanages+startvm'                       # VirtualBox start
  - 'sshs+-os+(StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|BatchMode=yes)' # host key bypass
  - 'sshs+-[LFRDNT]s+.*'                       # port forwarding / tunnel options
  - 'socats+.*'                                 # socket proxy
  - 'mitmproxys+.*'                             # MITM proxy
  - 'tunnels+.*'                               # TLS tunnel
  - 'iptabless+-[F]'                            # flush iptables
  - 'nfts+flushs+table'                        # nftables flush
  - 'ufws+disable'                              # ufw disable
  - 'firewallds+stop'                           # firewalld stop
  - 'systemctls+(mask|disable|stop|halt)'       # service control
  - '(poweroff|reboot|shutdowns+-[hr])'          # power actions
  - 'mounts+-os+remount,rw'                    # remount read‑write
  - 'umounts+.*'                                # unmount
  - '(fuser|pkill|killall|kill)s+.*'             # kill commands
  - '(pkill|killall)s+--signals+9'             # force kill
  - '(strace|ltrace|gdb)s+-p'                   # attach debugger/trace
  - '(lsof|netstat|ss)s+.*'                     # socket/process inspection
  - '(ps|top|htop|w|whoami)'                    # system info commands
  - '(id|groups)'                                # identity commands
  - '(set|shopt)s+-(e|u|os+pipefail|ss+(nullglob|dotglob|extglob))' # strict shell options
  - '(bash|zsh|ksh|sh)s+-os+(errexit|pipefail|noclobber|noglob)' # bash options
  - 'finds+/.*s+-types+(fs+-execs+rms+-fs+{}s+;|ds+-execs+rmdirs+{}s+;)' # mass delete/dir removal
  - '(tar|zcat|gunzip|bzip2|xz|zip|unzip)s+.*s+>s+/dev/null' # discard output
  - 'pipefail'                                   # set -o pipefail
  - 'sets+-(e|u|os+pipefail)'                  # exit on error, undefined var, pipefail
  - 'shopts+-(ss+(nullglob|dotglob|extglob))'  # globbing options
  - '(bash)s+-os+(errexit|pipefail|noclobber|noglob)' # bash errexit etc.
```

## `data/exemplars.yml`
```yml
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

## `data/fallback_models.yml`
```yml
continuity:
  enabled: true
  updated_at: "2026-03-11T00:00:00Z"
openrouter:
  free_latest:
    - deepseek/deepseek-r1-0528:free
    - qwen/qwen3-coder:free
    - openai/gpt-oss-120b:free
ferrum_web_chat:
  free_latest:
    - ferrum:webchat:openrouter/free
```

## `data/features.yml`
```yml
modules:
  web_ui:
    enabled: true
    framework: rack
    assets:
      favicon: data/web/favicon.svg
    notes: |
      Interactive web shell exposing chat, council traces and metrics.
      Safe to enable in production; controls UI front‑end.
    security:
      csrf_protection: true
      content_security_policy: true
    performance:
      cache_control: max-age=3600
      gzip: true
      # Optional: enable HTTP/2 push for critical assets
      http2_push: false
  tts:
    enabled: true
    backend: system
    voice: default
    notes: |
      Text‑to‑speech adapter using the host OS `system` backend.
      Independent of the kernel; disable only when speech output
      interferes with automated pipelines.
    fallback: false
    latency_ms: 100
    quality: medium
    # Additional tuning parameters
    volume: 1.0
    rate: 1.0
    pitch: 1.0
    # When true, errors are logged but do not abort the pipeline
    resilient: true
```

## `data/infer_patterns.yml`
```yml
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
      - '(?:sweep|refactor|cleans*up|rewrite|polish|tidys*up|overhaul|improves+(?:all|every)|gos+throughs+(?:all|every)|fulls+passs+(?:over|on))(?:s+(?:all|every(?:thing)?|the))?(?:s+([w/.]+))?'
      - '(?:rydds+opp|refaktorer|forbedre?|gjennomg[åa]|omskriv)(?:s+([w/.]+))?'
    capture: path
  autoloop:
    patterns:
      - '(?:autoloop|autofix|fixs+alls+violations?|keeps+(?:fix|loop)|loops+until|iterates+until|runs+untils+clean|keeps+goings+until|(?:run|go)s+(?:its+)?(?:agains+)?untils+(?:done|clean|fixed|perfect))(?:s+(d+))?'
      - '(?:fiks?s+alle?s+(?:feil|brudd)|fortsetts+(?:til|inntil)|kj[øo]rs+(?:tils+)?(?:dets+ers+)?(?:rent|bra|ferdig))(?:s+(d+))?'
    capture: cycles
  council:
    patterns:
      - '(?:council|deliberat|multiples+perspect|seconds+opinion|peers+review|debates+this|gets+(?:another|as+second)s+view|multi(?:ple)?s+(?:view|agent|model|perspect))'
      - '(?:r[åa]dsl[åa]g|bruks+(?:flere|multiple)s+(?:perspektiv|synsvinkler?)|diskuters+(?:dette|det))'
    capture: on_off
  explain:
    patterns:
      - '(?:explains+(?:your(?:self)?|yours+architecture|hows+yous+work)|describes+(?:your(?:self)?|yours+architecture)|whats+ares+you|hows+(?:ares+yous+built|dos+yous+work)|shows+(?:yours+)?architecture|self[s-]?map)'
    capture: none
  persona:
    patterns:
      - '(?:(?:switch|change|set)s+personas+(?:tos+)?(w+)|personas+(w+)|uses+(w+)s+persona)'
    capture: persona_name
  memory:
    patterns:
      - '(?:whats+dos+yous+remember(?:s+abouts+([ws]+))?|shows+(?:mys+)?memor(?:y|ies)|lists+memor(?:y|ies)|recall(?:s+([w]+))?|what(?:''s|s+is)s+ins+(?:yours+)?memory|remembers+([w]+=.+)|forgets+([w_]+))'
      - '(?:hvas+huskers+du(?:s+oms+([ws]+))?|viss+(?:mins+)?hukommelse|husks+([w_]+=.+))'
    capture: first_group
  tokens:
    patterns:
      - '(?:tokens*count|hows+manys+tokens?|contexts+size|tokens+usage|hows+muchs+context|hvors+manges+token|tokens*antall)'
    capture: none
  cost:
    patterns:
      - '(?:hows+muchs+(?:hass+thiss+cost|dids+thiss+cost)|(?:currents+)?(?:spend|cost|budget)|what(?:''s|s+is)s+thes+cost|hvas+koster?s+(?:dette|det)|kostnader?)'
    capture: none
  undo:
    patterns:
      - '(?:undos+that|reverts+(?:that|last|it)|gos+back|takes+thats+back|angres+det|g[åa]s+tilbake)'
    capture: none
  clear:
    patterns:
      - '(?:clears+(?:context|chat|history|session|screen)|starts+(?:over|fresh|again)|resets+(?:context|session)|freshs+start|t[øo]ms+(?:kontekst|historikk)|begynns+p[åa]s+nytt)'
    capture: none
  save:
    patterns:
      - '(?:saves+(?:session|this|mys+work|progress)|checkpoints+now|lagres+(?:session|sesjonen?|arbeid))'
    capture: none
  model:
    patterns:
      - '(?:whichs+model|currents+model|whats+models+ares+you|whats+(?:llm|ai|model)s+(?:ares+yous+using|iss+this))'
    capture: none
  scan:
    patterns:
      - '(?:scan|lint|checks+(?:code|violations?)|runs+scan)(?:s+(deep))?'
    capture: scan_depth
  dmesg:
    patterns:
      - '(?:shows+(?:logs?|events?)|systems+log|dmesg|whats+(?:happened|hass+happened)|recents+activity)'
    capture: none
  dreams:
    patterns:
      - '(?:dreams?|consolidate?s+memor(?:y|ies)|memorys+consolidat|dreams+mode|promotes+memor(?:y|ies))'
    capture: first_group
  soul:
    patterns:
      - '(?:show|check|view)s+(?:thes+)?soul'
      - 'souls+(?:version|changelog|diff|approve|reject|rollback|propose)'
    capture: soul_subcmd
  orders:
    patterns:
      - '(?:standings+orders?|shows+orders?|lists+orders?)'
    capture: orders_subcmd
```

## `data/language_axioms.yml`
```yml
# Language-specific beauty axioms for MASTER2's refactoring engine
# Detection rules + design philosophy across all supported languages
ruby:
  - id: prefer_each_with_object
    name: "Prefer each_with_object over inject for hash building"
    detect: '.(inject|reduce)(s*{s*}s*)'
    suggest: "Use .each_with_object({}) instead — eliminates mutable-return footgun"
    severity: warning
    autofix: false
  - id: guard_clause_over_nested
    name: "Favor guard clauses over nested conditionals"
    detect: '^s*def w+.*
s*if .+
(?:.*
)*?s*else
(?:.*
)*?s*ends*$'
    suggest: "Flatten to: return ... unless condition"
    severity: info
    autofix: false
  - id: safe_navigation_chain
    name: "Use &. safe navigation consistently"
    detect: '(w+)s*&&s*.w+'
    suggest: "Rewrite to x&.foo&.bar"
    severity: warning
    autofix: true
  - id: freeze_collection_constants
    name: "Freeze all collection literals assigned to constants"
    detect: '^s*[A-Z][A-Z_]*s*=s*[[{](?!.*.freeze)'
    suggest: "Add .freeze to prevent mutation: CONST = [...].freeze"
    severity: warning
    autofix: true
  - id: module_function_over_extend_self
    name: "Prefer module_function where appropriate"
    detect: 'extend self
.*class << self'
    suggest: "Consider module_function for cleaner intent"
    severity: info
    autofix: false
  - id: keyword_args_over_positional
    name: "Enforce keyword arguments for ≥3 parameters"
    detect: 'def w+([^)]*,s*[^:)]+,s*[^:)]+,s*[^:)]+)'
    suggest: "Use keyword arguments for clarity and safety"
    severity: info
    autofix: false
  - id: kernel_coercion
    name: "Prefer Array(), Hash(), String() kernel coercions"
    detect: '(w+)s*.s*nil?s*?s*[]s*:s*|(w+)s*||s*[]'
    suggest: "Use Array(x) instead of x.nil? ? [] : x"
    severity: info
    autofix: true
  - id: include_comparable
    name: "Use Comparable instead of manual comparison methods"
    detect: 'def <(|def >(|def <=>('
    suggest: "include Comparable and define <=> only"
    severity: info
    autofix: false
  - id: rescue_on_def
    name: "Move begin/rescue wrapping entire method to def line"
    detect: '^s*def w+.*
s*begin
(?:.*
)*?s*rescue'
    suggest: "Put rescue directly on the def block"
    severity: info
    autofix: false
  - id: use_tap
    name: "Promote tap for inline debugging and builder returns"
    detect: '(w+)s*=s*w+.new
s*.w+s*=.*
s*s*$'
    suggest: "Use Foo.new.tap { |o| o.bar = val }"
    severity: info
    autofix: false
  - id: percent_literal_arrays
    name: "Favor %i[] and %w[] for symbol/string arrays"
    detect: '[:[a-z_]+,s*:[a-z_]+,s*:[a-z_]+'
    suggest: "Use %i[a b c] for symbol arrays"
    severity: info
    autofix: true
  - id: transform_keys_values
    name: "Use transform_keys/transform_values over manual hash iteration"
    detect: '.each_with_object({})s*{s*|(k,s*v),s*h|'
    suggest: "Use .transform_values { |v| ... } (Ruby 2.5+)"
    severity: info
    autofix: false
  - id: use_then_pipeline
    name: "Use .then for single-line pipeline transforms"
    detect: '(w+)s*=s*w+(.*)
s*w+()'
    suggest: "Chain with .then { |r| next_step(r) }"
    severity: info
    autofix: false
  - id: hash_fetch_over_bracket_or
    name: "Prefer Hash#fetch over [] with ||"
    detect: 'w+[:w+]s*||'
    suggest: "Use hash.fetch(:key, default) for nil-vs-false safety"
    severity: info
    autofix: false
  - id: private_section_placement
    name: "Enforce single private section at bottom"
    detect: 'privates+:w+'
    suggest: "Use a single 'private' keyword with methods below it"
    severity: info
    autofix: false
rails:
  - id: detect_n_plus_one
    name: "Detect N+1 queries by static pattern"
    detect: '.(each|map|collect)s*(do|{).*.w+.w+'
    suggest: "Add .includes(:association) to prevent N+1"
    severity: warning
    autofix: false
  - id: strict_loading
    name: "Enforce strict_loading on associations"
    detect: '(has_many|belongs_to|has_one)s+:w+(?!.*strict_loading)'
    suggest: "Add strict_loading: true for dev/test"
    severity: info
    autofix: false
  - id: scope_over_class_method
    name: "Prefer scopes over class methods for chainable queries"
    detect: 'def self.w+.*
s*where('
    suggest: "Use scope :name, -> { where(...) }"
    severity: info
    autofix: false
  - id: find_each_over_each
    name: "Use find_each for batch processing"
    detect: '.(all.each|where(.*).each)'
    suggest: "Use .find_each(batch_size: 1000) for memory efficiency"
    severity: warning
    autofix: false
  - id: no_update_attribute
    name: "Replace update_attribute with update!"
    detect: '.update_attribute('
    suggest: "update_attribute skips validations — use update!"
    severity: error
    autofix: true
  - id: callback_extraction
    name: "Extract long callbacks to service objects"
    detect: '(after_create|before_save|after_save)s+:w+(?=.*
(?:.*
){5,})'
    suggest: "Extract callback logic >5 lines to a service object"
    severity: info
    autofix: false
  - id: frozen_string_literal_auto
    name: "Auto-add frozen_string_literal magic comment"
    detect: 'A(?!# frozen_string_literal)'
    suggest: "Add # frozen_string_literal: true as first line"
    severity: warning
    autofix: true
  - id: pluck_over_map
    name: "Prefer pluck over map for single-column selects"
    detect: '.w+.map(&:w+)'
    suggest: "Use .pluck(:column) to avoid AR object instantiation"
    severity: info
    autofix: false
  - id: use_delegate
    name: "Use delegate instead of manual delegation"
    detect: 'def (w+)
s*w+.
s*end'
    suggest: "Use delegate :method, to: :association"
    severity: info
    autofix: false
  - id: strong_params_exhaustive
    name: "Enforce strong parameters exhaustiveness"
    detect: '.permit('
    suggest: "Cross-reference .permit() list with schema.rb columns"
    severity: info
    autofix: false
zsh:
  - id: quote_variables
    name: "Always quote $variables"
    detect: '(?<!["'\])$w+(?!["'])'
    suggest: 'Use "$VAR" to prevent word splitting and glob expansion'
    severity: error
    autofix: true
  - id: double_bracket_test
    name: "Use [[ ]] over [ ] for conditionals"
    detect: '(?<![)[s+[^[]'
    suggest: "Use [[ ... ]] for safe conditionals"
    severity: warning
    autofix: true
  - id: dollar_paren_over_backtick
    name: "Replace backticks with $(command)"
    detect: '`[^`]+`'
    suggest: "Use $(command) — nestable and readable"
    severity: warning
    autofix: true
  - id: local_in_functions
    name: "Use local for function variables"
    detect: '^w+()s*{[^}]*
s+w+='
    suggest: "Declare with 'local' to prevent global leaks"
    severity: warning
    autofix: false
  - id: parameter_expansion_default
    name: "Prefer ${var:-default} over if/then"
    detect: 'if [ -z "$w+" ]; thens+w+=w+'
    suggest: 'Use ${var:-default} for concise defaults'
    severity: info
    autofix: false
  - id: strict_mode
    name: "Use set -euo pipefail at script top"
    detect: '^#!/.*(?:ba|z)sh
(?!set -)'
    suggest: "Add 'set -euo pipefail' after shebang"
    severity: error
    autofix: true
  - id: useless_cat
    name: "Replace cat file | command with command < file"
    detect: 'cats+S+s*|'
    suggest: "Use command < file (Useless Use of Cat)"
    severity: info
    autofix: true
  - id: heredoc_for_multiline
    name: "Use heredocs for multi-line strings"
    detect: 'echos+".*"
s*echos+".*"
s*echos+"'
    suggest: "Use heredoc: cat <<'EOF'"
    severity: info
    autofix: false
html_erb:
  - id: semantic_elements
    name: "Enforce semantic HTML5 elements"
    detect: '<divs+class="(header|footer|nav|main|sidebar|article|section)"'
    suggest: "Use <header>, <footer>, <nav>, <main>, <aside>, <article>, <section>"
    severity: warning
    autofix: true
  - id: img_alt_required
    name: "Require alt on every <img>"
    detect: '<imgs+(?![^>]*alt=)'
    suggest: "Add alt= attribute (use alt="" for decorative images)"
    severity: error
    autofix: false
  - id: button_over_anchor
    name: "Prefer <button> over <a href="#">"
    detect: '<as+href=["'']#["'']'
    suggest: "Use <button> for actions — accessible by default"
    severity: warning
    autofix: false
  - id: time_element
    name: "Use <time datetime=""> for dates"
    detect: 'd{4}-d{2}-d{2}(?!.*<time)'
    suggest: "Wrap dates in <time datetime="ISO8601">"
    severity: info
    autofix: false
  - id: html_lang
    name: "Enforce lang attribute on <html>"
    detect: '<html(?!s+[^>]*lang=)'
    suggest: "Add lang="en" (or appropriate locale)"
    severity: error
    autofix: true
  - id: no_inline_styles
    name: "Replace inline styles with classes"
    detect: 'style="[^"]*"'
    suggest: "Extract to CSS class for cacheability"
    severity: warning
    autofix: false
  - id: erb_partials
    name: "Use ERB partials for repeated blocks"
    detect: null
    suggest: "Extract repeated ≥3-line blocks to _partial.html.erb"
    severity: info
    autofix: false
  - id: content_tag_helpers
    name: "Prefer content_tag/tag helpers over raw HTML in helpers"
    detect: '["'']<w+[^"'']*>["'']'
    suggest: "Use Rails tag() or content_tag() helpers"
    severity: info
    autofix: false
  - id: aria_on_interactive
    name: "Enforce ARIA on non-semantic interactive elements"
    detect: '<(div|span)s+[^>]*onclick'
    suggest: "Add role= and tabindex= for accessibility"
    severity: warning
    autofix: false
  - id: lazy_loading_images
    name: "Use loading="lazy" on below-fold images"
    detect: '<imgs+(?![^>]*loading=)'
    suggest: "Add loading="lazy" for below-fold images"
    severity: info
    autofix: true
css_scss:
  - id: logical_properties
    name: "Prefer logical properties over physical"
    detect: '(margin|padding)-(left|right):'
    suggest: "Use margin-inline-start/end, padding-inline-start/end for RTL support"
    severity: info
    autofix: true
  - id: custom_properties_over_magic
    name: "Replace magic numbers with CSS custom properties"
    detect: '(?:margin|padding|gap|font-size):s*d+px'
    suggest: "Extract to var(--spacing-*) or var(--size-*)"
    severity: info
    autofix: false
  - id: gap_over_margins
    name: "Prefer gap over margin hacks for flex/grid"
    detect: '+s*w+s*{[^}]*margin-(left|top):'
    suggest: "Use gap on the flex/grid container instead"
    severity: info
    autofix: false
  - id: clamp_typography
    name: "Use clamp() for fluid typography"
    detect: '@media.*{[^}]*font-size:'
    suggest: "Use font-size: clamp(1rem, 2.5vw, 1.5rem)"
    severity: info
    autofix: false
  - id: mobile_first
    name: "Enforce mobile-first media queries"
    detect: '@medias*(s*max-width'
    suggest: "Use min-width (mobile-first, progressive enhancement)"
    severity: warning
    autofix: false
  - id: use_forward_over_import
    name: "Replace @import with @use/@forward in SCSS"
    detect: '@imports+["']'
    suggest: "@import is deprecated — use @use/@forward"
    severity: warning
... 301 lines truncated (601 total)
```

## `data/language_rules.yml`
```yml
ruby:
  version: "3.3+"
  frozen_string_literal: required
  magic_comments: true
  guard_clauses: true
  max_method_lines: 12
  max_class_lines: 200
  max_params: 3
  rescue: specify_type_always
  lint:
    style: strict
    complexity: low
    todo_comments: forbidden
    unused_variables: error
    naming_convention: snake_case
    mutable_state: forbidden
    duplicated_logic: error
  documentation: required
  type_checking: strict
  security:
    taint_mode: true
    safe_navigation: required
rails:
  version: "8+"
  stack:
    - solid_queue
    - solid_cache
    - solid_cable
  frontend: hotwire
  database: sqlite_default
  testing: minitest
  security:
    strong_parameters: true
    csrf_protection: true
    content_security_policy: true
    ssl_enforced: true
    cookie_secure: true
    http_strict_transport_security: true
  assets:
    digest: true
    compile: false
    precompile: true
  time_zone: UTC
  locales:
    default: en
    available:
      - en
      - nb
  background_jobs:
    adapter: solid_queue
    max_concurrent: 10
    retry_attempts: 3
    queue_prefix: master
zsh:
  shebang: "#!/usr/bin/env zsh"
  options: "set -euo pipefail; setopt nullglob extendedglob"
  banned_commands:
    - sed
    - awk
    - tr
    - grep
    - cut
    - head
    - tail
    - find
    - wc
    - sudo
    - perl
    - ruby
    - dd
    - xargs
  enforce_strict:
    - errexit
    - nounset
    - pipefail
    - noclobber
    - noglob
    - noexec
  allowed_builtin: false
openbsd:
  service_manager: rcctl
  package_manager: pkg_add
  firewall: pf
  privilege: doas
  http: httpd
  mail: smtpd
  update:
    daily: true
    mirror: secure
    auto_security: true
    auto_reboot: false
  syslog: inet
  ssh:
    permit_root_login: no
    password_authentication: no
    allow_agent_forwarding: no
    permit_empty_passwords: no
    allow_tcp_forwarding: no
    max_auth_tries: 3
    enable_publickey_authentication: true
  cron:
    allow_user: master
    deny_user: root
  user_add_defaults:
    umask: "027"
    login_class: daemon
    home_directory: "/var/master"
  sysctl:
    net.inet.ip.forwarding: 0
    kern.random.tls_entropy: 1
    vm.swappiness: 0
    net.inet.tcp.msl: 15000
```

## `data/mcp_servers.yml`
```yml
# MCP server definitions for MASTER.
# Transport options: stdio | sse
# All stdio servers share a common command pattern.
# Anchors remove duplication and simplify future updates.
defaults: &defaults
  transport: stdio
  command: npx
  enabled: true
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
```yml
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
  deepseek_r1: &deepseek_r1
    id: deepseek/deepseek-r1-0528:free
    <<: *model_defaults
    score: { quality: 0.73, speed: 0.55, cost: 1.0 }
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
models:
  default:
    - *nemotron_super
    - *qwen_coder
    - *gpt_oss
    - *gemini_flash
  strong:
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
```

## `data/openbsd_patterns.yml`
```yml
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

## `data/platform.yml`
```yml
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

## `data/principles.yml`
```yml
principles:
  01-kiss:
    name: KISS (Keep It Simple, Stupid)
    description: The most famous principle
    tier: core
    priority: 1
    auto_fixable: false
    anti_patterns:
    - name: over_engineering
      smell: Building for hypothetical future requirements
      fix: Delete abstractions until it hurts
    - name: unnecessary_complexity
      smell: Nested conditionals, convoluted logic, too many parameters
      fix: Extract methods, use early returns, simplify
    - name: premature_abstraction
      smell: Creating interfaces/base classes before second use case
      fix: Wait for duplication, then abstract
  02-dry:
    name: DRY (Don't Repeat Yourself)
    description: Every piece of knowledge must have a single, authoritative representation
    tier: core
    priority: 2
    auto_fixable: true
    anti_patterns:
    - name: duplicate_code
      smell: Same logic in multiple places
      fix: Extract to shared method/module
    - name: copy_paste_programming
      smell: Copying code instead of abstracting
      fix: Parameterize the original, reuse it
  03-yagni:
    name: YAGNI (You Aren't Gonna Need It)
    description: Implement things when you need them, never when you foresee needing them
    tier: core
    priority: 3
    auto_fixable: true
    anti_patterns:
    - name: speculative_generality
      smell: Building for imagined future requirements
      fix: Delete until actually needed
    - name: unused_code
      smell: Methods/classes never called
      fix: Delete it
    - name: dead_code
      smell: Unreachable code paths
      fix: Delete it
  04-separation-of-concerns:
    name: Separation of Concerns
    description: Divide program into distinct sections, each addressing a separate concern
    tier: core
    priority: 4
    auto_fixable: false
    anti_patterns:
    - name: mixed_concerns
      smell: One module handles unrelated responsibilities
      fix: Split into UserAuth, UserMailer, UserBilling
    - name: ui_logic_in_models
      smell: Domain models contain presentation logic
      fix: Use presenters/decorators for display logic
    - name: business_logic_in_views
      smell: Templates contain conditionals and calculations
      fix: Move logic to model/presenter, expose simple flags
  05-single-responsibility:
    name: Single Responsibility (SOLID S)
    description: A module should have one, and only one, reason to change
    tier: solid
    priority: 5
    auto_fixable: true
    anti_patterns:
    - name: god_class
      smell: Class over 300 lines or 10+ public methods
      fix: Extract concerns into focused classes
    - name: feature_envy
      smell: Method uses another class more than its own
      fix: Move method to the class it envies
    - name: long_method
      smell: Method over 20 lines or 5 nesting levels
      fix: Extract into smaller named methods
  06-open-closed:
    name: Open-Closed (SOLID O)
    description: Open for extension, closed for modification
    tier: solid
    priority: 6
    auto_fixable: false
    anti_patterns:
    - name: shotgun_surgery
      smell: One change requires edits in many files
      fix: Use strategy pattern, dependency injection
    - name: rigid_design
      smell: Can't extend without modifying core code
      fix: Use polymorphism, plugins, or hooks
  07-liskov-substitution:
    name: Liskov Substitution (SOLID L)
    description: Subtypes must be substitutable for their base types
    tier: solid
    priority: 7
    auto_fixable: false
    anti_patterns:
    - name: refused_bequest
      smell: Subclass doesn't use inherited methods
      fix: Use composition, or don't inherit
    - name: type_checking
      smell: Checking class type instead of using polymorphism
      fix: Define common interface, let each type implement
  08-interface-segregation:
    name: Interface Segregation (SOLID I)
    description: Clients should not depend on interfaces they don't use
    tier: solid
    priority: 8
    auto_fixable: false
    anti_patterns:
    - name: fat_interface
      smell: Interface with too many methods
      fix: Split into smaller role-based interfaces
    - name: forced_implementation
      smell: Empty or stub implementations of interface methods
      fix: Remove method from interface, use mixins
  09-dependency-inversion:
    name: Dependency Inversion (SOLID D)
    description: Depend on abstractions, not concretions
    tier: solid
    priority: 9
    auto_fixable: false
    anti_patterns:
    - name: tight_coupling
      smell: Class directly instantiates its dependencies
      fix: Inject dependencies through constructor
    - name: hard_coded_dependencies
      smell: Concrete class names scattered throughout code
      fix: Inject abstraction, swap implementations easily
  10-law-of-demeter:
    name: Law of Demeter
    description: Only talk to your immediate friends
    tier: design
    priority: 10
    auto_fixable: true
    anti_patterns:
    - name: message_chains
      smell: Long chains like `a.b.c.d.e`
      fix: 'Add delegate method: `order.customer_city`'
    - name: inappropriate_intimacy
      smell: Class knows too much about another's internals
      fix: Use public interface, hide implementation
    - name: feature_envy
      smell: Method uses another object's data excessively
      fix: Move method to the class it envies
  11-composition-over-inheritance:
    name: Composition Over Inheritance
    description: Favor object composition over class inheritance
    tier: design
    priority: 11
    auto_fixable: false
    anti_patterns:
    - name: deep_hierarchy
      smell: Inheritance chain deeper than 3 levels
      fix: Flatten with mixins or composition
    - name: refused_bequest
      smell: Subclass ignores or overrides most parent methods
      fix: 'Use composition: `has_a` not `is_a`'
    - name: inheritance_abuse
      smell: Inheriting for code reuse, not substitutability
      fix: 'Compose: `Stack` contains `ArrayList`'
  12-fail-fast:
    name: Fail Fast
    description: Errors should be reported as soon as they are detected
    tier: reliability
    priority: 12
    auto_fixable: true
    anti_patterns:
    - name: silent_failure
      smell: Errors caught and ignored
      fix: Log, re-raise, or handle explicitly
    - name: swallowed_exceptions
      smell: Catching broad exceptions, hiding root cause
      fix: Catch specific exceptions, let others bubble
    - name: defensive_nulls
      smell: Returning nil instead of raising on error
      fix: Raise exception or use Result monad
  13-principle-of-least-astonishment:
    name: Principle of Least Astonishment
    description: Systems should behave as users expect
    tier: ux
    priority: 13
    auto_fixable: false
    anti_patterns:
    - name: surprising_behavior
      smell: Method does something unexpected from its name
      fix: 'Rename or split: `save_and_notify()`'
    - name: inconsistent_api
      smell: Similar methods behave differently
      fix: Establish conventions, document behavior
    - name: hidden_side_effects
      smell: Getter that modifies state
      fix: Separate query from command
  14-command-query-separation:
    name: Command-Query Separation
    description: Methods should either change state OR return data, never both
    tier: design
    priority: 14
    auto_fixable: true
    anti_patterns:
    - name: side_effects_in_queries
      smell: Getter modifies state
      fix: 'Split: `stack.top()` + `stack.remove()`'
    - name: mixed_responsibilities
      smell: Method both computes and persists
      fix: '`total = calculate(); save(total)`'
  15-boy-scout-rule:
    name: Boy Scout Rule
    description: Leave the code cleaner than you found it
    tier: practice
    priority: 15
    auto_fixable: true
    anti_patterns:
    - name: technical_debt_ignored
      smell: TODO comments never addressed
      fix: Fix it now or delete the comment
    - name: broken_windows
      smell: Visible code rot left unfixed
      fix: Clean up on each commit, no exceptions
  16-unix-philosophy:
    name: Unix Philosophy
    description: Do one thing well
    tier: architecture
    priority: 16
    auto_fixable: false
    anti_patterns:
    - name: monolithic_design
      smell: Single app does everything
      fix: Extract services, use clear module boundaries
    - name: tight_coupling
      smell: Components can't be used independently
      fix: Use stdin/stdout, compose with pipes
  17-functional-core-imperative-shell:
    name: Functional Core, Imperative Shell
    description: Pure logic in the core, side effects at the edges
    tier: architecture
    priority: 17
    auto_fixable: false
    anti_patterns:
    - name: scattered_side_effects
      smell: IO/DB calls deep in business logic
      fix: Return data from core, let shell handle IO
    - name: impure_core
      smell: Core functions depend on global state
      fix: Inject configuration, keep core deterministic
  18-idempotent-operations:
    name: Idempotent Operations
    description: Same operation, same result
    tier: reliability
    priority: 18
    auto_fixable: false
    anti_patterns:
    - name: non_idempotent_mutations
      smell: Repeated calls produce different results
      fix: Use `set_counter(value)` instead
    - name: unsafe_retries
      smell: Retry logic without idempotency keys
      fix: Add idempotency key, check before processing
  19-defensive-programming:
    name: Defensive Programming
    description: Never trust input
    tier: reliability
    priority: 19
    auto_fixable: true
    anti_patterns:
    - name: missing_validation
      smell: User input used without checks
      fix: Whitelist, sanitize, validate all input
    - name: trust_boundary_violation
      smell: Internal code trusts external data
      fix: Validate at boundaries, fail on invalid data
  20-fail-gracefully:
    name: Graceful Degradation
    description: Partial functionality beats total failure
    tier: reliability
    priority: 20
    auto_fixable: false
    anti_patterns:
    - name: missing_fallback
      smell: Single point of failure crashes everything
      fix: Fallback to database, show stale data
    - name: cascade_failures
      smell: One service down takes others with it
      fix: Circuit breakers, timeouts, bulkheads
  21-explicit-over-implicit:
    name: Explicit Over Implicit
    description: Zen of Python
    tier: clarity
    priority: 21
    auto_fixable: true
    anti_patterns:
    - name: magic_values
      smell: Unexplained literals in code
      fix: 'Use constants: `STATUS_APPROVED = 7`'
    - name: hidden_behavior
      smell: Implicit conversions or callbacks
      fix: Make transformations explicit in code path
    - name: implicit_conversions
      smell: Type coercion without explicit cast
... 400 lines truncated (700 total)
```

## `data/quality_thresholds.yml`
```yml
file_lines:
  warn: 200
  error: 300
  self_test_max: 300
method_lines:
  warn: 7
  error: 10
max_self_test_issues: 0
max_self_test_violations: 0
file:
  max_bytes: 8192
  max_lines: 250
  max_line_length: 80
method:
  max_lines: 8
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
graduation:
  apprentice:
    requires: []
    autonomy: ask_always
  journeyman:
    requires: [10_successful_tasks, zero_reverts_7d]
    autonomy: preview_changes
  craftsman:
    requires: [50_successful_tasks, zero_reverts_30d, test_coverage_95]
    autonomy: apply_safe
  master:
    requires: [200_successful_tasks, zero_reverts_90d, positive_user_feedback]
    autonomy: apply_all
profiles:
  minimal:
    description: "Bare minimum checks for prototypes and experiments"
    file_lines_max: 250
    method_lines_max: 12
    cyclomatic_max: 8
    test_coverage_min: 0
    enable_gates: [syntax, security]
  standard:
    description: "Default profile for most projects"
    file_lines_max: 300
    method_lines_max: 8
    cyclomatic_max: 6
    test_coverage_min: 85
    enable_gates: [syntax, security, complexity, style]
  complete:
    description: "Full enforcement for production code"
    file_lines_max: 250
    method_lines_max: 6
    cyclomatic_max: 4
    test_coverage_min: 95
    enable_gates: [syntax, security, complexity, style, duplication, performance]
  startup:
    description: "Fast iteration with core quality gates"
    file_lines_max: 200
    method_lines_max: 10
    cyclomatic_max: 7
    test_coverage_min: 70
    enable_gates: [syntax, security, critical_bugs]
  enterprise:
    description: "Maximum rigor for enterprise codebases"
    file_lines_max: 180
    method_lines_max: 5
    cyclomatic_max: 3
    test_coverage_min: 98
    enable_gates: [syntax, security, complexity, style, duplication, performance, documentation]
  research:
    description: "Flexible for research code with core safety"
    file_lines_max: 300
    method_lines_max: 15
    cyclomatic_max: 10
    test_coverage_min: 50
    enable_gates: [syntax, security]
  default_profile: "standard"
cost_protection:
  max_per_session: 5.00
  max_per_request: 0.50
  warn_at: 0.25
  enforcement: "warn at warn_at, block at max_per_request"
```

## `data/scan_depths.yml`
```yml
# Scan depth configurations
# Centralized list of every available rule name.
all_rules: &all_rules
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
# Pre‑defined depth groups
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
hunt: *all_rules
critique: *all_rules
deep: *all_rules
profiles:
  quick:
    description: Fast scan with core principles only
    allow:
      - "group:axioms"
      - "group:clean_code"
  full:
    description: All principles
    allow:
      - "*"
  axioms_only:
    description: Axioms tier only
    allow:
      - "group:axioms"
  critical:
    description: Critical issues only
    allow:
      - CqsRule
      - ExplicitRule
      - ImmutableRule
      - FrozenStringRule
      - LongMethodRule
      - GodClassRule
```

## `data/standing_orders.yml`
```yml
[]
```

## `data/strunk.yml`
```yml
preambles:
  - "In summary,"
  - "Consequently,"
  - "Therefore,"
  - "Notably,"
  - "Importantly,"
hedges:
  - "might"
  - "could"
  - "perhaps"
  - "seems"
  - "appears"
endings:
  - "as a result."
  - "for this reason."
  - "thus."
  - "in effect."
  - "accordingly."
code_preambles:
  - "# TODO: clarify intent"
  - "# FIXME: review edge cases"
  - "# NOTE: performance considerations"
  - "# HACK: temporary workaround"
  - "# REVIEW: assess after refactor"
```

## `data/sweep_prompts.yml`
```yml
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

## `data/templates.yml`
```yml
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

## `data/workflow.yml`
```yml
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
  after_commit: "ruby -e "require_relative 'lib/master'; puts 'ok'""
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
```yml
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
  remove_crlf:             "${var//$'\r'/}"
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
    code: "awk -F, '{print $4}' | sed 's/\r//g' | tr '[:upper:]' '[:lower:]'"
    cost: "3 grammars, pipes + subshells, I/O transformations"
  example_good:
    code: "cleaned=${var//$'\r'/}; lower=${(L)cleaned}; fourth=${${(s:,:)lower}[4]}"
    cost: "One grammar, one evaluation model, no process boundaries"
  benefit: "Model reasons locally instead of globally across pipeline"
```

## `lib/master.rb`
```rb
# frozen_string_literal: true
require "zeitwerk"
module Master
  ROOT = File.expand_path("..", __dir__).freeze
  MIN_API_KEY_LENGTH = 20
CTX_WINDOW_SIZE = 200_000
VIOLATION_TRUNCATE = 90
FILE_LANGUAGE_MAP = { ".rb" => "ruby", ".yml" => "yaml", ".yaml" => "yaml",
                       ".js" => "javascript", ".json" => "json", ".sh" => "bash",
                       ".zsh" => "bash", ".md" => "markdown", ".html" => "html",
                       ".erb" => "erb", ".css" => "css" }.freeze
  API_KEY_PROVIDERS = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY"
  }.freeze
  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "autoloop"   => "AutoLoop",
    "cli"        => "CLI",
    "llm"        => "LLM",
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"
  loader.setup
  def self.configure_providers!
    require "ruby_llm"
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
    config   = Config.new(root)
    config["model"] ||= default_model
    ring     = RingBuffer.new(1000)
    bus      = EventBus.new(log: ring)
    logging  = Logging.new(ring_buffer: ring, event_bus: bus, trace_level: config.trace)
    session  = Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
    undo     = Undo.new(session:, event_bus: bus)
    breaker  = CircuitBreakerRegistry.new(budget_max: config.budget_max, req_max: config.req_max, event_bus: bus)
    cache    = SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
    governor = Governor.new(config:, event_bus: bus)
    renderer = Renderer.new(config:)
    metrics  = Metrics.new(root:, event_bus: bus)
    AuditLog.new(root:, event_bus: bus)
    code_index   = CodeIndex.new(root:, event_bus: bus)
    diff_stager  = config["staging_enabled"] ? DiffStager.new(root:, event_bus: bus) : nil
    mcp          = McpCoordinator.new(root:, event_bus: bus)
    mcp.connect_all
    code_index.build
    bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }
    memory      = Memory.new(root:)
    experience  = State::Experience.new(root:)
    personality = Personality.new(config["persona"]&.to_sym || Personality::DEFAULT, root:)
    tools    = build_tools(root:, undo:, governor:, bus:, diff_stager:, code_index:)
    tools   += mcp.tools
    router   = Routing::ModelRouter.new(config:)
    modes    = Reasoning::Modes.new
    agent    = Agent.new(config:, session:, tools:, circuit_breaker: breaker, cache:, event_bus: bus,
                         model_router: router, reasoning_modes: modes,
                         memory:, personality:, code_index:)
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
    commands = build_commands(session:, undo:, logging:, config:, agent:,
                             council_stage:, swarm:, scanner:, deliberation:,
                             bus:, root:, memory:, cache:, metrics:,
                             standing:, soul: soul_doc)
    stages = [
      Stages::Intake.new,
      Stages::Infer.new,
      Stages::Route.new(commands:, agent:),
      Stages::Guard.new(governor:, injection_guard: guard),
      Stages::Execute.new,
      Pipeline::ParallelGroup.new(council_stage, Stages::Lint.new(scanner:, config:)),
      Stages::Prune.new,
      Stages::Memo.new(memory:, event_bus: bus),
      Stages::Render.new(renderer:)
    ]
    pipeline = Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:)
    standing.wire_pipeline(pipeline)
    {
      config:, session:, agent:, renderer:, logging:, undo:, pipeline:,
      scanner:, bus:, breaker:, cache:, governor:, metrics:, council_stage:,
      memory:, experience:, personality:, swarm:, root:,
      diff_stager:, mcp:, code_index:, standing:, soul: soul_doc,
    }
  end
  def self.boot(root: Dir.pwd, argv: [])
    container = build(root:)
    container[:renderer].tap { |r| puts r.banner(container[:agent].model) }
    CLI.new(container:)
  end
  def self.default_model
    return "deepseek-ai/deepseek-v3" if api_key_present?("OPENROUTER_API_KEY")
    return "deepseek-ai/deepseek-r1" if api_key_present?("REPLICATE_API_KEY")
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
  def self.build_commands(session:, undo:, logging:, config:, agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, memory:, cache:, metrics: nil, standing:, soul:)
    build_session_commands(session:, undo:, logging:, config:)
      .merge(build_mode_commands(config:))
      .merge(build_agent_commands(agent:, council_stage:, swarm:, scanner:, deliberation:, bus:, root:, config:, metrics:))
      .merge(build_memory_commands(memory:, agent:))
      .merge(build_utility_commands(agent:, root:, cache:))
      .merge(build_master_commands(standing:, soul:))
      .merge(
        "help" => ->(ctx) {
          cmds = %w[clear save tokens undo dmesg cost config model mode task autotest council autoloop swarm sweep memory dreams orders soul cache diff commit knowledge why snapshot explain persona help exit]
          cmds.map { "/#{_1}" }.join("  ")
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
      "config" => ->(ctx) { config.data.inspect },
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
      },
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
          result = swarm.dispatch(role, task: task, context_slice: {})
          result.ok? ? result.value!.inspect : result.message
        end
      },
      "explain" => ->(ctx) {
        map       = Introspection::SelfMap.new(root:)
        info      = map.describe
        cov       = map.axiom_coverage
        cov_lines = cov.map { |ax, n| "  #{ax}: #{n}" }.join("
")
        stages    = "Intake→Infer→Route→Guard→Execute→Council→Lint→Prune→Memo→Render"
        "MASTER — #{info[:files]} files, #{info[:lines]} lines
pipeline: #{stages}

axiom coverage:
#{cov_lines}"
      },
      "autoloop" => ->(ctx) {
        max    = ctx[:args].to_s.strip.to_i
        max    = AutoLoop::MAX_CYCLES if max <= 0
        looper = AutoLoop.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log    = []
        result = looper.run(max_cycles: max) { |cycle, violations|
          log << "  cycle #{cycle}: #{violations.size} violation(s)"
        }
        ([result.ok? ? result.value! : result.message] + log).join("
")
      },
      "sweep" => ->(ctx) {
        arg     = ctx[:args].to_s.strip
        target  = arg.empty? ? root : File.expand_path(arg, root)
        sweeper = Sweep.new(agent:, scanner:, council: deliberation, root:, event_bus: bus)
        log     = []
        result  = sweeper.run(target) { |cycle, file, delta|
          log << "  cycle #{cycle}  #{file}  +#{delta}"
        }
        ([result.ok? ? result.value! : result.message] + log).join("
")
      },
      "model" => ->(ctx) {
        arg = ctx[:args].to_s.strip
        if arg == "list"
          yml_path = File.join(root, "data", "models.yml")
          if File.exist?(yml_path)
            require "yaml"
            data          = YAML.safe_load_file(yml_path)
            tiers         = data["models"] || {}
            model_lines   = tiers.flat_map { |tier, ms| ms.to_a.map { |m| "  [#{tier}] #{m["id"]}" } }
            quality_lines = metrics&.model_quality&.map { |mod, s| "  #{mod}: #{s[:calls]} calls, fail_rate=#{s[:fail_rate]}" } || []
            sections      = ["available models:"] + model_lines
            sections     += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
            sections.join("
")
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
          "usage: /why <rule_name>  -- explains a scan rule. e.g. /why ExplicitRule"
... 185 lines truncated (485 total)
```

## `lib/master/agent.rb`
```rb
# frozen_string_literal: true
require "ruby_llm"
require "digest"
module Master
  class Agent
    DEFAULT_MESSAGE_WINDOW_SIZE = 16
    COST_PER_TOKEN              = 0.000_015
    # Replicate native API — these owner prefixes route through Bridges::Replicate.
    REPLICATE_OWNERS = %w[deepseek-ai mistralai xai meta-replicate].freeze
    # Tool-capable model whitelist — anchored regex, not substring match.
    # See note at tool_capable? for why the previous `include?` check was unsafe.
    TOOL_CAPABLE_RE = %r{
      A(?:
        (?:claude|gpt-4|gpt-4o|gemini|mistral|mixtral)
        | (?:llama-3.[13])
        | (?:qwen|command-r|deepseek|stepfun|nvidia|nemotron)
        | (?:meta/meta-llama.+)
        | (?:anthropic/claude.+)
        | (?:openai/gpt.+)
        | (?:google/gemini.+)
      )(?:[:@/-.].+)?z
    }ix.freeze
    MAX_TOOL_TURNS     = 5
    MIN_API_KEY_LENGTH = 20
    TOOL_CALL_RE       = /(?:<use_tool>s*(.*?)s*</use_tool>|^ACTION:s*({.*?})s*$|^TOOL:s*({.*?})s*$)/m.freeze
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
    def chat(message, stream: true, escalation_attempted: false, &blk)
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
      last_response = maybe_escalate(last_response, prompt, context, message, stream, escalation_attempted, &blk)
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
    def maybe_escalate(last_response, prompt, context, original_message, stream, escalation_attempted, &blk)
      return last_response unless @model_router
      return last_response if escalation_attempted
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
        escalation_attempted: true,
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
        return Result.ok(response.respond_to?(:value!) ? response.value! : response.to_s)
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
      parts.empty? ? nil : parts.join("

")
    end
    def extract_response(reply, selected_model)
      return reply.to_s unless reply.respond_to?(:content)
      if NEMOTRON3_RE.match?(selected_model) && reply.respond_to?(:reasoning_content)
        thinking = reply.reasoning_content.to_s.strip
        content  = reply.content.to_s
        return thinking.empty? ? content : "#{content}

<think>
#{thinking}
</think>"
      end
      reply.content.to_s
    end
    def nemotron_system_prompt(selected_model, base_system_prompt = nil)
      base = base_system_prompt || system_prompt
      return base unless LLAMA_NEMOTRON_RE.match?(selected_model)
      thinking_on = @config["reasoning_mode"] != "none"
      directive   = thinking_on ? "detailed thinking on" : "detailed thinking off"
      [directive, base].compact.join("

")
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
      window = context.last(CACHE_WINDOW).map { |msg| "#{msg[:role]}:#{msg[:content]}" }.join("
")
      Digest::SHA256.hexdigest("#{message}
#{window}")
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
end
```

## `lib/master/audit_log.rb`
```rb
# frozen_string_literal: true
require "fileutils"
module Master
  # Append-only audit trail of every tool invocation.
  # Subscribes to tool:before events on the shared EventBus.
  # Written to data/audit.log — one line per call, machine-readable.
  class AuditLog
    LOG_PATH = "data/audit.log"
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
```rb
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
      "Fix this Ruby violation in #{violation[:file]}.
" \
        "Rule: #{violation[:rule]}
" \
        "Issue: #{violation[:message]} (line #{violation[:line]})

" \
        "Return ONLY the corrected Ruby file content, no explanation.

" \
        "```ruby
#{src}
```"
    end
    # Reflexion-style prefix: tell the model the prior attempt failed and why.
    # Directly inspired by arxiv:2503.14340 (MANTRA Repair Agent).
    def reflected_prompt(base, last_error, attempt)
      "Prior attempt (#{attempt}) failed with: #{last_error[0, 200]}
" \
        "Reflect briefly on what went wrong, then retry.

" \
        "#{base}"
    end
    def extract_code(text)
      return text.match(/```ruby
(.*?)```/m)[1].strip if text.match?(/```ruby
(.*?)```/m)
      return text.match(/```
(.*?)```/m)[1].strip if text.match?(/```
(.*?)```/m)
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
      score += 0.25 if code.match?(/A.*?(?:module |class )[A-Z]/m)
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
```rb
# frozen_string_literal: true
require 'yaml'
module Master
  # Central source for kernel axioms, philosophy, and workflow rules.
  # All data is loaded once (optionally from a custom root) and frozen
  # to guarantee immutability and fast repeated access.
  class Axioms
    DATA_PATH     = File.join(File.expand_path('../../..', __dir__), 'data', 'axioms.yml').freeze
    WORKFLOW_PATH = File.join(File.expand_path('../../..', __dir__), 'data', 'workflow.yml').freeze
    def initialize(root: nil)
      @axioms_path   = root ? File.join(root, 'data', 'axioms.yml')   : DATA_PATH
      @workflow_path = root ? File.join(root, 'data', 'workflow.yml') : WORKFLOW_PATH
      @data          = load_yaml(@axioms_path)   || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end
    # Public API ---------------------------------------------------------
    def kernel
      @kernel ||= (@data['kernel'] || {}).freeze
    end
    def workflow
      @workflow.freeze
    end
    # Returns philosophy items sorted by ascending priority.
    # If +limit+ is provided, only that many items are returned.
    def philosophy(limit: nil)
      @philosophy ||= begin
        items = (@data.dig('philosophy', 'prioritized_top_25') || [])
        items
          .map { |h| h.transform_keys(&:to_s) }
          .sort_by { |h| h['priority'].to_i }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end
    # Formatted blocks for display (e.g. in prompts) --------------------
    def kernel_block
      return nil if kernel.empty?
      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("
")
      "## Kernel Axioms (enforced)
#{pairs}"
    end
    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?
      top = items.map { |a| "  #{a['id']}: #{a['statement']}" }.join("
")
      "## Core Philosophy (top #{items.size})
#{top}"
    end
    # Workflow rule lookup ------------------------------------------------
    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end
    # General lookup -------------------------------------------------------
    def lookup(id)
      id_str = id.to_s
      kernel[id_str] ||
        philosophy.find { |a| a['id'] == id_str }&.dig('statement')
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
```rb
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
```rb
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
        parts << "<<SYS>>
#{system}
<</SYS>>

" if system
        messages.each do |m|
          role    = (m[:role] || m["role"]).to_s.downcase
          content = (m[:content] || m["content"]).to_s
          tag     = role == "assistant" ? "Assistant" : "Human"
          parts << "#{tag}: #{content}
"
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
              while (idx = buffer.index("

"))
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
end
```

## `lib/master/circuit_breaker.rb`
```rb
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
```rb
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

## `lib/master/cli.rb`
```rb
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
    TOGGLE_VALUES = %w[on off].freeze
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
      cmd, *args = s.split
      dispatch_command(cmd, args) || run_input(s)
    end
    def run_input(input)
      return if input.strip.empty?
      accumulated = +""
      streamed = false
      thinking_shown = true
      on_chunk = build_chunk_handler(accumulated) do |text|
        if thinking_shown && $stdout.isatty
          print "[K"
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
        handle_command(line) || run_input(line)
      end
      @scan_thread&.kill
      @session.save! if @session.respond_to?(:save!)
    end
    def handle_command(line)
      return false unless line.start_with?("/")
      cmd, *args = line[1..].split
      dispatch_command(cmd, args)
    end
    def dispatch_command(cmd, args)
      case cmd
      when "help"    then puts help_text
      when "clear"   then clear_screen
      when "exit"    then exit_cli
      when "model"   then puts @renderer.render(@agent.model.to_s, mode: :dim)
      when "tokens"  then puts @renderer.render("session tokens: #{safe_token_est}", mode: :dim)
      when "save"    then save_session
      when "dmesg"   then puts format_dmesg_lines
      when "scan"    then run_scan_command(args)
      when "stage"   then run_stage_command
      when "apply"   then run_apply_command(args)
      when "discard" then run_discard_command(args)
      when "staging" then toggle_staging(args)
      when "tts"     then toggle_tts(args)
      when "profile" then puts format_profile
      else false
      end
    end
    def exit_cli
      @session.save! if @session.respond_to?(:save!)
      @running = false
    end
    def clear_screen
      print "[2J[H"
      puts @renderer.splash(@agent.model)
    end
    def safe_token_est
      @session.token_est
    rescue StandardError
      "n/a"
    end
    def save_session
      @session.save! if @session.respond_to?(:save!)
      puts @renderer.render("saved", mode: :success)
    end
    def format_profile
      timings = @pipeline.last_timings
      return @renderer.render("(no profile -- run a query first)", mode: :dim) if timings.nil? || timings.empty?
      total = timings.values.sum
      lines = timings.map { |stage, ms| "  %-22s %dms" % [stage, ms] }
      (["last request:"] + lines + ["  " + "-" * 26, "  %-22s %dms" % ["total", total]]).join("
")
    end
    def format_dmesg_lines
      @logging.dmesg(DMESG_LINES).split("
").map { |l| @renderer.format_dmesg(l) }.join("
")
    end
    def toggle_staging(args)
      case args.first
      when "on"
        @config["staging_enabled"] = true
        @config.save!
        puts @renderer.render("staging: on", mode: :dim)
      when "off"
        @config["staging_enabled"] = false
        @config.save!
        puts @renderer.render("staging: off", mode: :dim)
      else
        status = @config["staging_enabled"] ? "on" : "off"
        puts @renderer.render("staging: #{status} -- /staging on|off", mode: :dim)
      end
    end
    def toggle_tts(args)
      case args.first
      when "on"
        @tts_on = Speech.available?
        puts @renderer.render("tts: #{@tts_on ? "on" : "unavailable"}", mode: :dim)
      when "off"
        @tts_on = false
        puts @renderer.render("tts: off", mode: :dim)
      else
        puts @renderer.render("tts: #{@tts_on ? "on" : "off"} -- /tts on|off", mode: :dim)
      end
    end
    def run_scan_command(args)
      depth = args.include?("deep") ? :deep : :standard
      target = File.join(@root, "lib")
      puts @renderer.render("scanning #{target} (#{depth})...", mode: :dim)
      result = @scanner.scan_dir(target, depth: depth)
      unless result.respond_to?(:ok?) && result.ok?
        puts @renderer.render("scan failed", mode: :error)
        return
      end
      by_rule = group_violations_by_rule(result.value!)
      total = by_rule.values.sum(&:size)
      @violations = total
      if total.zero?
        puts @renderer.render("clean -- no violations", mode: :success)
        return
      end
      render_violations_by_rule(filter_seen_violations(by_rule))
      puts @renderer.render("#{total} total violations", mode: :warning)
    end
    def group_violations_by_rule(scan_results)
      by_rule = Hash.new { |h, k| h[k] = [] }
      scan_results.each do |_file, file_result|
        next unless file_result.respond_to?(:ok?) && file_result.ok?
        file_result.value!.each { |v| by_rule[v[:rule].to_s] << v }
      end
      by_rule
    end
    def filter_seen_violations(by_rule)
      by_rule.transform_values do |vs|
        vs.reject do |v|
          key = "#{v[:rule]}:#{v[:line]}:#{v[:message].to_s[0, 60]}"
          seen = @seen_violations.key?(key)
          @seen_violations[key] = true
          seen
        end
      end.reject { |_, vs| vs.empty? }
    end
    def render_violations_by_rule(by_rule)
      ordered = by_rule.sort_by do |_, vs|
        sev_rank = { critical: 0, error: 1, warning: 2, style: 3 }
        [sev_rank.fetch(vs.first&.dig(:severity) || :warning, 2), -vs.size]
      end
      ordered.each do |rule, violations|
        sev = violations.first&.dig(:severity) || :warning
        icon = SEVERITY_ICON.fetch(sev, "!")
        puts @renderer.render("[#{icon}][#{rule}] #{violations.size}", mode: :dim)
        violations.first(3).each do |v|
          puts "  L#{v[:line]}: #{v[:message].to_s[0, 88]}"
          if v[:fix]&.any?
            hint = v[:fix].to_s.lines.first.to_s.strip[0, 80]
            puts "    fix: #{hint}" unless hint.empty?
          end
        end
        puts "  ... +#{violations.size - 3} more" if violations.size > 3
      end
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
        puts "
#{@renderer.render("boot scan: #{count} violation(s) -- /scan for details", mode: :dim)}"
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
        print "[K" if $stdout.isatty
        value = ok.value
        text = value.is_a?(Hash) && value[:rendered] ? value[:rendered] : value.to_s
... 155 lines truncated (455 total)
```

## `lib/master/code_index.rb`
```rb
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
      @built_at = nil
    end
    # Build the entire index. Optional +path+ restricts to a subtree.
    def build(path: nil)
      target = path ? File.expand_path(path, @root) : @root
      files = Dir.glob(File.join(target, "**", "*.rb"))
                  .reject { |f| f.include?("/vendor/") }
      @symbols.clear
      @references.clear
      files.each { |f| index_file(f) }
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
      [header, title, *classes].join("
")
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
        return super unless method_name.match?(/A[_a-z][a-z0-9_]*[!?]?z/i) && method_name.length > 1
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

## `lib/master/cognitive_monitor.rb`
```rb
# frozen_string_literal: true
module Master
  # Tracks cognitive load of agent sessions using Miller's 7±2 working‑memory model.
  class CognitiveMonitor
    LOAD_MAX    = 7
    STACK_MAX   = 9
    SWITCH_MAX  = 3
    COMPRESS_AT = 0.6 # 40 % compression ratio
    FLOW_STATES = {
      optimal:    0.0..0.2,
      focused:    0.2..0.5,
      stressed:   0.5..0.7,
      overloaded: 0.7..Float::INFINITY
    }.freeze
    Entry = ::Struct.new(:concept, :weight, :ts, keyword_init: true)
    attr_reader :load, :switches, :flow_state
    def initialize
      @load       = 0.0
      @stack      = [] # Array<Entry>
      @switches   = 0
      @flow_state = :optimal
    end
    def push(concept, weight: 1.0)
      compress! if (@load + weight) > LOAD_MAX
      @stack << Entry.new(concept: concept, weight: weight, ts: Time.now.to_i)
      @load += weight
      evict_excess!
      self
    end
    def context_switch!
      @switches += 1
      reset_switches! if @switches > SWITCH_MAX
      self
    end
    def overloaded?
      @load > LOAD_MAX || @stack.size > STACK_MAX || @switches > SWITCH_MAX
    end
    def reset!(keep_recent: 3)
      @stack = @stack.last(keep_recent)
      @load = @stack.sum(&:weight)
      @switches = 0
      @flow_state = :focused
      self
    end
    def state
      {
        load:          @load.round(2),
        stack_size:    @stack.size,
        switches:      @switches,
        flow_state:    @flow_state,
        overload_risk: [(@load / LOAD_MAX * 100), 100].min.round(1),
        complexity:    complexity_label
      }
    end
    def update_flow(context_switches: @switches, error_rate: 0.0)
      distraction = [context_switches * 0.2 + error_rate, 1.0].min
      @flow_state = FLOW_STATES.find { |_k, r| r.cover?(distraction) }&.first || :overloaded
      self
    end
    private
    def compress!
      groups = @stack.group_by { |e| e.concept[0, 5] }
      @stack = groups.map do |_key, entries|
        total_weight = entries.sum(&:weight) * COMPRESS_AT
        first = entries.first
        Entry.new(
          concept: "#{first.concept}[×#{entries.size}]",
          weight:  total_weight,
          ts:      Time.now.to_i
        )
      end
      @load = @stack.sum(&:weight)
    end
    def evict_excess!
      @stack.shift while @stack.size > STACK_MAX
      @load = @stack.sum(&:weight)
    end
    def reset_switches!
      @switches = 0
      @flow_state = :focused
    end
    def complexity_label
      case @load
      when 0..2 then :simple
      when 2..5 then :moderate
      when 5..7 then :complex
      else          :overload
      end
    end
  end
end
```

## `lib/master/config.rb`
```rb
# frozen_string_literal: true
require 'yaml'
require 'fileutils'
module Master
  class Config
    DEFAULT_WEB_PORT = 10_002
    DEFAULTS = {
      'model'          => 'meta-llama/llama-3.3-70b-instruct:free',
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
end
```

## `lib/master/context_window.rb`
```rb
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
        content: "[Context compacted]

#{summary}"
      )
      Result.ok(:compacted)
    rescue StandardError => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end
```

## `lib/master/council/deliberation.rb`
```rb
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
          return Result.err("council: veto from #{veto[:persona]}
#{veto[:feedback]}", category: :validation)
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
        ctx = context ? "
Context: #{context}
" : ''
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

## `lib/master/council/personas.rb`
```rb
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
end
```

## `lib/master/diff_stager.rb`
```rb
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
      end.join("
")
    end
    # Colored unified diff for one entry
    def render_diff(id, pastel)
      entry = @pending.find { |e| e.id == id }
      return pastel.red("no staged change with id #{id}") unless entry
      short = entry.path.sub(@root + "/", "")
      header = "#{pastel.bold(short)} #{pastel.dim(entry.diff_stats)}
"
      diff_lines = entry.diff.to_s.lines.map do |line|
        case line[0]
        when "+" then pastel.green(line.chomp)
        when "-" then pastel.red(line.chomp)
        when "@" then pastel.cyan(line.chomp)
        else          pastel.dim(line.chomp)
        end
      end
      header + diff_lines.join("
")
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
```rb
# frozen_string_literal: true
require 'monitor'
module Master
  class EventBus
    include MonitorMixin
    BOOT_TIME = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    def initialize(log: nil)
      super()
      @subscribers   = Hash.new { |h, k| h[k] = [] }
      @log           = log
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
      @log&.push("[#{ts}ms] #{event}: #{payload.except(:event, :ts).inspect}")
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
        "\A" + Regexp.escape(pattern).gsub('\*\*', '.*').gsub('\*', '[^:]*') + "\z"
      )
      re.match?(event)
    end
  end
end
```

## `lib/master/git_operations.rb`
```rb
# frozen_string_literal: true
require "open3"
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

## `lib/master/governor.rb`
```rb
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

## `lib/master/introspection/friction.rb`
```rb
# frozen_string_literal: true
require "json"
module Master
  module Introspection
    class Friction
      def initialize(root:)
        @path    = File.join(root, ".master", "friction.jsonl")
        @records = []
      end
      def record(event:, context: nil)
        entry = { ts: Time.now.to_i, event:, context: }
        @records << entry
        File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
      end
      def summary
        return "(no friction recorded)" if @records.empty?
        counts = @records.group_by { |r| r[:event] }.transform_values(&:size)
        counts.sort_by { |_, v| -v }.map { |k, v| "#{k}: #{v}" }.join("
")
      end
    end
  end
end
```

## `lib/master/introspection/self_map.rb`
```rb
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
        axioms_path = File.join(@root, "data", "axioms.yml")
        return {} unless File.exist?(axioms_path)
        axioms = YAML.safe_load_file(axioms_path)
        source = Dir.glob(File.join(@root, "lib/**/*.rb")).map { |f| File.read(f) }.join
        axioms.transform_values { |ids|
          ids.count { |id| source.include?(id.to_s) }
        }
      end
    end
  end
end
```

## `lib/master/logging.rb`
```rb
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
      @buffer.to_a.last(lines).join("
")
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
```rb
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
      transport = cfg["transport"] || "stdio"
      client    = case transport
                  when "stdio"
                    ::RubyLLM::MCP::Client.new(
                      name:,
                      transport: :stdio,
                      command:   cfg["command"],
                      args:      cfg["args"] || []
                    )
                  when "sse"
                    ::RubyLLM::MCP::Client.new(
                      name:,
                      transport: :sse,
                      url:       cfg["url"]
                    )
                  end
      client.connect
      @clients[name] = client
      @bus&.publish("mcp:server_connected", name:, transport:)
    rescue StandardError => e
      @bus&.publish("mcp:server_failed", name:, error: e.message)
    end
    def load_servers
      path = File.join(@root, CONFIG_PATH)
      return {} unless File.exist?(path)
      require "yaml"
      YAML.safe_load_file(path, aliases: true) || {}
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
```rb
# frozen_string_literal: true
require "yaml"
require "fileutils"
module Master
  # Persistent cross-session memory store with TF-IDF semantic search.
  # Stored at .master/memory.yml — survives restarts.
  class Memory
    def initialize(root: Dir.pwd)
      @path  = File.join(root, ".master", "memory.yml")
      @store = load_store
    end
TTL_DAYS = 90
def remember(key, value)
  prune_stale! if @store.size > 40
  @store[key.to_s] = { "value" => value.to_s, "ts" => Time.now.to_i }
  persist
end
    # Keys are always stored and retrieved as strings.
    def recall(key)
      @store.dig(key.to_s, "value")
    end
    def forget(key)
      @store.delete(key.to_s)
      persist
    end
    def all = @store.transform_values { |v| v.is_a?(Hash) ? v["value"] : v }
# Returns top-5 most recent active entries for system prompt injection.
def context_summary
  active = @store.reject { |k, _| k.to_s.start_with?("archive/") || k == "_consolidated_summary" }
  return nil if active.empty?
  recent = active.sort_by { |_, v| -(v.is_a?(Hash) ? v["ts"].to_i : 0) }.first(5)
  lines  = recent.map { |k, v| "- #{k}: #{v.is_a?(Hash) ? v["value"] : v}" }
  archived_n = @store.count { |k, _| k.to_s.start_with?("archive/") }
  summary    = recall("_consolidated_summary")
  header = summary ? "Memory (#{summary.to_s[0, 80]}):" : "Memory:"
  header += " [+#{archived_n} archived]" if archived_n > 0
  "#{header}
#{lines.join("
")}"
end
    # TF-IDF ranked search across all memory entries.
    # Returns array of {key:, value:, score:} hashes, highest score first.
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
# Three-phase memory consolidation inspired by OpenClaw dreaming.
# Light: score. Deep: archive stale. REM: LLM summary if agent given.
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
      .join("
")
    unless active_text.strip.empty?
      summary = agent.ask_once(
        "Summarize in 2 concise sentences, preserving all key facts:
#{active_text}"
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
      text.downcase.scan(/[a-z]{2,}/)
    end
    # Log-weighted term frequency similarity — no external gem required.
    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty?
      freq = doc_terms.tally
      query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
    end
  end
end
```

## `lib/master/metrics.rb`
```rb
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
```rb
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
    CONSTITUTION_PATH = File.join(Master::ROOT, "data", "constitution.yml").freeze
    STRUNK_PATH       = File.join(Master::ROOT, "data", "strunk.yml").freeze
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
      const_path = root ? File.join(root, "data", "constitution.yml") : CONSTITUTION_PATH
      strunk_path = root ? File.join(root, "data", "strunk.yml") : STRUNK_PATH
      @constitution = File.exist?(const_path)  ? YAML.safe_load_file(const_path)  : {}
      @strunk       = File.exist?(strunk_path) ? YAML.safe_load_file(strunk_path) : {}
    end
    # Injected before every LLM call. Pulls from axioms, constitution, and strunk.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end
    private
def build_system_prompt
  ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
  banned  = (@constitution.dig("banned_output") || [])
  no_open = (@strunk.dig("preambles") || []).first(4)
  no_end  = (@strunk.dig("endings")   || []).first(3)
  ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
  ls << "Evidence only: show diff or file content, never assert. Active voice."
  kernel = @axioms.kernel
  ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
  phil = @axioms.philosophy(limit: 10)
  ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
  golden = @constitution["golden_rule"]
  ls << "Rule: #{golden}." if golden
  ls.join("
")
end
  end
end
```

## `lib/master/pipeline.rb`
```rb
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
```rb
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
```rb
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

## `lib/master/quality/auto_testing.rb`
```rb
# frozen_string_literal: true
require "English"
module Master
  module Quality
    class AutoTesting
      CHECKS = {
        "rubocop" => "bundle exec rubocop --format simple",
        "brakeman" => "bundle exec brakeman -q",
        "reek" => "bundle exec reek"
      }.freeze
      def run
        results = CHECKS.map { |name, cmd| [name, run_cmd(cmd)] }.to_h
        coverage = run_cmd("bundle exec rspec --format progress")
        { checks: results, coverage_gate: coverage }
      end
      private
      def run_cmd(cmd)
        ok = system("/bin/sh", "-c", "command -v #{cmd.split[2] || cmd.split.first} >/dev/null 2>&1")
        return { status: :skipped, reason: "missing dependency", command: cmd } unless ok
        output = IO.popen(["/bin/sh", "-c", "#{cmd} 2>&1"], &:read)
        { status: $CHILD_STATUS.success? ? :pass : :fail, command: cmd, output: output.lines.first(20).join }
      rescue StandardError => e
        { status: :fail, command: cmd, output: e.message }
      end
    end
  end
end
```

## `lib/master/reasoning/modes.rb`
```rb
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
```rb
# frozen_string_literal: true
# encoding: utf-8
require "pastel"
require "open3"
module Master
  DEFAULT_WEB_PORT = 10002
  class Renderer
    TICK  = "✔".freeze
    CROSS = "✘".freeze
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
      lines.join("
")
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
end
```

## `lib/master/result.rb`
```rb
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
      def value!                = raise(Master::UnwrapError, "Err#value! called: #{@message}")
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
```rb
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
```rb
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
        data.dig("continuity", "openrouter", "free_latest").to_a
      end
      def ferrum_latest
        data.dig("continuity", "ferrum_web_chat", "free_latest").to_a
      end
      def data
        path = File.join(@root, "data", "fallback_models.yml")
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
```rb
# frozen_string_literal: true
require "yaml"
module Master
  module Routing
    class ModelRouter
      # Phrases that indicate the model is uncertain — trigger escalation.
      UNCERTAINTY_PHRASES = %w[
        i'm not sure i don't know cannot determine unclear uncertain
        might be possibly probably not limited information i cannot i am unable
        i lack the not enough information i would need more
      ].freeze
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

## `lib/master/scan/rule.rb`
```rb
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
```rb
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
            match = line.strip.match(/AISSUE:(d+):(.+)z/)
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
```rb
# frozen_string_literal: true
require "yaml"
require "prism"
module Master
  module Scan
    module Rules
      # AxiomCoverageRule — meta-level rule. Checks that every axiom in
      # axioms.yml has at least one scan rule referencing it, and that all
      # @axiom_tags assignments in scan rules correspond to real axioms.
      #
      # Previously used a greedy regex /:([A-Z_]{3,})/ which matched any
      # uppercase symbol anywhere in the file — method-name symbols, hash
      # keys, constants — producing false positives. Now parses rule files
      # with Prism and extracts only the literal symbols assigned to
      # @axiom_tags.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every axiom must have scan rule coverage; every tag must be a real axiom"
          @severity    = :warning
          @axiom_tags  = []
        end
        def check(code, path:)
          # Only run when scanning the scan rules directory itself.
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root
          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []
          # Orphaned tags: in code but not in axioms.yml
          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in axioms.yml — define it or remove the tag")
          end
          # Uncovered axioms: in axioms.yml but no scan rule covers them
          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "axiom #{id} has no scan rule coverage — add a rule or accept as advisory")
          end
          findings
        end
        private
        def load_axiom_ids
          path = File.join(@root, "data", "axioms.yml")
          return [] unless File.exist?(path)
          data = YAML.safe_load_file(path)
          ids  = []
          ids += data.dig("kernel")&.keys || []
          ids += (data.dig("philosophy", "prioritized_top_25") || []).map { |a| a["id"] }
          ids += (data.dig("ux", "nielsen_heuristics") || []).map { |a| a["id"] }
          ids.map(&:to_s).uniq
        rescue StandardError
          []
        end
        # Parse each rule file with Prism and collect only the symbols in
        # the RHS of `@axiom_tags = [...]`. Falls back to an empty list on
        # parse error — never crashes the scan.
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
        # Walks the Prism AST and collects symbols assigned to @axiom_tags.
        # Matches both forms:
        #   @axiom_tags = [:ONE_JOB, :CQS]
        #   @axiom_tags = %i[ONE_JOB CQS]
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
```rb
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
          scan_lines(code, /^s*rescues*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/conceptual_rule.rb`
```rb
# frozen_string_literal: true
require "yaml"
module Master
  module Scan
    module Rules
      # ConceptualRule — LLM-based axiom violation detection.
      #
      # Checks all philosophy axioms that resist lexical detection:
      # NO_SURPRISES, COMPOSABLE, REVERSIBLE, IDEMPOTENT, JUST_ENOUGH, etc.
      # Runs only at :deep depth. Makes one LLM call per file and parses
      # structured findings. Skips if no agent is set.
      #
      # Meta-note: this rule itself must satisfy JUST_ENOUGH (one LLM call,
      # not one per axiom) and GUARD_EXPENSIVE (depth gate).
      class ConceptualRule < Rule
        AXIOMS_PATH = File.join(Master::ROOT, "data", "axioms.yml").freeze
        CODE_SNIPPET_LIMIT = 2000
        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based philosophy axiom review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_philosophy_axioms
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
        def load_philosophy_axioms
          data = YAML.safe_load_file(AXIOMS_PATH)
          entries = data.dig("philosophy", "prioritized_top_25") || []
          entries.each_with_object({}) { |e, h| h[e["id"]] = e["statement"] }
        end
        def build_prompt(code, path)
          axiom_list = @axioms.map { |id, stmt| "#{id}: #{stmt}" }.join("
")
          <<~PROMPT
            Review #{File.basename(path)} against these axioms. List ONLY clear violations.
            Format each as: AXIOM_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN
            Axioms:
            #{axiom_list}
            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end
        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"
          response.lines.filter_map do |line|
            match_data = line.strip.match(/A([A-Z_]+):(d+):(.+)z/)
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # CqsRule — detects Command/Query Separation violations.
      # A method should either return a value (query) or change state (command), not both.
      # Flags methods named like queries (get_*, find_*, fetch_*, load_*) that also
      # contain state-mutating patterns (@x =, save!, update!, write).
      class CqsRule < Rule
        QUERY_PREFIX   = /^s+defs+(get_|find_|fetch_|load_|read_|list_|show_|describe_)w+/.freeze
        MUTATION_IN_BODY = /(@w+s*=(?!=)|.save[!s]|.update[!s]|.write[!s]|File.write)/.freeze
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
              depth += line.scan(/do|begin|if|case|def/).size
              depth -= line.scan(/end/).size
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
```rb
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
            key = block.gsub(/s+/, " ").strip
            seen[key] += 1
          end
          seen.each do |block_key, count|
            next if count < OCCUR_MIN
            first_line = code.lines.index { |l|
              block_key.start_with?(l.gsub(/s+/, " ").strip[0, 20])
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # ExplicitRule — detects implicit/opaque patterns that violate EXPLICIT.
      # Flags: bare rescue, implicit return of nil, magic number literals,
      # single-letter variable names outside loops, and undefined method patterns.
      class ExplicitRule < Rule
        RESCUE_NIL   = /rescues+nil/.freeze
        MAGIC_NUM    = /[^:]([2-9]d{2,}|[1-9]d{3,})(?!s*[#=])/.freeze
        OPAQUE_VAR   = /^s+[a-z]s*=(?!=)/.freeze        # x = ... (not x == or x +=)
        IMPLICIT_NIL = /defs+w+[^;]*
(?:s*#[^
]*
)*s*end/.freeze  # empty method body
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
            lines[i].match?(/(?:each|map|times|upto|downto|step|fors+w)/)
          end
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/frozen_string_rule.rb`
```rb
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
                   fix: "# frozen_string_literal: true
" + code)]
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/god_class_rule.rb`
```rb
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
          class_name = code.match(/class (w+)/i)&.[](1) || File.basename(path, ".rb")
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # ImmutableRule — detects mutable shared state that violates IMMUTABLE.
      # Flags: unfrozen String/Array/Hash constants, attr_accessor on data objects,
      # class-level mutable variables (@@), and global variable mutations ($x =).
      class ImmutableRule < Rule
        UNFROZEN_CONST  = /^s+[A-Z][A-Z0-9_]+ s*=s*(?:"[^"]*"|'[^']*'|[|{)(?!.*.freeze)/.freeze
        CLASS_VAR_WRITE = /^s+@@w+s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^s+$w+s*=(?!=)/.freeze
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
```rb
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
            if line.match?(/^s*def /)
              method_start = num
              method_name  = line.match(/def (w+)/)[1]
              depth        = 1
            elsif method_start
              depth += line.scan(/do|begin|if|case|class|module|def/).size
              depth -= line.scan(/end/).size
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # NielsenRule — enforces Nielsen Norman Group's 10 Usability Heuristics
      # at the code level: API design, error messages, output behavior.
      class NielsenRule < Rule
        # H9: Error messages must describe the problem — bare string raises with no guidance
        BARE_RAISE       = /raises+["'][^"']{0,20}["']/.freeze
        # H9: Result.err with no message or single-word message
        THIN_ERR         = /Result.err(["'][a-z_]{1,15}["'](?:s*))/.freeze
        # H4: Inconsistent boolean naming — mix of is_/has_/can_ with plain predicates
        # H6: Positional args over 3 — harms recognition (caller can't tell what each is)
        POSITIONAL_HEAVY = /defs+w+((?:[^,)]+,){3,}[^*&]/.freeze
        # H8: Aesthetic minimalism — debug inspect calls (p/pp/pry) left in production
        DEBUG_OUTPUT     = /^s+(?:p|pp|binding.pry|debugger)s+(?!.*#s*rubocop)/.freeze
        # H3: User control — destructive methods without bang or guard comment
        SILENT_DELETE    = /(?:FileUtils.rm|File.delete|Dir.rmdir)s*((?!.*#.*safe)/.freeze
        # H2: Real world match — internal jargon in user-facing strings
        JARGON           = /(?:raise|Result.err)(.*(?:nil|exception|stacktrace|backtrace|segfault|errno)/.freeze
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
```rb
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
        BOOL_POSITIONAL = /defs+w+([^)]*,s*(true|false)s*[,)]/.freeze
        # unless !condition (double negation)
        DOUBLE_NEG      = /unlesss+!/.freeze
        # Negative boolean attribute names
        NEG_BOOL_ATTR   = /attr_w+s+:(?:not_|no_|without_|disabled?_|skip_)w+/.freeze
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
            if line.match?(/^s+defs+w+?/)
              in_predicate = true
              pred_line    = num
              depth        = 1
            elsif in_predicate
              depth += line.scan(/do|begin|if|case|def/).size
              depth -= line.scan(/end/).size
              if depth <= 0
                in_predicate = false
              elsif line.match?(/(@w+s*=(?!=)|.save[!s]|.update[!s]|File.write)/)
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
```rb
# frozen_string_literal: true
require "yaml"
module Master
  module Scan
    module Rules
      # PruneRule — flags hedge words and preamble phrases in Ruby comments.
      # Patterns loaded from data/strunk.yml — the same source the Prune stage uses at runtime.
      # Single source of truth: no hardcoded patterns here.
      class PruneRule < Rule
        DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
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
          @rules ||= (File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : nil) || {}
        rescue StandardError
          @rules = {}
        end
        # Build regex from hedge entries in strunk.yml: [{pattern:, replace:}, ...].
        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            next unless h.is_a?(Hash)
            pat = h["pattern"].to_s.strip
            pat.empty? ? nil : Regexp.escape(pat)
          }
          return nil if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError
          nil
        end
        # Build regex from preamble strings in strunk.yml.
        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return nil if phrases.empty?
          /#.*(?:#{phrases.join("|")})/i
        rescue StandardError
          nil
        end
      end
    end
  end
end
```

## `lib/master/scan/rules/reek_rule.rb`
```rb
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
```rb
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # SelfExplainingRule — detects names that obscure intent, violating SELF_EXPLAINING.
      # Flags method/variable names that are abbreviations, noise words, or too generic
      # to reveal purpose without reading the implementation.
      class SelfExplainingRule < Rule
        NOISE_NAMES  = /(do_it|handle|process|run_it|execute_it|go|doit)/.freeze
        ABBREV_METHOD = /^s+defs+(tmp|res|ret|val|obj|thingy|stuff|thing|data2?|info2?)/.freeze
        ABBREV_VAR    = /(tmp|res|ret|val|obj|arr|lst|hsh|idx|cnt|num|str)s*=(?!=)/.freeze
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
```rb
# frozen_string_literal: true
module Master
  module Scan
    module Rules
      # SrpRule — Single Responsibility Principle.
      # A class should have one reason to change. Flags classes whose public methods
      # span multiple concern domains (persistence, rendering, validation, networking, parsing).
      class SrpRule < Rule
        CONCERNS = {
          persistence: /(save|load|read_w|write_w|persist|store_w|fetch_w|find_by|delete|destroy|insert|upsert)/,
          rendering:   /(render|display|format_w|present|to_html|draw|paint|emit|output_w)/,
          validation:  /(valid?|validate[^d]|check_w|verify_w|assert_w|ensure_w|guard_w)/,
          networking:  /(request_w|http_w|send_request|receive_w|connect_w|socket_w)/,
          parsing:     /(parse_w|tokenize|lex_w|extract_w|decode_w|encode_w|deserialize|serialize)/,
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
          public_methods = code.scan(/^s{2,8}defs+(w+)/).flatten
          return [] if public_methods.size < 4
          concerns_found = CONCERNS.select { |_, pat| public_methods.any? { |m| m.match?(pat) } }
          return [] if concerns_found.size < 2
          class_name = code.match(/classs+(w+)/i)&.[](1) || File.basename(path, ".rb")
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
```rb
# frozen_string_literal: true
require "yaml"
module Master
  module Scan
    # Scanner — runs configured scan rules against Ruby source files.
    #
    # scan_dir parallelizes across files with a thread pool sized to CPU count.
    # Each file is independent; rules share no mutable state between files.
    class Scanner
      DEPTHS_PATH  = File.join(Master::ROOT, "data", "scan_depths.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min  # cap at 8 to avoid overwhelming VPS
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
      # Parallel file scan — spawns up to POOL_SIZE threads, one per file.
      # Results preserve input order.
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
        @depth_rules ||= YAML.safe_load_file(DEPTHS_PATH, aliases: true)
      rescue StandardError
        @depth_rules = {}
      end
      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.id) }
      end
    end
  end
end
```

## `lib/master/security/injection_guard.rb`
```rb
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
        /[SYSTEM]/i,
        /###s*SYSTEM/i,
        /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
        /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
        /jailbreak/i,
      ].freeze
      # Shell-injection pattern checked separately (multiline, heavier regex).
      SHELL_INJECTION_RE = /```(?:bash|sh|zsh|shell)
.*?(?:rms+-rf|curl.*?|s*(?:bash|sh)|wget.*?|s*(?:bash|sh))/im.freeze
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
```rb
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
```rb
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
```rb
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

## `lib/master/soul.rb`
```rb
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
      "SOUL.md v#{version} | persona: #{persona}
#{voice}"
    end
    def changelog
      block = @soul[/## Changelog
+(.*?)(?=
## |z)/m, 1].to_s.strip
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
      out.empty? ? "(no visible changes)" : out.join("
")
    end
    def approve
      return "no pending proposal" unless File.exist?(PROPOSAL_PATH)
      proposal = File.read(PROPOSAL_PATH)
      old_version = extract_version
      new_version = bump_version(old_version, :patch)
      # Inject new version into proposal
      updated = proposal.sub(/Version: [d.]+/, "Version: #{new_version}")
      # Update changelog entry
      date    = Time.now.strftime("%Y-%m-%d")
      entry   = "| #{new_version} | #{date} | Evolution Protocol change | Approved via `soul approve` |
"
      updated = updated.sub(/| 1.0.0 |/, entry + "| 1.0.0 |")
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
      voice  = @soul[/## Voice
+(.*?)(?=
## |z)/m, 1].to_s.strip
      values = @soul[/## Values
+(.*?)(?=
## |z)/m, 1].to_s.strip
      "#{voice}

#{values}"
    end
# Auto-propose a soul amendment when scan violations cluster on one rule.
# Called by AutoLoop when the same rule fails across 3+ consecutive cycles.
def propose_from_violations(rule_id, sample_violations, agent: @agent)
  return "no agent available" unless agent
  examples = sample_violations.first(3).map { |v| "  L#{v[:line]}: #{v[:message]}" }.join("
")
  rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} " \
              "violations across multiple files and cycles:
#{examples}
" \
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
      @soul[/^Version: ([d.]+)/, 1] || "1.0.0"
    end
    def extract_field(name)
      @soul[/^#{Regexp.escape(name)}:s*(.+)/, 1].to_s.strip
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
```rb
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
```rb
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
      def multi_file_diff?(ctx) = extract_payload(ctx).scan(/^(?:---|+++)s+[ab]/(.+)$/).uniq.size >= 2
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
        text.scan(/praise/).size >= 3
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
```rb
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
```rb
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
```rb
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
        coding:   /(?:def |class |module |require |.rb|fixs+(?:thes+)?(?:bug|error|issue)|refactor|implement|writes+(?:as+)?(?:method|class|function|test)|adds+(?:as+)?(?:method|feature)|```(?:ruby|python|js|javascript|bash))/i,
        research: /(?:search|finds+(?:all|every|info)|research|looks+up|whats+is|explains+(?:how|what|why)|tells+mes+about)/i,
        qa:       /?(?:s*$|s+[A-Z])/m,
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
          path = nil if path&.match?(/A(?:all|everything|the|code|codebase)z/i)
          path.to_s
        when "cycles"
          (match[1] || msg[/(d+)s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "on_off"
          msg.match?(/(?:off|disable|stop|av|skrus+av)/i) ? "off" : "on"
        when "first_group"
          match.captures.compact.first.to_s.strip
        when "persona_name"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul_subcmd"
          msg[/(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders_subcmd"
          msg.match?(/list|show/i) ? "list" : ""
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
```rb
# frozen_string_literal: true
module Master
  module Stages
    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /As*/([w-]+)s*(.*)/m.freeze
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

## `lib/master/stages/lint.rb`
```rb
# frozen_string_literal: true
module Master
  module Stages
    # Lint — run static analysis after execution when auto-testing is enabled.
    # Uses the shared scanner so rules are consistent with sweep/autoloop.
    class Lint
      def initialize(scanner:, config:)
        @scanner = scanner
        @config  = config
      end
      def call(ctx)
        return Result.ok(ctx) unless @config.auto_testing?
        root   = ctx[:path].to_s
        root   = Master::ROOT if root.empty?
        report = @scanner.scan_dir(root, depth: :standard)
        return Result.err(report.message, category: :unknown) if report.respond_to?(:err?) && report.err?
        Result.ok(ctx.merge(lint_report: report))
      rescue => e
        Result.err("lint: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/stages/memo.rb`
```rb
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
      REMEMBER_RE = /remembers+(?:thats+)?(.{10,200}?)(?:[.!]|$)/im.freeze
      DECISION_RE = /we(?:'ve|s+have)?s+decideds+(?:tos+)?(.{10,150}?)(?:[.!]|$)/im.freeze
      PREFER_RE   = /Is+prefers+(.{5,100}?)(?:[.!]|$)/im.freeze
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
          key = "pref_#{pref.split.first(3).join("_").downcase.gsub(/W/, "")}"
          @memory.remember(key, pref.strip)
        end
      end
    end
  end
end
```

## `lib/master/stages/prune.rb`
```rb
# frozen_string_literal: true
require "yaml"
module Master
  module Stages
    # Prune — strip AI throat-clearing from LLM responses.
    # Rules loaded from data/strunk.yml.
    #
    # Fence-aware: previously bailed entirely on any response containing a
    # triple-backtick. Now splits into prose/code segments, prunes prose,
    # leaves code blocks untouched.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze
      def call(ctx)
        output = ctx[:output]
        return Result.ok(ctx) unless output.is_a?(String) && !output.empty?
        cleaned = prune_mixed(output)
        Result.ok(ctx.merge(output: cleaned.strip))
      end
      private
      # Split on fenced code blocks, prune only the prose segments.
      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          if seg.start_with?("```")
            seg
          else
            strip_rules(seg)
          end
        }.join
      end
      def strip_rules(text)
        cleaned = text
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/A#{Regexp.escape(p)}s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/s*#{Regexp.escape(e)}s*z/i, "") }
        # Hedges are plain-string replacements, not regex patterns.
        rules.fetch("hedges",    []).each { |h| cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s) }
        cleaned
      end
      def rules
        @rules ||= File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : {}
      rescue StandardError
        @rules = {}
      end
    end
  end
end
```

## `lib/master/stages/render.rb`
```rb
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
```rb
# frozen_string_literal: true
module Master
  module Stages
    # Route — attach the correct handler to the context.
    # :command → looks up registered command object.
    # :llm     → uses the agent.
    class Route
      def initialize(commands:, agent:)
        @commands = commands
        @agent    = agent
      end
      # Register a command handler after construction (used by build for circular deps).
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
```rb
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
      end.join("
")
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

## `lib/master/state/experience.rb`
```rb
# frozen_string_literal: true
require "json"
require "digest"
module Master
  module State
    # Experience store — records (plan → outcome) pairs across runs.
    #
    # Used by future PlanTree/MCTS stages (not wired in this patch) to bias
    # plan selection toward sequences that have succeeded before.
    # Minimal drop-in: no vector DB, no embeddings, exact-match on plan
    # signature. Adding embedding-based similarity is a later step.
    #
    # Design follows the ChatGPT-session sketch with two critical additions:
    #   1. Score decay (0.99 per record) to avoid permanent lock-in on
    #      plans that were good once and wouldn't be now.
    #   2. Small exploration noise added at read time so novel plans aren't
    #      permanently dominated by historically successful ones.
    #
    # File format: JSON at .master/experience.json, keyed by plan signature.
    class Experience
      DECAY        = 0.99
      EXPLORE_NOISE = 0.05   # ±5% random perturbation on recall
      def initialize(root:)
        @path = File.join(root, ".master", "experience.json")
        FileUtils.mkdir_p(File.dirname(@path))
      end
      # Record the outcome of a plan. `plan` is any array-of-hashes or
      # array-of-symbols; we derive a stable signature from it.
      # `score` should be roughly in [-1.0, +1.0].
      def record(plan:, score:)
        data = load_data
        key  = signature(plan)
        entry = data[key] ||= { "count" => 0, "sum" => 0.0, "updated_at" => 0 }
        entry["sum"]        = (entry["sum"] * DECAY) + score.to_f
        entry["count"]      = (entry["count"] * DECAY) + 1
        entry["updated_at"] = Time.now.to_i
        write_data(data)
        entry
      end
      # Return the decayed-average score for a plan, with a small amount
      # of exploration noise so novel candidates can still win.
      def score(plan)
        data = load_data
        entry = data[signature(plan)]
        base  = entry ? (entry["sum"] / [entry["count"], 1.0].max) : 0.0
        base + ((rand * 2.0) - 1.0) * EXPLORE_NOISE
      end
      # Opportunity: retrieve top-N plans by recent average score.
      def top(limit: 5)
        data = load_data
        data.filter_map { |sig, e|
          next if e["count"].to_f.zero?
          [sig, e["sum"] / e["count"]]
        }.sort_by { |_, avg| -avg }.first(limit)
      end
      def clear!
        File.delete(@path) if File.exist?(@path)
        self
      end
      private
      # Stable plan signature — only the sequence of tool identifiers.
      # Ignores arguments on purpose: "fs_read → ast_replace → git_commit"
      # is the same strategy whether it edited user.rb or auth.rb.
      def signature(plan)
        tools = Array(plan).map { |step|
          case step
          when Hash   then (step[:tool] || step["tool"]).to_s
          when Symbol then step.to_s
          else             step.to_s
          end
        }
        Digest::SHA256.hexdigest(tools.join("->"))[0, 16]
      end
      def load_data
        return {} unless File.exist?(@path)
        JSON.parse(File.read(@path))
      rescue JSON::ParserError
        {}
      end
      def write_data(data)
        File.write(@path, JSON.generate(data))
      end
    end
  end
end
```

## `lib/master/swarm/coordinator.rb`
```rb
# frozen_string_literal: true
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
      def worker_roles = WORKER_CLASSES.keys
      private
      # Combine successful worker results into a coherent summary string.
      def synthesize(results)
        lines = results.filter_map do |role, r|
          next if role == :timeout
          next unless r.respond_to?(:ok?) && r.ok?
          val = r.value!
          text = val.is_a?(Hash) ? val.inspect : val.to_s
          "### #{role}
#{text.strip}"
        end
        lines.empty? ? "(no results)" : lines.join("

")
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
```rb
# frozen_string_literal: true
module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know)
class Worker
  # Subclasses override to prefer a lighter/heavier model for their role.
  PREFERRED_MODEL = nil
  # Phrases that signal low-confidence output.
  UNCERTAINTY_PHRASES = %w[unclear uncertain not sure cannot determine
                            i don't know limited information probably].freeze
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
        "You are a specialized #{@role} agent. #{role_description}
" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end
      # Subclasses override
      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}

Task: #{task}"
def parse_result(raw)
  text = raw.to_s.strip
  hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
  @confidence = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
  Result.ok({ text: text, confidence: @confidence })
end
      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k.to_s}: #{v.to_s}" }.join("
")
      end
    end
  end
end
```

## `lib/master/swarm/workers/analyst.rb`
```rb
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
          parts << "Code:
```
#{ctx[:code]}
```" if ctx[:code]
          parts << "Analyze: #{task}"
          parts.join("

")
        end
        def parse_result(raw)
          match_str = raw.to_s.match(/{.*}/m)&.to_s || "{}"
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
```rb
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
          parts << "Existing code:
```
#{ctx[:code]}
```" if ctx[:code]
          parts << "Spec: #{task}"
          parts.join("

")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/researcher.rb`
```rb
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
          parts << "Prior findings:
#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("

")
        end
      end
    end
  end
end
```

## `lib/master/swarm/workers/reviewer.rb`
```rb
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
          parts << "Code to review:
```
#{ctx[:code]}
```" if ctx[:code]
          parts << "Security checklist: #{CHECKLIST.join(", ")}"
          parts << "Review for: #{task}"
          parts.join("

")
        end
        def parse_result(raw)
          parsed = JSON.parse(raw.to_s.match(/{.*}/m)&.to_s || "{}")
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
```rb
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
      ".sh" => ->(p) { system("bash -n #{p}  > /dev/null 2>&1") }
    }.freeze
    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
    PROMPTS_PATH = File.join(Master::ROOT, "data", "sweep_prompts.yml").freeze
    # Regex for Ruby method/class/constant names — used by rename tracker.
    NAME_RE = /(?:defs+(w+)|classs+([A-Z]w*)|[A-Z][A-Z_]+)/.freeze
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
      "## Codebase (#{files.size} Ruby files)
" +
        files.map { |f| "  #{f}" }.join("
")
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
      fence_re = /```(?:#{Regexp.escape(lang)}|ruby|sh|bash|yaml|erb)?
(.*?)```/m
      return text.match(fence_re)[1]         if text.match?(fence_re)
      return text.match(/```
(.*?)```/m)[1] if text.match?(/```
(.*?)```/m)
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

## `lib/master/tools/apply_diff.rb`
```rb
# frozen_string_literal: true
require "open3"
module Master
  module Tools
    class ApplyDiff
      TIER        = :guarded
      NAME        = "apply_diff"
      DESCRIPTION = "Apply a unified diff patch to files in the project."
      def initialize(root:, undo:, governor:, event_bus: nil)
        @root     = File.realpath(root)
        @undo     = undo
        @governor = governor
        @bus      = event_bus
      end
      def call(diff:)
        perm = @governor.permit?(NAME, TIER, "apply patch")
        return perm if perm.err?
        affected = diff.scan(/^--- a/(.+)$/).flatten + diff.scan(/^+++ b/(.+)$/).flatten
        affected.uniq.each { |p| @undo.snapshot(File.join(@root, p)) }
        out, err, status = Open3.capture3("patch -p1", stdin_data: diff, chdir: @root)
        return Result.err("apply_diff: #{err.strip}", category: :unknown) unless status.success?
        @bus&.publish("tool:after", tool: NAME)
        Result.ok(out.strip)
      rescue => e
        Result.err("apply_diff: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/ask_llm.rb`
```rb
# frozen_string_literal: true
module Master
  module Tools
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
```rb
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
        Result.ok("# #{name} (lines #{entry[:start]}–#{entry[:end]})
#{slice}")
      end
      # Rename all occurrences of a method definition and calls
      def rename_method(fp, src, from, to)
        return Result.err("ast_edit: from/to required", category: :validation) if from.empty? || to.empty?
        return Result.err("ast_edit: invalid name: #{to}", category: :validation) unless to.match?(/A[a-z_][a-zA-Z0-9_]*[?!]?z/)
        @undo.snapshot(fp)
        updated = src
          .gsub(/defs+#{Regexp.escape(from)}/, "def #{to}")
          .gsub(/#{Regexp.escape(from)}s*(/, "#{to}(")
          .gsub(/#{Regexp.escape(from)}(?!s*[:=])/) { |m| to }
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
        lines.insert(insert_at, "
", code.chomp + "
")
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
```rb
# frozen_string_literal: true
module Master
  module Tools
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
```rb
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
        Result.ok("cleaned #{cleaned.size} file(s):
#{cleaned.join("
")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/git_context.rb`
```rb
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
        ref_s = (ref.to_s.empty? ? "HEAD" : ref.to_s).gsub(/[^a-zA-Z0-9._~^:-/]/, "")
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
```rb
# frozen_string_literal: true
module Master
  module Tools
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
        Result.ok(lines.join("
"))
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
```rb
# frozen_string_literal: true
require "ruby_llm"
module Master
  module Tools
    # LLM-callable wrappers around the existing Master tool instances.
    # Each class holds a reference to the underlying tool via initialize,
    # so governor, undo, and event_bus plumbing is preserved.
    module LLM
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

## `lib/master/tools/read_file.rb`
```rb
# frozen_string_literal: true
module Master
  module Tools
    class ReadFile
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
        numbered = slice.each_with_index.map { |l, i| "#{offset + i + 1}	#{l}" }.join
        suffix   = total > offset + limit ? "
[...truncated, #{total} total lines]" : ""
        result = Result.ok(numbered + suffix)
        @cache[key] = result
        result
      end
      private
      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/search_files.rb`
```rb
# frozen_string_literal: true
module Master
  module Tools
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
            results << "#{rel}:#{idx + 1}
#{ctx}"
            return Result.ok(results.join("
---
") + "
[...truncated]") if results.size >= MAX_RESULTS
          end
        end
        Result.ok(results.empty? ? "(no matches)" : results.join("
---
"))
      rescue => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end
      private
      def binary_file?(path)
        sample = File.read(path, 512) rescue ""
        sample.include?(" ")
      end
    end
  end
end
```

## `lib/master/tools/search_knowledge.rb`
```rb
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
            results << "### #{rel}:#{idx + 1}
#{ctx}"
            break if results.size >= MAX_RESULTS
          end
          break if results.size >= MAX_RESULTS
        end
        if results.empty?
          Result.ok("No matches for '#{query}' in #{topic || "all knowledge"}.")
        else
          header = "# Knowledge search: '#{query}' (#{results.size} matches)

"
          Result.ok(header + results.join("
---
"))
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
```rb
# frozen_string_literal: true
require "tty-command"
require "timeout"
require "shellwords"
module Master
  module Tools
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
        wrapped = "#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob
export ZDOTDIR=#{Shellwords.escape(zdotdir)}
export LC_ALL=C.UTF-8
cd #{Shellwords.escape(@root)}
#{command}
"
        out, err = Timeout.timeout(TIMEOUT) { @cmd.run!("zsh", input: wrapped) }
        @bus&.publish("tool:after", tool: NAME, exit_code: out.exit_status)
        if out.exit_status != 0
          Result.err("zsh: exit #{out.exit_status}
#{err.to_s.strip}", category: :unknown)
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
```rb
# frozen_string_literal: true
module Master
  module Tools
    class StrReplace
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
      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/tools/symbol_lookup.rb`
```rb
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
        Result.ok(hits.map { |h| format_hit(h) }.join("

"))
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
        lines.join("
")
      end
    end
  end
end
```

## `lib/master/tools/tree.rb`
```rb
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
        Result.ok(lines.join("
"))
      rescue StandardError => e
        Result.err("tree: #{e.message}", category: :unknown)
      end
    end
  end
end
```

## `lib/master/tools/web_search.rb`
```rb
# frozen_string_literal: true
require "net/http"
require "uri"
require "json"
module Master
  module Tools
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
        parts.empty? ? "(no results)" : parts.join("

")
      end
    end
  end
end
```

## `lib/master/tools/write_file.rb`
```rb
# frozen_string_literal: true
require "fileutils"
module Master
  module Tools
    class WriteFile
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
      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
```

## `lib/master/undo.rb`
```rb
# frozen_string_literal: true
module Master
  # Single-file undo: snapshots file content before a write, restores on demand.
  class Undo
    def initialize(session:, event_bus: nil)
      @session = session
      @bus     = event_bus
      @stack   = []
    end
    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { path:, content: }
      Result.ok(path)
    rescue => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end
    def undo!
      entry = @stack.pop
      return Result.err('nothing to undo', category: :validation) unless entry
      restore(entry[:path], entry[:content])
      @bus&.publish('undo:applied', path: entry[:path])
      Result.ok(entry[:path])
    end
    def depth = @stack.size
    private
    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end
  end
end
```

## `lib/master/unwrap_error.rb`
```rb
# frozen_string_literal: true
module Master
  # Raised when #value! is called on an Err result.
  class UnwrapError < RuntimeError; end
end
```

## `web/config/routes.rb`
```rb
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

## `web/app/controllers/application_controller.rb`
```rb
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
      @@container ||= Master.build(root: Rails.root.join("..").to_s).tap { |c| start_scheduler(c) }
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
```rb
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
          sse.write("event: tool
data: #{payload}

")
        rescue StandardError
          nil
        end
      end
      on_chunk = ->(token) {
        streamed = true
        encoded = token.to_s.gsub("\", "\\").gsub("
", "\n")
        sse.write("data: #{encoded}

")
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
          encoded = text.to_s.gsub("\", "\\").gsub("
", "\n")
          sse.write("data: #{encoded}

")
        end
      end
      sse.write("data: [DONE]

")
    rescue => e
      sse.write("data: ERROR: #{e.message}

")
      sse.write("data: [DONE]

")
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
```rb
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
        response.stream.write(": keepalive

")  # SSE comment, prevents proxy timeout
        sleep POLL_INTERVAL_S
      else
        event = received.pop(true) rescue nil
        next unless event
        response.stream.write("data: #{event.to_json}

")
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

## `web/config/application.rb`
```rb
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

---
files: 131 | lines: 10319 | truncated: 4 | est. tokens: ~12382
