# pub2 misc plugin archaeology — 2026-10-28

Scope: inventory of every current file under `anon987654321/pub2/misc/**` and focused review of the utility implementations and paired README files, compared to the *shape* of the existing `MASTER/plugins` tree and `MASTER/data/recovery/plugin_schema_v1.json`. This is a disposition report, not permission to edit MASTER; the repository owner's full-read precondition for MASTER remains mandatory.

## Inventory and disposition

| Legacy item | Observed purpose / condition | Disposition |
|---|---|---|
| `misc/default2.theme` | Irssi neutral/monochrome theme file. It has no executable tool contract. | **Do not make a plugin.** Preserve as a standalone theme/reference only if Irssi configuration is still wanted. |
| `misc/nmap/nmap.sh` | OpenBSD-oriented active network scanner with DNS fallback, privileged scanning and phased output. The README advertises TCP SYN, UDP, service/version, OS and vulnerability scanning. It requires nmap/doas and some scan paths invoke privileged actions. Its “cognitive load” counters are mostly presentation counters, not validated measurements. | **Candidate only after a fresh design.** Could become a narrowly scoped, authorization-first network-assessment utility, but not by copying this script. Require explicit target allowlists, bounded scan profiles/timeouts, no target-derived shell strings, least privilege, evidence provenance and simulated tests first. Compare to current OPENBSD and MASTER security facilities before any implementation. |
| `misc/pouncekeys/pouncekeys.rb` | Termux setup script for an APK described in its own comments as keylogging; it discusses capturing keystrokes and emailing logs. Its expected SHA-256 is a literal placeholder, so integrity is not actually verified. | **Reject. Do not restore or package as a plugin.** The security claims in the README do not change what the implementation does. |
| `misc/r-vx/r-vx.md` | A proposed Rust “threat simulation” write-up, not a completed repository tool. It includes simulated sensitive-data/keylogging concepts, network scanning and a suggested Rails endpoint invoking a binary through backticks. | **Do not restore as executable code.** If there is a legitimate training need, write a separate isolated fixture-only simulator with no real credential capture, host scanning, persistence or shell execution. |
| `misc/vulcheck/vulcheck.rb` | Small Ruby host-checking prototype for macOS/iOS/Android. It requires root, installs and updates packages, executes shell commands, writes logs to the current directory, and uses unreliable platform/rootkit/intrusion heuristics (for example, `ps aux | grep suspicious`). README claims exceed demonstrated capability. | **Concept only, not a drop-in plugin.** A safe replacement would be read-only by default, platform-specific, no implicit sudo/install/update, use argument-vector subprocess calls with bounded timeouts, document false positives, and emit source-backed evidence. First check overlap with current security scanning so we don't create a second scanner. |

## Plugin recommendation

Do not copy any of these directories wholesale into `MASTER/plugins`. The Irssi theme is configuration, `pouncekeys` is disallowed behavior, `r-vx` is a draft, and both scanners require redesign and parity checks. At most, Nmap and VulCheck are *requirements/reference material* for a future safe network/host assessment capability.

An approved MASTER plugin would need to be built against the current plugin contract and schema, with tests and least-privilege guarantees. That means inspecting and reading MASTER fully first, as required by the repository owner, and then following the authority order (soul, laws, executable enforcement, tree contracts). No MASTER files were changed by this audit.

## Evidence and limits

- `pub2/main` inventory revision: `ad05242c97fff1b01450434974aad628d7de8628`.
- Inventory: nine leaf files are present under `misc/**` (including duplicate HTML/Markdown Nmap documentation). The focused pass examined the theme, Nmap shell implementation and docs, PounceKeys installer and docs, r-vx draft, and VulCheck implementation/docs.
- Not claimed: byte-by-byte review of every legacy document's full contents, execution against a live host, a security audit of the upstream APK, or runtime test results.
