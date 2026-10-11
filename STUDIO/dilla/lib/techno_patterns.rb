# frozen_string_literal: true

# Named techno drum pattern profiles at 16th-step resolution.
#
# What the sources support: Ben Klock's beats read as house played much faster,
# with a tight bounce above 130 BPM (Resident Advisor, Fabric 66 review); Regis
# and the Downwards lineage use brittle snares, layered subs and relentless
# industrial percussion, sheet metal among it; FJAAK are known for distorted
# drums, hard kicks and breaks mixed into electro. HATE itself is described as
# techno, electro and experimental, avoiding "mainstream techno" (Dummy).
# What is inference: the exact step placements below, the swing depths, and the
# sub "rumble" on the offbeat 8ths, which is the common Berlin convention and
# not a quoted fact.
#
# Each profile is a function of (bar, rng) returning role => [[step, velocity]].
# `step` is a Float on the 16-step grid; the fractional part is micro-timing,
# bounded by MICRO_MAX_STEPS per role. The rng is the caller's seeded Random,
# so one seed gives one cycle.
module DillaTechnoPatterns
  BARS = 8
  ROLES = %i[kick ghost clap hat open ride metal tom rumble].freeze
  # Largest nudge, in steps, any role may carry. At 145 BPM a step is 103 ms, so
  # 0.2 is about 20 ms: a lean, not a flam.
  MICRO_MAX_STEPS = 0.2
  # Kicks stay on the grid; they are the reference everything else leans on.
  MICRO_BY_ROLE = {
    kick: 0.0, rumble: 0.0, ghost: 0.08, clap: 0.06, hat: 0.05, open: 0.04,
    ride: 0.05, metal: 0.2, tom: 0.1
  }.freeze

  FLOOR = [0, 4, 8, 12].freeze
  OFFBEATS = [2, 6, 10, 14].freeze
  EVEN_16THS = (0..15).step(2).to_a.freeze
  ALL_16THS = (0..15).to_a.freeze

  PROFILES = {
    # Straight four-on-the-floor, open hat on every "and", sub rumble in the gaps.
    driving_offbeat: {
      four_on_floor: true,
      build: lambda do |bar, rng|
        row = { kick: FLOOR.map { |s| [s, 1.0] }, clap: [[4, 0.9], [12, 0.95]],
                open: OFFBEATS.map { |s| [s, 0.8] },
                hat: (ALL_16THS - OFFBEATS - FLOOR).map { |s| [s, 0.28 + (s.odd? ? 0.0 : 0.08)] },
                rumble: OFFBEATS.map { |s| [s, 0.55] } }
        row[:ghost] = [[7, 0.3]] if bar.odd?
        row[:kick] = FLOOR.first(3).map { |s| [s, 1.0] } if bar == BARS - 1 && rng.rand < 0.5
        row[:metal] = [[14, 0.5]] if (bar % 4).zero?
        row
      end
    },
    # Klock-style: rolling swung 16ths, a bouncing hat line, tight and stripped.
    klock_rolling: {
      four_on_floor: true,
      swing: 0.14,
      build: lambda do |bar, rng|
        # Odd 16ths carry the roll; one even step fills the gap. Eight to nine
        # hats a bar is the ceiling hate's single-expression hat layer survives
        # (a full 16 a bar over eight bars made ffmpeg run out of memory).
        hats = (ALL_16THS.select(&:odd?) + [10]).map { |s| [s, s.odd? ? 0.5 + rng.rand * 0.12 : 0.26] }
        hats.reject! { |s, _| s == 15 } if bar.odd?
        { kick: FLOOR.map { |s| [s, 1.0] },
          clap: [[4, 0.85], [12, 0.9]],
          hat: hats,
          open: [[6, 0.6], [14, 0.55]],
          ghost: bar.even? ? [[11, 0.25]] : [[3, 0.25], [11, 0.3]],
          ride: [[2, 0.3], [10, 0.3]],
          metal: bar.even? ? [[13, 0.35]] : [[5, 0.35]],
          rumble: [[2, 0.4], [10, 0.4]] }
      end
    },
    # FJAAK-style: hard, broken kicks over a four-bar phrase, claps pushed off the
    # backbeat, little hat. The floor is deliberately not four-on-the-floor.
    fjaak_broken: {
      four_on_floor: false,
      build: lambda do |bar, rng|
        kicks = [[[0, 1.0], [3, 0.7], [6, 0.9], [8, 1.0], [11, 0.8], [14, 0.9]],
                 [[0, 1.0], [4, 0.9], [7, 0.8], [8, 1.0], [10, 0.7]],
                 [[0, 1.0], [3, 0.75], [8, 1.0], [12, 0.9], [15, 0.6]],
                 [[0, 1.0], [5, 0.8], [8, 1.0], [11, 0.75], [13, 0.8]]][bar % 4]
        { kick: kicks,
          clap: [[4, 0.95], [rng.rand < 0.5 ? 12 : 13, 0.9]],
          hat: [[2, 0.4], [6, 0.35], [10, 0.4], [14 - (bar % 2), 0.35]],
          open: bar % 4 == 3 ? [[14, 0.6]] : [],
          tom: [[9, 0.5], [15, 0.4]].first(1 + (bar % 2)),
          metal: [[bar.even? ? 7 : 13, 0.5]],
          ghost: [[5, 0.3], [12, 0.25]] }
      end
    },
    # Regis/Birmingham-style: sparse, grinding, brittle snares and metal hits off
    # the grid over an unrelenting kick.
    regis_industrial: {
      four_on_floor: true,
      build: lambda do |bar, rng|
        metal = [[[3, 0.8], [7, 0.6], [13, 0.7]], [[5, 0.7], [11, 0.8]],
                 [[3, 0.7], [9, 0.6], [14, 0.8]], [[7, 0.8], [15, 0.5]]][bar % 4]
        { kick: FLOOR.map { |s| [s, 1.0] },
          clap: [[4, 0.8], [12, 0.85]] + (rng.rand < 0.4 ? [[15, 0.4]] : []),
          hat: [[2, 0.3], [10, 0.3], [14, 0.25]],
          open: [],
          metal: metal,
          tom: bar.odd? ? [[6, 0.5], [10, 0.45]] : [],
          rumble: [[2, 0.5], [6, 0.35], [10, 0.5]],
          ride: [[0, 0.2], [8, 0.2]] }
      end
    },
    # Four on the floor under percussion that cycles 5 and 7 steps against the
    # 16-step bar, so it only realigns every few bars.
    polymetric_percussion: {
      four_on_floor: true,
      build: lambda do |bar, _rng|
        absolute = ALL_16THS.map { |s| [s, (bar * 16) + s] }
        { kick: FLOOR.map { |s| [s, 1.0] },
          clap: [[4, 0.85], [12, 0.9]],
          open: OFFBEATS.map { |s| [s, 0.55] },
          hat: absolute.select { |_, a| (a % 3).zero? }.map { |s, _| [s, 0.35] },
          metal: absolute.select { |_, a| (a % 5).zero? && a % 16 != 0 }.map { |s, _| [s, 0.6] },
          tom: absolute.select { |_, a| (a % 7).zero? && a % 4 != 0 }.map { |s, _| [s, 0.5] },
          rumble: OFFBEATS.map { |s| [s, 0.45] } }
      end
    }
  }.freeze

  module_function

  def names = PROFILES.keys

  def four_on_floor?(name) = PROFILES.fetch(name.to_sym).fetch(:four_on_floor)

  # Seeded choice: the same seed always names the same profile.
  def pick(seed) = names[Random.new(seed.to_i).rand(names.length)]

  # { role => [bar0_hits, ..., bar7_hits] }, each hit [step_float, velocity].
  # Micro-timing and the profile's swing on odd 16ths come from the seed.
  def cycle(name, seed)
    profile = PROFILES.fetch(name.to_sym)
    rng = Random.new(seed.to_i)
    swing = profile[:swing].to_f
    out = ROLES.to_h { |r| [r, Array.new(BARS) { [] }] }
    BARS.times do |bar|
      profile[:build].call(bar, rng).each do |role, hits|
        limit = [MICRO_BY_ROLE.fetch(role), MICRO_MAX_STEPS].min
        out[role][bar] = hits.map do |step, vel|
          lean = limit.zero? ? 0.0 : (rng.rand * 2 - 1) * limit
          lean += swing if swing.positive? && step.odd? && %i[hat ghost ride].include?(role)
          [(step + lean.clamp(-MICRO_MAX_STEPS, MICRO_MAX_STEPS)).round(4), vel.round(3)]
        end
      end
    end
    out
  end

  def steps(rows, role) = rows.fetch(role).map { |bar| bar.map(&:first) }
  def velocities(rows, role) = rows.fetch(role).flat_map { |bar| bar.map(&:last) }
end
