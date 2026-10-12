# Dilla

**A small room that plays a chord progression soft and a little late, with a drum kit that never
sits on the grid.** Dilla is one Ruby file and one data file. It reads a progression as a list of
chord names, works out the voicing itself, plays the chords as stacks of sine waves, and writes a
wav. Add a drum pattern and a groove profile and the kick, the snare and the hats fall a few
milliseconds early or late, each in its own direction, the way a person leaning on a machine would
play them.

The engine is `dilla.rb`, about five hundred lines of plain Ruby with nothing beyond the standard
library, and the data is `dilla.json`, which sits beside it. Run `ruby dilla.rb --list` to see the
numbered progressions, the drum patterns and the groove profiles. Run `ruby dilla.rb --progression
3 --drums offbeat_inversion --profile early_snare_late_hats --out out/three.wav` to render one,
add `--midi out/three.mid` to write the same chords and drums as a Standard MIDI File, and run
`ruby dilla.rb --random` to let the seed choose all three. The same seed always makes the same
render, and the seed is printed. Renders are sixteen-bit mono at 44.1 kilohertz. The folder `out/`
is ignored by git, because audio is not tracked, and a render that matters belongs outside the
repository, in the dilla-renders folder under your documents.

The data holds a flat list of progressions, each one a list of chord names such as Fm9, Bbm9, Eb13
and Abmaj9, with nothing else attached: no tempo, no names, no frequencies. The voicer reads the
name. It puts the root, or the bass of a slash chord, in the low octave, leaves the root out of
the upper structure, keeps the third and the seventh, drops the fifth when the chord is crowded,
and places every note as near as it can to where the last chord sat, so the voices glide. It reads
minor and major ninths, elevenths and thirteenths, added and suspended tones, altered fifths and
ninths, and slash chords, and a test maps every voicing back to the spelling it came from. Every
chord holds the same number of beats, four unless `--beats` says otherwise, and the tempo is 88
unless `--bpm` says otherwise.

A groove profile says how a render is played, and its name says what it does: soft_swing, lush and
dry are texture and swing only, while early_snare_late_hats, late_snare, behind_the_beat,
loose_pocket and pump move the drums. A profile holds a swing for the second chord of each pair, a
swing for each drum role on the off-beat eighths and sixteenths, an offset in seconds for the
kick, the snare and the hats, and a separate offset for the first kick. It may hold a drunk
amount, which nudges every hit by a seeded random amount, and a sidechain, which dips the chords
on every kick like a gain envelope and has no oscillator in it. Nothing is ever moved more than
thirty-five milliseconds from its place. The single knob `--groove`, from nought to one and a
half, scales the whole profile: nought is the grid, one is the profile as written, and one and a
half is the profile leaning harder. The drum patterns are rows of sixteen steps, and a pattern
repeats bar after bar until the chords end, so a long progression is not left drumless after the
first bar.

The timing ideas come from a summary the operator pasted in, which says that hats on the off-beat
sixteenths sit slightly late, the snare and clap slightly early and the kick mostly late except
the first, that a deliberate collision between a straight grid and a swung one is what gives the
feel, and that a window of about thirty milliseconds is the point. That summary has not been
checked against any record, so read every number as a starting point to be corrected by ear. The
progressions are hand-picked starting points too, merged from several lists and removed of
duplicates, and nobody has verified the spellings.

The engine is small on purpose, and its limits are plain. The chords play through once and the
render ends. Every note is a stack of four sine partials, so the sound is thin and organ-like, and
the only motion is the detune and the swing: there is no LFO, no wow, no flutter and no crackle.
The drums are three short synthesised sounds. A render takes about four tenths of its own length
to compute.

The old engine, which was far larger, is not lost. The tag `dilla-engine-final` marks the last
commit that carried all of it, `git checkout dilla-engine-final -- STUDIO/dilla` brings it back,
and `git show dilla-engine-final:STUDIO/dilla/lib/sound.rb` reads one file from it. Its large data
files, the MIDI library, the sample worth scores and the crate records all stay recoverable from
that tag in the same way.
