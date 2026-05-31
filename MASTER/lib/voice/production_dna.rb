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
            nudge: { hihats: :forward, snares: :early, kicks: :late }
          },
          mix: {
            lowpass: :aggressive_sample_filtering,
            sub_bass: "40Hz oscillator triggered by kick with short gate release",
            texture: "SP-1200 12-bit grit, watery SPX900 symphonic modulation"
          }
        },
        flying_lotus: {
          philosophy: "jazz lineage, hazy electronic collage, off-kilter rhythm, sidechain breathing",
          equipment: %w[Reason Ableton SP-303 RolandMC505 TriggerFinger MPD32 AccessVirusTI SpaceEcho Rhodes Wurlitzer],
          timing: {
            bpm: 81..110,
            quantize: false,
            hats: :behind_beat,
            snares: :lazy_yet_tight
          },
          mix: {
            sidechain_attack_ms: 0.75..1.0,
            sidechain_release_ms: 10..20,
            gain_reduction_db: 30..40,
            texture: "vinyl layer, pitched-down mass, SP-303 compression, cosmic jazz haze"
          }
        },
        madlib: {
          philosophy: "speed over perfection; live triggering; rough-hewn texture as truth",
          equipment: %w[SP-303 SP-1200 SP-12 SP-606 VS-1680 VS-880 Tascam488 Tascam388 Rhodes Clavinet MicroKORG],
          timing: {
            beat_build_minutes: 10..15,
            sequencer: false,
            performance: :live_to_multitrack
          },
          mix: {
            signature_effects: [:vinyl_sim, :wah, :time_stretch, :tape_echo, :phaser, :ring_mod],
            texture: "SP-303 Vinyl Sim, cassette saturation, preserved surface noise, minimal processing"
          }
        }
      }.freeze

      CHORDS = {
        j_dilla: {
          fantastic_vol2: [
            { track: "fall_in_love", key: "Fm", bpm: 91, chords: %w[Bbm Ab Fm7 Fm], roman: %w[iv bIII i7 i] },
            { track: "climax", key: "E", bpm: 96, chords: %w[Emaj7 G#m7 G#m7 G#maj7], roman: %w[Imaj7 iii7 iii7 IIImaj7] },
            { track: "get_dis_money", key: "C#m", bpm: 90, chords: %w[C#m G#m A#7 C#], roman: %w[i v VI7 I] },
            { track: "thelonious", key: "floating", bpm: 92, chords: %w[Ebm Bbm], roman: %w[i v] },
            { track: "selfish", key: "G", bpm: nil, chords: %w[Cmaj7 Bm7 Am7 D7], roman: %w[IVmaj7 iii7 ii7 V7] }
          ],
          fantastic_vol1: [
            { track: "look_of_love", key: "G", bpm: nil, chords: %w[Bm7 Bm7 Cmaj7 Em7], roman: %w[iii7 iii7 IVmaj7 vi7] }
          ],
          donuts: [
            { track: "time_donut_of_the_heart", key: "Ab/Fm", bpm: 94, chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], roman: %w[IVmaj7 iii7 vi7 ii7] },
            { track: "workinonit", key: "Bm", bpm: 93, chords: [] },
            { track: "lightworks", key: "F#m", bpm: 95, chords: [] },
            { track: "waves", key: "A#m", bpm: 90, chords: [] },
            { track: "stop", key: "F#m", bpm: 86, chords: [] }
          ],
          the_shining: [
            { track: "so_far_to_go", key: "Bb", bpm: nil, chords: %w[Dm7 Cm7 F Gm7] }
          ]
        },
        flying_lotus: {
          los_angeles: [
            { track: "camel", key: "C", bpm: 84, chords: [], character: "percussive janky eastern jangle" },
            { track: "robertaflack", key: "G", bpm: 81, chords: [], character: "laid-back jazz and lush neo-soul" },
            { track: "gng_bng", key: nil, bpm: 103, chords: [], character: "heavy wall-of-noise gangster soundtrack" }
          ]
        },
        madlib: {
          madvillainy: [
            { track: "accordion", key: "Dm", bpm: 96, chords: %w[Dm Gm Am], roman: %w[i iv v] }
          ]
        }
      }.freeze

      LOFI_PRESETS = {
        dilla_drum_bus: {
          producer: :j_dilla,
          sonitex_preset: :boom_bap,
          bpm: 88,
          instructions: [
            "turn quantize off or use 53-56% swing only as a starting grid",
            "nudge snares early, kicks late, and second hat lane forward",
            "low-pass samples aggressively and add sub support around 40Hz"
          ]
        },
        flylo_haze: {
          producer: :flying_lotus,
          sonitex_preset: :aggressive_lofi,
          bpm: 84,
          instructions: [
            "layer high-passed vinyl noise under the beat",
            "use fast heavy sidechain pumping with short release",
            "pitch samples down and let transients smear"
          ]
        },
        madlib_303: {
          producer: :madlib,
          sonitex_preset: :phone_wear,
          bpm: 96,
          instructions: [
            "trigger samples live instead of sequencing perfectly",
            "embrace SP-303 style vinyl sim compression and time-stretch artifacts",
            "bounce through rough media rather than polishing"
          ]
        }
      }.freeze

      module_function

      def brief
        <<~TEXT.strip
        Production DNA:
        - J Dilla: 96 PPQN MPC feel, 53-56% swing pocket, snares early, kicks late, hats nudged forward, 82-92 BPM, low-pass warmth.
        - Flying Lotus: jazz harmony plus electronic haze, unquantized drums, fast heavy sidechain pump, vinyl layer, pitch-down texture.
        - Madlib: SP-303 live triggering, Vinyl Sim grit, cassette/multitrack roughness, speed over polish, minor/jazz harmony.
        - Code generation should expose timing, chord, and texture parameters rather than hard-code one beat.
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
