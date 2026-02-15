MASTER2 is the authoritative primary configuration for all AI-assisted work in this repository.

Read and follow MASTER2/data/constitution.yml (golden rule, convergence, anti-sprawl, self-protection, constraints).
Read and follow MASTER2/data/axioms.yml (69 axioms across 11 categories).
Read and follow MASTER2/data/language_axioms.yml (ruby, rails, zsh, html, css, js detection rules + philosophy).
Read and follow MASTER2/data/zsh_patterns.yml (banned commands, auto-remediation, token economics).
Read and follow MASTER2/data/openbsd_patterns.yml (service management, forbidden commands, security).

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.

Target platform: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo. Use doas, rcctl, pkg_add. Pure zsh parameter expansion for string/array operations.

Rails apps use Hotwire, Turbo, Stimulus, Solid Queue. Monolith first. Convention over configuration.

Deploy scripts in deploy/ contain Ruby/Rails apps embedded in zsh heredocs (single source of truth). Edit in-place, never extract to separate files.

Anti-sprawl: never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md. Edit existing files directly.

Communication style: OpenBSD dmesg-inspired. Terse, factual, evidence-based. No headlines, no bullet lists without content, no unnecessary tables.

Run MASTER2 to validate changes: cd MASTER2 && bundle exec ruby bin/master scan <path>
