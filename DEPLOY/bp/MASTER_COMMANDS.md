# MASTER commands for business plans

This directory follows the MASTER rule: preserve, validate, then improve.

Each idea gets one standalone HTML document. A business plan is valid only when it has inline CSS in a `<style>` tag, inline JavaScript in a `<script>` tag, no external stylesheet link, no external `script src`, Norwegian language markup, and all required Innovation Norway sections.

## Commands

Run the deterministic generator:

```zsh
ruby DEPLOY/bp/generate.rb
```

Run the BP gate:

```zsh
ruby DEPLOY/bp/master_bp_gate.rb
```

Run the repository scan through MASTER when available:

```zsh
cd MASTER
bundle exec ruby bin/cli
# /scan ../DEPLOY/bp --depth deep
```

On the OpenBSD VPS, use package-qualified Ruby when needed:

```zsh
ruby34 DEPLOY/bp/master_bp_gate.rb
cd MASTER && bundle34 exec ruby bin/cli
# /scan ../DEPLOY/bp --depth deep
```

## Required plan files

- `syre.html`
- `speis.html`
- `norwegianhedge.html`
- `pubhealthcare.html`
- `ragnhild.html`
- `govt_bergen.html`
- `nato.html`
- `ai3.html`

## Required section ids

- `sammendrag`
- `problem-og-mulighet`
- `marked-og-kunder`
- `losning-og-produkt`
- `teknologi-og-innovasjon`
- `forretningsmodell`
- `gjennomforing-og-drift`
- `utviklingsveikart`
- `finansieringsbehov`
- `team-og-kompetanse`
- `risiko-og-tiltak`
- `baerekraft-og-samfunnsansvar`
- `maltall-og-validering`

## Merge rule

Do not overwrite hand-written value blindly. If a section already exists in an HTML plan, preserve it unless the replacement is demonstrably more complete, more accurate, and still Norwegian.
