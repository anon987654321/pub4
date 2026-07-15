# Dilla Lab

Unified audio engine — synthesis, analog pads, vocal mixes, stem rack,
demux, MIDI electronium. One file (`dilla.rb`) by design; the former
`dilla_enhancements.rb` split was merged back in.

Two entry points:

- `MASTER/tools/dilla.rb` — the stable MASTER entrypoint
  (`generate --style dilla|flylo|baroque|neo-soul|jazz`), used by the chat
  router's "make a Dilla beat" path. Writes to `.master/media/` and calls
  the engine with the flag interface below.
- `MASTER/tools/dilla/dilla.rb` — the engine itself.
  `ruby dilla.rb help` is the full command reference.

## Command taxonomy

| Group | Commands |
|---|---|
| Render styles | `dilla`/`beat`, `hiphop`, `slum`, `industrial`, `techno`, `analog`, `analog_liveset`, `loose_pocket`, `render` |
| Vocal mixes | `mix`, `v7`–`v11` |
| Sample pipeline | `prepare`, `sample`, `source`, `separate`, `demux`, `clean` |
| Stem rack / live | `stems`, `liveset`, `live`, `stream`, `live_now`, `livestream` |
| Analysis | `scan`, `ears`, `verify`, `study`, `grade`, `chords`, `rhythm`, `melody`, `harmony`, `semantics`, `quality`, `debug`, `sweep`, `council` |
| MIDI | `electronium`/`midi` (needs `gem install midilib`) |
| Assets | `fetch-assets`, `use-external-kit` (opt-in; engine is pure-Ruby/ffmpeg by default) |

The dispatch table (`DISPATCH` at the bottom of `dilla.rb`) is the single
source of truth — `COMMANDS`, help, and the `debug` dump all derive from it.

## Tuning: flags or ENV

Every tuning ENV var has a `--flag=value` twin usable on any command
(`FLAG_ENV` in `dilla.rb`): `--track --progression --sonitex --analog-chain
--sidechain --bars --bpm --swing --voicing --kicks`. Flags set the same ENV
internally, so both interfaces stay equivalent.

```sh
ruby dilla.rb dilla beat.mp3 --track=timeless --sonitex=donuts_warm --bars=16
```

## Scratch and outputs

- Finished renders → the invoking directory, or `DILLA_OUTPUT_DIR`.
- All caches/temp audio → `.cache/` next to the engine, or
  `DILLA_SCRATCH_DIR`. Safe to wipe **except** `progressions_log.txt`:
  generated progressions never repeat, so that log is the only record of
  what actually played. Legacy dotfile logs are auto-migrated in.

## External assets

`fetch-assets` caches CC0 soundfonts + a drum-kit repo under `~/.cache/`,
recording SHA256s (and the kit repo's HEAD) into `checksums.json` on first
fetch; later runs warn if upstream content drifted, since that changes how
renders sound. Delete a manifest entry to accept a new upstream version.

## Tests

`MASTER/test/test_dilla_lab.rb` — table integrity (grade presets ↔ filter
arms, dispatch ↔ COMMANDS), voicing bounds, flag parsing, wrapper→engine
contract. The whole-pipeline render smoke is opt-in:

```sh
DILLA_SMOKE=1 bundle exec ruby -Itest test/test_dilla_lab.rb
```
