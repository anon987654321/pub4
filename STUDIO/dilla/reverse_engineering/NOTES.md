# Reverse engineering notes

This folder is for local analysis only. Audio, stems, and YouTube dumps stay
gitignored. They are not the catalogue.

## What demo.wav actually carries

The last write on the take was `grit_catalogue!`: 7.5 ips tape, a mild triode,
11-bit crush, and a gated square/noise chip with space echo, applied after the
pieces join. That is dirt on the showcase, not a new arrangement.

The engine already knew the three records the operator named. `data/dilla_reference.yml`
holds documented progressions for Slum Village *Fantastic Vol. 2* (Players,
Intro) and Flying Lotus *Los Angeles* (Beginners Falafel, Camel). `lib/groove.rb`
has a `dillatime` pocket at swing 58. `DfamEngine` is the dual-osc FM percussion
voice, on unless `DFAM=0`. Techno pieces already point at `*kit_industrial` and
`feel_hardgroove`. HATE is a named drum profile in `bed.yml`.

The grit chain did not make the drums more 909, the chords more Dilla, or the
textures more FlyLo. It made the joined file sound like a cassette.

## HATE channel

https://www.youtube.com/channel/UC6qQOTx9LuKMC5p2dbjmSRg is HATE, a commercial
techno promotion channel (hour-long mixes: Ben Klock Podcast 500, Marie
Montexier 499). Dumping that catalogue into the tree is a copyrighted mix
archive, not a drum analysis. `yt-dlp` and `demucs` are on the machine. They
are not run against the whole channel from here.

## Dilla, Fantastic Vol. 2, neo-soul Detroit

James Yancey, Conant Gardens. Slum Village with T3 and Baatin. *Fantastic Vol. 2*
finished 1998, released 2000. Questlove and Robert Glasper both credit it with
changing where a chord sits relative to the beat.

Documented flips on that record (from published track analyses, not from
stems we do not have):

- Conant Gardens — Little Beaver "A Tribute To Wes"; Tribe "Award Tour" vocal
- I Don't Know — Baden Powell "É Isso Aí"; James Brown chops
- Jealousy — Bill Evans Trio electric piano, last minute of the cut
- Fall In Love — Gap Mangione "Diana in the Autumn Wind" (1976)
- Get Dis Money — Herbie Hancock "Come Running to Me" (1978) Rhodes
- Untitled/Fantastic — Singers Unlimited "Claire" (the one people still argue)
- World Full of Sadness — Roy Ayers Ubiquity "Love from the Sun"

The people behind those records: Gap Mangione (Chuck's brother, jazz fusion),
Herbie Hancock (Head Hunters / Sunlight vocoder era), Bill Evans, Baden
Powell, Roy Ayers, Motown bass (Jamerson) as the city's low-end grammar, Amp
Fiddler as the Detroit neo-soul hinge Dilla actually sat with.

The harmonic habit is rootless ninths and thirteenths that do not cadence:
Cm9–Fm9–Bb13–Ebmaj7 is the Intro/Players colour. Swing is independent clocks,
not a single MPC percentage. Vinyl crackle is the medium, not a plugin.

## Flying Lotus, Los Angeles

Steven Ellison, 2008, Warp. Beginners Falafel and Camel are ii–V–I–IV in C
with ninths and a lydian #11 on the IV. The engine already stores those
voicings. The FlyLo feel in this tree is stagger, FM, and the `flylo` drum
bank, not a new sample pack.

## DFAM and 909

`lib/sound.rb` `DfamEngine`: two oscillators, FM, noise, resonant decay, an
8-step pitch/velocity sequencer. That is the Moog DFAM shape already. GitHub
does not have a DFAM emulator worth vendoring; what exists is Arduino MIDI
sync for the hardware (`dllmkdir/Moog-DFAM-MIDI-sync`) and Minimoog clones
(`t2techno/Faug`, `giorgiogamba/MinimoogEmulator`). For techno kicks the
useful public circuit work is TR-909 firmware analysis (`Jacquot-SFE/tr-909-analysis`)
and analog 909 kick studies, not another LUT.

## What would actually move the take

Point the showcase at Fall In Love first (done). Re-render `demo.wav` so the
file matches the table. Keep DFAM on. Do not ingest HATE.
