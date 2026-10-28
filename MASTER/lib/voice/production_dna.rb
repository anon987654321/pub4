# frozen_string_literal: true

module Master
  module Voice
    module ProductionDna
      PRODUCERS = {
        j_dilla: {
          philosophy: "humanized machine music through micro-timing, low-pass warmth, and sampler grit",
          equipment: %w[SP-12 SP-1200 MPC-60 MPC3000 SP-303 MinimoogVoyager MicroKORG DBX160X SPX900],
          timing: {
            ppqn: 96,
            bpm: 82..92,
            swing_percent: 53..56,
            golden_ratio_swing: 62.5,
            nudge: { hihats: :forward, snares: :early, kicks: :late },
            # Measured constants from the 2026-10-27 research pass. These are
            # observations with sources, not configuration: brief() reads only
            # the keys above, so nothing downstream can mistake measurement
            # for tuning.
            measured: {
              source: "21st Century Funk: A Microtiming Analysis of the Beats of J Dilla (academia.edu 29812748); " \
                      "Soundfly, Three Examples of Dilla Swing (2016); Hein, Dilla Time (2022)",
              melodic_anticipation: "synths and bass anticipate the drums by ~100ms; bass and snare anticipations " \
                                    "of 32nd-note duration",
              kick_instability: "10 of 13 kick notes in the measured bar fall off the metronomic grid — kicks are " \
                                "the erratic element; snare and hi-hats are the stable frame",
              hats_feel: "on-beat hats straight; upbeat hats nudged back without reaching triplet feel (Say It); " \
                         "late 16ths clustering at the end of beat two (U-Love)",
              anchors: "kicks on one and three hold the grid while everything around them drifts (U-Love)",
              repetition: "the deviations repeat identically every bar — meticulously executed, never sloppy " \
                          "(Charnas, via Hein 2022)",
            },
            # Form, not feel: the loop lengths the catalogue shows (Atwood-
            # Ferguson, Guardian 2011; Get Dis Money's seven-bar loop and the
            # non-4 hook/verse bar counts, Hein 2022).
            form: {
              loop_lengths: [3, 5, 7],
              note: "parts looped in threes, fives and sevens against the strict four; phrase lengths follow the " \
                    "sample, not the grid",
            },
          },
          lineage: {
            note: "cello lessons as a child; sampled Bach's Toccata and Fugue in D minor through Mike Hankinson's " \
                  "synthesizer LP (The Unusual Classical Synthesizer) and Satie through The Music of Eric Satie – " \
                  "Velvet Gentleman; Atwood-Ferguson hears Satie, Ravel, Debussy and Poulenc in the harmony " \
                  "(Guardian, 2011); Suite for Ma Dukes recreated the melodies, harmonies and basslines of the " \
                  "samples for a 60-piece orchestra",
            sources: [
              "musicismysanctuary.com, The Classical Side of Dilla (2016)",
              "theguardian.com, J Dilla: the Mozart of hip-hop (2011)",
            ],
          },
          mix: {
            lowpass: :aggressive_sample_filtering,
            sub_bass: "40Hz oscillator triggered by kick with short gate release",
            texture: "SP-1200 12-bit grit, watery SPX900 symphonic modulation",
          },
        },
        flying_lotus: {
          philosophy: "jazz lineage, hazy electronic collage, off-kilter rhythm, sidechain breathing",
          equipment: %w[Reason Ableton SP-303 RolandMC505 TriggerFinger MPD32 AccessVirusTI SpaceEcho Rhodes Wurlitzer],
          timing: {
            bpm: 81..110,
            quantize: false,
            hats: :behind_beat,
            snares: :lazy_yet_tight,
          },
          mix: {
            sidechain_attack_ms: 0.75..1.0,
            sidechain_release_ms: 10..20,
            gain_reduction_db: 30..40,
            texture: "vinyl layer, pitched-down mass, SP-303 compression, cosmic jazz haze",
          },
        },
        madlib: {
          philosophy: "speed over perfection; live triggering; rough-hewn texture as truth",
          equipment: %w[SP-303 SP-1200 SP-12 SP-606 VS-1680 VS-880 Tascam488 Tascam388 Rhodes Clavinet MicroKORG],
          timing: {
            beat_build_minutes: 10..15,
            sequencer: false,
            performance: :live_to_multitrack,
          },
          mix: {
            signature_effects: %i[vinyl_sim wah time_stretch tape_echo phaser ring_mod],
            texture: "SP-303 Vinyl Sim, cassette saturation, preserved surface noise, minimal processing",
          },
        },
      }.freeze

      CHORDS = {
        j_dilla: {
          fantastic_vol2: [
            { track: "intro", key: "Dm", bpm: 93, chords: %w[Dm7 F G C], roman: %w[i7 bIII IV bVII], sample: "A Tribe Called Quest, Butter (Phife Dawg vocal tag at the end)", sample_reference: "https://jdillabasslines.wordpress.com/fantastic-vol-2/" },
            { track: "fall_in_love", key: "Fm", bpm: 91, chords: %w[Bbm Ab Fm7 Fm], roman: %w[iv bIII i7 i],
              alternate: %w[Cm Gm Cm Fm Ab Cm], sample: "Gap Mangione, Diana in the Autumn Wind (1968)",
              sample_reference: "https://maximumfun.org/episodes/heat-rocks/the-art-of-sampling-3b-with-dan-charnas-on-slum-villages-fantastic-vol-2-2000/" },
            { track: "climax", key: "E", bpm: 96, chords: %w[Emaj7 G#m7 G#m7 G#maj7],
              roman: %w[Imaj7 iii7 iii7 IIImaj7], alternate: %w[C#m7 Emaj7 D#7 C#m],
              sample: "Isao Tomita, Clair de Lune; Steve Miller Band, Space Intro and Fly Like an Eagle; Les McCann, The Pleading",
              sample_reference: "https://dilla.fandom.com/wiki/Climax_%28Girl_Shit%29" },
            { track: "get_dis_money", key: "C#m", bpm: 90, chords: %w[C#m G#m A#7 C#], roman: %w[i v VI7 I],
              alternate: %w[D/E Db/E C/E Bm/E Bbm/E Am/E], pedal: "E", bars: 7,
              sample: "Herbie Hancock, Come Running to Me (1978), slowed 4 semitones, bass tuned 50 cents sharp",
              sample_reference: "https://jdillabasslines.wordpress.com/fantastic-vol-2/",
              transcription_source: "https://www.ethanhein.com/wp/2022/get-dis-money/" },
            { track: "players", key: "Ebm", bpm: 93, chords: %w[Ebm7 Abm7 Fm7 Bbm7], roman: %w[i7 iv7 ii7 v7],
              sample: "The Singers Unlimited, Clair (1974)", sample_reference: "https://jdillabasslines.wordpress.com/fantastic-vol-2/" },
            { track: "2u_4u", key: "Am", bpm: 95, chords: %w[Am7 Em7 Bm7 F#m7], roman: %w[i7 v7 ii7 vi7],
              sample: "D'Angelo, Jonz in My Bonz", sample_reference: "https://jdillabasslines.wordpress.com/fantastic-vol-2/" },
            { track: "hold_tight", key: nil, bpm: 97, chords: %w[C Db G F Bb],
              sample: "Cannonball Adderley Quintet, Experience in E" },
            { track: "jealousy", key: nil, bpm: 98, chords: [],
              sample: "Bill Evans and Eddie Gomez, Are You All the Things (1974), final minute" },
            { track: "conant_gardens", key: "D", bpm: 94, chords: %w[D Em G], roman: %w[I ii IV],
              sample: "Little Beaver, A Tribute to Wes (bassline), one of eight sources",
              sample_reference: "https://www.whosampled.com/Little-Beaver/A-Tribute-to-Wes/" },
            { track: "untitled_fantastic", key: "A", bpm: nil, chords: %w[A Dm E7 D7], roman: %w[I iv V7 IV7],
              sample: "Herbie Hancock, You'll Know When You Get There (1971)" },
            { track: "go_ladies", key: nil, bpm: 95, chords: %w[G# C# E F# C#m G#m B],
              character: "bass doubled an octave up at phrase starts" },
            { track: "thelonious", key: "floating", bpm: 92, chords: %w[Ebm Bbm], roman: %w[i v] },
            { track: "selfish", key: "G", bpm: nil, chords: %w[Cmaj7 Bm7 Am7 D7], roman: %w[IVmaj7 iii7 ii7 V7] },
          ],
          fantastic_vol1: [
            { track: "players", key: "Ebm", bpm: 94, chords: %w[Ebm7 Abm7 Fm7 Bbm7], roman: %w[i7 iv7 ii7 v7],
              sample: "The Singers Unlimited, Clair (1974)" },
            { track: "look_of_love", key: "G", bpm: nil, chords: %w[Bm7 Bm7 Cmaj7 Em7], roman: %w[iii7 iii7 IVmaj7 vi7],
              sample: "Minnie Riperton, Inside My Love (1975), Gbmaj7 Bbm Abmaj Dbmaj7 repitched" },
            { track: "5_ela", key: "Dm/A", bpm: nil, chords: %w[Dm9 Em7 C#m7], roman: %w[i9 ii7 #vii7],
              character: "dual-tonal, D minor and A major at once",
              sample: "The Gap Band, Yearning for Your Love; Patrice Rushen, Remind Me",
              transcription_source: "https://www.ethanhein.com/wp/2022/patrice-rushens-memory-songs/" },
            { track: "give_this", key: "Eb", bpm: nil, chords: %w[Cm7 Fm7 F7], roman: %w[vi7 ii7 II7],
              sample: "Zapp, Heartbreaker (1983)" },
            { track: "fantastic", key: nil, bpm: nil, chords: [],
              sample: "Herbie Hancock, You'll Know When You Get There (1971)" },
            { track: "pregnant", key: nil, bpm: nil, chords: [],
              sample: "Bobby Hutcherson, Manzanita (1975)" },
          ],
          donuts: [
            { track: "time_donut_of_the_heart", key: "Ab/Fm", bpm: 94,
              chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], roman: %w[IVmaj7 iii7 vi7 ii7],
              sample: "The Jackson 5, All I Do Is Think of You (1975); Sweet Charles, Yes It's You",
              sample_reference: "https://www.reddit.com/r/jdilla/comments/nczrv3/" \
                                "every_donuts_track_briefly_explored_and_analyzed" },
            { track: "workinonit", key: "Bm", bpm: 93, chords: [],
              sample: "10cc, The Worst Band in the World (1975); George Kirby & The Temptations, Comedy Routine: " \
                      "Hello, Young Lovers / Cloud Nine / If I Didn't Care",
              sample_reference: "https://scholarworks.sfasu.edu/etds/197/" },
            { track: "lightworks", key: "F#m", bpm: 95, chords: [],
              sample: "Raymond Scott & Dorothy Collins, Lightworks; Mantronix, King of the Beats (1988); Raymond " \
                      "Scott, Bendix the Tomorrow People",
              sample_reference: "https://www.whosampled.com/album/J-Dilla/Donuts" },
            { track: "waves", key: "A#m", bpm: 90, chords: [],
              sample: "10cc, Johnny, Don't Do It (1973); Mantronix, King of the Beats (1988); B.R. Gunna, Intro (2004)",
              sample_reference: "https://www.whosampled.com/album/J-Dilla/Donuts" },
            { track: "stop", key: "F#m", bpm: 86, chords: [],
              # Two independent album breakdowns agree on Dionne Warwick; the
              # exact side is not confirmed by an open source, so it stays
              # unnamed rather than guessed.
              sample: "Dionne Warwick (exact side unconfirmed in open sources)",
              sample_reference: "https://guiorecords.com/groove-gazette/j-dilla-donuts-review.html" },
            { track: "dont_cry", key: nil, bpm: nil, chords: [],
              sample: "George Kerr & The Escorts, I Can't Stand (To See You Cry); George Kirby & The Temptations, " \
                      "Comedy Routine",
              sample_reference: "https://scholarworks.sfasu.edu/etds/197/" },
            { track: "two_can_won", key: nil, bpm: nil, chords: [],
              sample: "The Sylvers, Only One Can Win (1973)",
              sample_reference: "https://www.whosampled.com/album/J-Dilla/Donuts" },
          ],
          the_shining: [
            { track: "so_far_to_go", key: "Bb", bpm: nil, chords: %w[Dm7 Cm7 F Gm7],
              sample: "The Isley Brothers, Don't Say Goodnight (It's Time for Love) (Parts 1 & 2) (1980)",
              sample_reference: "https://www.whosampled.com/sample/2772/" \
                                "J-Dilla-Common-D%27Angelo-So-Far-to-Go-The-Isley-Brothers-Don%27t-Say-Goodnight-(It" \
                                "%27s-Time-for-Love)-(Parts-1-%26-2)/" },
          ],
        },
        flying_lotus: {
          los_angeles: [
            { track: "camel", key: "C", bpm: 84, chords: [], character: "percussive janky eastern jangle" },
            { track: "robertaflack", key: "G", bpm: 81, chords: [], character: "laid-back jazz and lush neo-soul" },
            { track: "gng_bng", key: nil, bpm: 103, chords: [], character: "heavy wall-of-noise gangster soundtrack" },
          ],
        },
        madlib: {
          madvillainy: [
            { track: "accordion", key: "Dm", bpm: 96, chords: %w[Dm Gm Am], roman: %w[i iv v] },
          ],
        },
      }.freeze

      LOFI_PRESETS = {
        dilla_drum_bus: {
          producer: :j_dilla,
          sonitex_preset: :boom_bap,
          bpm: 88,
          instructions: [
            "turn quantize off or use 53-56% swing only as a starting grid",
            "nudge snares early, kicks late, and second hat lane forward",
            "low-pass samples aggressively and add sub support around 40Hz",
          ],
        },
        flylo_haze: {
          producer: :flying_lotus,
          sonitex_preset: :aggressive_lofi,
          bpm: 84,
          instructions: [
            "layer high-passed vinyl noise under the beat",
            "use fast heavy sidechain pumping with short release",
            "pitch samples down and let transients smear",
          ],
        },
        madlib_303: {
          producer: :madlib,
          sonitex_preset: :phone_wear,
          bpm: 96,
          instructions: [
            "trigger samples live instead of sequencing perfectly",
            "embrace SP-303 style vinyl sim compression and time-stretch artifacts",
            "bounce through rough media instead of polishing",
          ],
        },
      }.freeze

      module_function

      def brief
        <<~TEXT.strip
        Production DNA:
        - J Dilla: 96 PPQN MPC feel, 53-56% swing pocket, snares early, kicks late, hats nudged forward, 82-92 BPM, low-pass warmth.
        - Flying Lotus: jazz harmony plus electronic haze, unquantized drums, fast heavy sidechain pump, vinyl layer, pitch-down texture.
        - Madlib: SP-303 live triggering, Vinyl Sim grit, cassette/multitrack roughness, speed over polish, minor/jazz harmony.
        - Code generation should expose timing, chord, and texture parameters instead of hard-coding one beat.
      TEXT
      end

      def producer(name)
        PRODUCERS.fetch(name.to_sym)
      end

      def chords_for(name, collection = nil)
        data = CHORDS.fetch(name.to_sym)
        return data unless collection

        data.fetch(collection.to_sym)
      end

      def preset(name)
        LOFI_PRESETS.fetch(name.to_sym)
      end

      def sonitex_preset_for(name)
        preset(name).fetch(:sonitex_preset)
      end
    end
  end
end
