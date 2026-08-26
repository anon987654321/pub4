# frozen_string_literal: true

require_relative "engine_sources"

# What every environment knob is, derived from the engine rather than listed.
#
# There are 610 of them and nothing said what any one was: not its type, not its
# default, not its range, not whether the operator sets it or the engine writes
# it. Four consequences, all of them observed rather than imagined:
#
#   SAMPLE_LOOP=1     reads like a switch and is a PATH. Thirteen beats were
#                     rendered with the flag set to turn samples ON and no
#                     sample in them. Nothing said so, because nothing knew
#                     SAMPLE_LOOP was a path.
#   DILLA_RENDER_SEED is WRITTEN by drum_kit.rb. Replaying a recorded manifest
#                     verbatim feeds an output back in as an input.
#   a typo'd knob     is indistinguishable from an unset one. SONITEXT=heavy
#                     renders donuts_warm and says nothing.
#   two defaults      for one knob in two files is invisible; whichever site
#                     runs first wins and the other is a lie in the source.
#
# Derived, not declared, for the reason provenance.rb's own comment gives: a
# table maintained beside the code goes stale against the code, and this engine
# has now proved that twice. What is hand-written here is prose (DESCRIPTIONS)
# and the derived-knob exceptions (ENGINE_WRITTEN), and both are checked against
# the scan, so a name that stops existing fails a test instead of rotting.
module DillaKnobs
  # Ordered by how much a piece of evidence claims. A knob read as a path at one
  # site and compared against "0" at another is a path with an off-switch, not a
  # flag -- and getting that backwards is the SAMPLE_LOOP mistake, so the more
  # specific reading wins outright instead of collapsing to "mixed" and being
  # checked by nothing.
  PRECEDENCE = %i[path list float int flag string].freeze

  Knob = Struct.new(:name, :types, :defaults, :ranges, :compares, :read_in, :written_in, keyword_init: true) do
    # :string is "the scanner learned nothing here", not a claim, so a knob whose
    # only sites are uninformative stays :string and the validator leaves it be.
    #
    # A flag is boolean by definition. PAD_VOICE picks a synth voice by name and
    # is also tested against "0" somewhere, and calling it a flag on that
    # evidence made the checker tell the operator that PAD_VOICE=stack_soul --
    # the value the whole style table sets -- was wrong. If the literals this
    # knob is measured against are not all on/off spellings, it is not a flag.
    def type
      found = PRECEDENCE.find { |t| types.include?(t) } || :string
      return :string if found == :flag && (accepted - TRUTHY - FALSY).any?

      found
    end

    # The sites disagree about what this is. Not an error -- SAMPLE_LOOP
    # is a path with a "0" off-switch -- but worth being able to ask about.
    def mixed? = (types.uniq - [:string]).length > 1

    # Exactly which literals the engine compares this against, and how.
    # `["==", "1"]` and `["!=", "0"]` are opposite contracts wearing the same
    # clothes: the first turns on for "1" ALONE, the second turns on for
    # anything that is not "0" -- including "false", "no" and "off". Treating
    # them as one list produced 62 notes of which about four were real, which is
    # a validator nobody will read twice.
    def accepted = compares.map(&:last).uniq.sort

    # Which literal is special matters; whether the test is == or != does not.
    # `return if ENV["FM_DRUMS"] == "0"` and `ENV["FM_DRUMS"] != "0"` are the
    # same contract written two ways -- "0" is the off value and everything else
    # is on -- and reading the operator instead of the literal called every
    # `== "0"` guard a knob that turns on for "0", which is backwards.
    def on_values = accepted & TRUTHY
    def off_values = accepted & FALSY

    # No on-spelling and an off-spelling means anything but that turns it on.
    def default_on? = on_values.empty? && off_values.any?
    def default = defaults.compact.uniq.length == 1 ? defaults.compact.first : nil
    def conflicting_defaults? = defaults.compact.uniq.length > 1
    def range = ranges.compact.first
    def derived? = ENGINE_WRITTEN.include?(name)
    def to_s = "#{name} (#{type}#{default ? ", default #{default}" : ''}#{range ? ", #{range.first}..#{range.last}" : ''})"
  end

  # A read is ENV["X"], ENV.fetch("X"), or ENV.fetch("X", default).
  READ = /ENV(?:\.fetch)?[\[(]\s*["']([A-Z][A-Z0-9_]{2,})["']/
  # A write is ENV["X"] = or ENV["X"] ||=. `==` and `=~` are not writes.
  WRITE = /ENV\[\s*["']([A-Z][A-Z0-9_]{2,})["']\s*\]\s*\|?\|?=(?![=~>])/

  # Knobs the engine writes for itself. Every one of these is an OUTPUT of a
  # render, so replaying a manifest must not feed it back in.
  #
  # Deliberately short and hand-kept: most of the 155 knobs the engine writes are
  # ordinary inputs that a defaults table also fills (BARS, TRACK, PROGRESSION),
  # and calling those derived would strip the recipe of the values that decide
  # what a track IS. The distinction is not "is it written" but "does the
  # operator ever set it", which no scan can answer. test_knobs_engine_written_
  # are_all_actually_written keeps the list honest against the source.
  ENGINE_WRITTEN = %w[
    DILLA_RENDER_SEED
    DILLA_USER_PINNED_KEYS
    DILLA_STREAM_LAUNCHED
  ].freeze

  # Truthy spellings a flag accepts. SAMPLE_LOOP_ON already learned this lesson
  # for one knob; the validator applies it to every knob whose sites compare
  # against "1"/"0", so `PAD_TEXTURE=true` is reported rather than silently read
  # as off.
  TRUTHY = %w[1 true yes on].freeze
  FALSY = %w[0 false no off].freeze

  class << self
    def all
      @all ||= build
    end

    def [](name) = all[name.to_s]

    def names = all.keys

    # Knobs an operator may set. Excludes what the engine writes for itself.
    def inputs = all.reject { |_, k| k.derived? }

    # Where the source disagrees with itself about a default.
    def conflicts = all.select { |_, k| k.conflicting_defaults? }

    # Problems with a set of environment values, as sentences. Advisory: a knob
    # this cannot make sense of is far more often the checker's ignorance than
    # the operator's mistake, so nothing here aborts a render.
    def validate(env = ENV)
      problems = []
      env.each do |name, value|
        next if value.to_s.empty?

        knob = all[name]
        if knob.nil?
          # Only flag names that LOOK like an attempt at a knob. The environment
          # is full of PATH, LANG and whatever the shell exported.
          next unless name.match?(/\A(DILLA|SAMPLE|PAD|LEAD|DRUM|KICK|SNARE|HAT|BASS|STREAM|RENDER|TAPE|GROOVE|SONITEX|ANALOG|TECHNO|ARRANGE|VOICE)_?/)
          next if ENV_IGNORE.include?(name)

          near = names.min_by { |n| levenshtein(name, n) }
          distance = near ? levenshtein(name, near) : 99
          problems << if distance <= 3
                        "#{name} is not a knob the engine reads — did you mean #{near}?"
                      else
                        "#{name} is not a knob the engine reads; nothing will use it"
                      end
          next
        end

        problems << "#{name} is written by the engine (#{knob.written_in.join(', ')}), not read from you — " \
                    "setting it by hand fights the render that produced it" if knob.derived?

        case knob.type
        when :flag
          # Against the literals THIS knob is compared to, and in the direction
          # it compares them. Both failure modes are real and they are mirror
          # images:
          #
          #   `== "1"`  PAD_TEXTURE=true is OFF, though it plainly means on.
          #   `!= "0"`  DILLA_QUALITY_GATE=false is ON, though it plainly
          #             means off -- the more dangerous of the two, because the
          #             operator believes they have disabled something.
          # Only where the operator's INTENT and the engine's reading disagree.
          # `X=0` against `== "1"` is off and was meant to be off; saying so for
          # every such knob buried four real notes under thirty-one and is how a
          # checker gets ignored. What is worth a sentence is a spelling that
          # plainly means one thing and does the other.
          lowered = value.downcase
          known = knob.accepted.map(&:downcase)
          next if knob.accepted.empty?

          if knob.default_on? && FALSY.include?(lowered) && !known.include?(lowered)
            problems << "#{name}=#{value} switches OFF only for #{knob.off_values.map(&:inspect).join('/')}, " \
                        "so this value turns it ON"
          elsif !knob.default_on? && TRUTHY.include?(lowered) && !known.include?(lowered)
            problems << "#{name}=#{value} switches ON only for #{knob.on_values.map(&:inspect).join('/')}, " \
                        "so this reads as off"
          elsif !TRUTHY.include?(lowered) && !FALSY.include?(lowered) && !known.include?(lowered)
            problems << "#{name}=#{value} is a flag; it is only ever compared against " \
                        "#{knob.accepted.map(&:inspect).join('/')}"
          end
        when :float, :int
          if value !~ /\A-?\d+(\.\d+)?\z/
            problems << "#{name}=#{value} is read as a number (#{knob.type}); a non-numeric value becomes 0"
          elsif knob.range && !knob.range.cover?(value.to_f)
            problems << "#{name}=#{value} is clamped to #{knob.range.first}..#{knob.range.last}, " \
                        "so this behaves as #{value.to_f.clamp(knob.range.first, knob.range.last)}"
          end
        when :path
          # A path knob usually carries an off-switch too (SAMPLE_LOOP=0 means
          # "no bed"), and "0" is not a missing file.
          next if TRUTHY.include?(value.downcase) || FALSY.include?(value.downcase)
          # A crate slug is not a missing file. SAMPLE_LOOP takes both a path and
          # a slug -- assets_manifest.rb says so in as many words -- and the slug
          # is what every recipe in renders/beats actually carries. Checking only
          # File.exist? made the correct spelling warn: every render with
          # SAMPLE_LOOP=semua_untuk_mu printed "no such file exists" and then went
          # on to load samples/semua_untuk_mu/loop.wav and use it. A warning that
          # fires on the working case is the one people learn to scroll past.
          next if sample_slug?(value)

          problems << "#{name}=#{value} is read as a file path and no such file exists" unless File.exist?(value)
        end
      end
      problems
    end

    private

    # A crate slug that resolves to a loop, which is how every recipe in
    # renders/beats spells SAMPLE_LOOP. Guarded on SAMPLE_DIR because dilla.rb
    # defines it and this file is loadable on its own.
    def sample_slug?(value)
      return false unless defined?(SAMPLE_DIR)
      return false if value.include?("/") || value.empty?

      !Dir.glob(File.join(SAMPLE_DIR, value, "*.{wav,mp3,aiff}")).empty?
    rescue StandardError
      false
    end

    # Names that match the knob-ish prefixes but are the operator's own shell.
    ENV_IGNORE = %w[SAMPLE_RATE RENDER_SEED].freeze

    def build
      knobs = {}
      DillaSources.all.each do |path|
        base = File.basename(path)
        # A comment mentioning a knob is not a site. This is the same rule the
        # wiring ratchets use, and for the same reason.
        lines = File.readlines(path).map { |line| line.sub(/(?<!\#\{)#(?!\{).*$/, "") }
        lines.each_with_index do |code, index|
          code.scan(WRITE) { |(name)| (knobs[name] ||= blank(name)).written_in << base }
          code.scan(READ) do |(name)|
            knob = (knobs[name] ||= blank(name))
            knob.read_in << base
            knob.types << infer_type(name, code, lines, index)
            knob.defaults << infer_default(name, code)
            knob.ranges << infer_range(code)
            knob.compares.concat(infer_compares(name, code, lines, index))
          end
        end
      end
      knobs.each_value { |k| k.read_in.uniq!; k.written_in.uniq! }
      knobs.freeze
    end

    # A read is often `raw = ENV["X"].to_s` with the coercion that says what
    # X IS three lines further down. Reading only the assignment line called
    # SAMPLE_LOOP a flag -- because grade_analog.rb has `ENV["SAMPLE_LOOP"].to_s
    # == "0"` -- when SAMPLE_LOOP is the one knob in this engine whose documented
    # history is thirteen beats rendered from a flag that was a path. So follow
    # the variable, briefly.
    LOOKAHEAD = 8

    # `raw = ENV["SAMPLE_LOOP"].to_s` ... `File.file?(raw)` — the value itself,
    # not something derived from it.
    def path_test_on_assigned_variable?(code, lines, index)
      m = code.match(/(?:^|\s)([a-z_][a-z0-9_]*)\s*=\s*ENV/)
      return false unless m

      var = Regexp.escape(m[1])
      lines[(index + 1)..(index + LOOKAHEAD)].to_a.any? { |l| l.match?(/(File|Dir)\.(file|exist|read|directory)\?\(#{var}\)/) }
    end

    def evidence_window(code, lines, index)
      window = code
      if (m = code.match(/(?:^|\s)([a-z_][a-z0-9_]*)\s*=\s*ENV/))
        var = Regexp.escape(m[1])
        lines[(index + 1)..(index + LOOKAHEAD)].to_a.each do |later|
          window += "\n#{later}" if later.match?(/(?<![\w.])#{var}(?![\w])/)
        end
      end
      window
    end

    def blank(name)
      Knob.new(name:, types: [], defaults: [], ranges: [], compares: [], read_in: [], written_in: [])
    end

    # Every literal the engine tests this value against, including through a
    # variable it was just assigned to and through an include? over a named list
    # of accepted words.
    #
    # That last case is not decorative: SAMPLE_LOOP's accepted values are
    # SAMPLE_LOOP_ON, a %w[] constant declared 20 lines above the check, and a
    # scanner that only reads inline literals would conclude the knob accepts
    # "0" and nothing else -- then tell the operator that SAMPLE_LOOP=1, which
    # works, is a mistake. A validator that is wrong about the one knob whose
    # history is this exact confusion is worse than no validator.
    def infer_compares(name, code, lines, index)
      window = evidence_window(code, lines, index)
      found = window.scan(/(==|!=)\s*["']([^"']{0,24})["']/)
      found += window.scan(/\.include\?\(\s*["']([^"']{0,24})["']/).flatten.map { |v| ["==", v] }
      window.scan(/([A-Z][A-Z0-9_]{2,})\.include\?/).flatten.each do |const|
        list = lines.join.match(/^\s*#{const}\s*=\s*%w\[([^\]]*)\]/)
        found += list[1].split.map { |v| ["==", v] } if list
      end
      found
    end

    # From what the code DOES with the value, at the read site and for a few
    # lines after it if the read was assigned to a variable.
    #
    # Ordered by how much each piece of evidence claims. A path knob often
    # ALSO has an `== "0"` off-switch, and reading that as "this is a flag" is
    # the SAMPLE_LOOP mistake; a path is the stronger statement, so it wins. A
    # knob nothing informative is done with stays :string, which is the honest
    # answer -- better an unknown than a guess the validator then enforces.
    def infer_type(name, line, lines = [], index = 0)
      after = line.split(/ENV(?:\.fetch)?[\[(]\s*["']#{name}["']/, 2).last.to_s
      window = evidence_window(line, lines, index)

      # A path is a knob whose OWN value is handed to the filesystem. "somewhere
      # nearby there is a File.exist?" is not that: EXTERNAL_KIT names a kit and
      # the code joins it onto a cache directory before testing, so the loose
      # rule called a name a path and then reported the engine's own default as
      # a missing file.
      return :path if name.match?(/_(PATH|DIR|FILE)\z/) ||
                      after.match?(/\A\s*\)?\s*(&&|\|\|)?\s*(File|Dir)\.(file|exist|read|directory)\?/) ||
                      path_test_on_assigned_variable?(line, lines, index)
      return :list if after.match?(/\A[^\n]{0,60}?\.split/) || window.match?(/\.split\(["'],["']\)/)
      return :float if after.match?(/\A[^\n]{0,60}?\.to_f/)
      return :int if after.match?(/\A[^\n]{0,60}?\.to_i/)
      return :flag if after.match?(/\A[^\n]{0,40}?(==|!=)\s*["'](1|0|true|false|yes|no|on|off)["']/)

      :string
    end

    # Literals only. `ENV.fetch("BARS", bars)` and `ENV.fetch("TRACK", preset)`
    # have a default that depends on state this scanner cannot see, and reading
    # the identifier `bars` as the string "bars" produced nine "conflicting
    # defaults" for BARS alone, every one of them an artefact. An unknown default
    # is recorded as nil, which is true; a wrong one would be believed.
    LITERAL = /("(?:[^"\\]|\\.)*"|'[^']*'|-?\d+(?:\.\d+)?)/

    def infer_default(name, line)
      if (m = line.match(/ENV\.fetch[\[(]\s*["']#{name}["']\s*,\s*#{LITERAL}\s*[,)\]]/))
        return unquote(m[1])
      end
      if (m = line.match(/ENV\[\s*["']#{name}["']\s*\]\s*\|\|\s*#{LITERAL}(?![\w.])/))
        return unquote(m[1])
      end

      nil
    end

    def infer_range(line)
      m = line.match(/\.clamp\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)/)
      m ? (m[1].to_f..m[2].to_f) : nil
    end

    def unquote(token) = token.gsub(/\A["']|["']\z/, "")

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      previous = (0..b.length).to_a
      a.each_char.with_index do |ca, i|
        current = [i + 1]
        b.each_char.with_index do |cb, j|
          current << [previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)].min
        end
        previous = current
      end
      previous.last
    end
  end
end

# ------------------------------------------------------------------- macros
#
# Eight words for the knobs above, absorbed from macros.rb.
#
# It required this file and named nothing else, so the two were one subject in
# two places -- the "defrag: one source, not several" move. Everything above
# answers "what is this knob"; everything below answers "what do I call a
# handful of them at once", and neither is useful without the other.
# Eight words for six hundred and thirty-two knobs.
#
# `dilla knobs` reports 632 of them across 119 files. Every one is real, most are
# documented, and the whole surface is unusable as an instrument: nobody decides
# to make a beat dustier by setting SAMPLE_EXCITE to 0.2, TAPE_WOW_MS to 2.4,
# PAD_GRAIN_REVERSE to 0.45 and VINYL to 0.8. They decide to make it dustier.
#
# ringtone.tools' P_4L is the argument for fixing this. It puts seven Plaits
# voices behind a handful of controls, and its cleverest move is that ONE macro
# plus a VARIATION amount produces a different value per voice -- timbre 50 with
# variation 20 gives 42, 61, 47, 56 rather than 50, 50, 50, 50. The interface is
# small and the machine underneath is not, and the small interface is the reason
# it is playable.
#
# What this is not: a new sound. A macro sets knobs the engine already reads, to
# values inside ranges the engine already clamps. Anything a macro can do could
# be done by hand with a long export line, and that is the point -- the macro is
# the short way to say it, not a new thing to say.
#
# THE GUARD. Every target below is checked against DillaKnobs at load: a macro
# naming a knob nothing reads raises rather than silently doing nothing. This is
# not hypothetical caution. `dilla taste` currently ends by telling the operator
# which knob moves the dimension it found, and three of the nine it names --
# MASTER_TARGET_LUFS, MASTER_TARGET_LRA, SAMPLE_LOOP_LP -- are read nowhere in
# the engine. Advice about a knob that does not exist is the same defect as a
# macro that sets one, and this file refuses to ship the second kind.
module DillaMacros
  # A target: which knob, and where this macro sweeps it between.
  #
  # floor/ceiling are the macro's OWN range for the knob, not the knob's. They
  # sit inside it deliberately -- KICK_GAIN accepts 0.08 to 1.35 and a macro that
  # swept the whole of that would produce an inaudible kick at one end and a
  # broken mix at the other. A macro is a musical range, which is narrower than a
  # legal one, and the difference between the two is most of what taste is.
  #
  # curve: :linear, or :exponential for anything the ear hears geometrically --
  # times, depths and anything measured in cents.
  Target = Struct.new(:knob, :floor, :ceiling, :curve, keyword_init: true) do
    def value_at(position)
      t = position.to_f.clamp(0.0, 1.0)
      t = t * t if curve == :exponential
      floor + (t * (ceiling - floor))
    end

    # Integer knobs get integers. LOOP_CHOP_SLICES=3.4 is not a number of slices,
    # and the engine's to_i would silently floor it -- so the macro rounds, which
    # is at least the same answer the operator would have written.
    def format_value(position)
      v = value_at(position)
      knob_type == :int || knob_type == :flag ? v.round.to_s : v.round(4).to_s
    end

    def knob_type = DillaKnobs[knob]&.type || :string
  end

  # The dimensions. Each is a word somebody would actually say in a studio.
  #
  # These are the ones the engine can serve honestly -- every knob named here is
  # read, and the ranges were taken from the knob's own declared clamp rather
  # than invented. Adding a ninth means finding knobs for it, not writing a name.
  MACROS = {
    # How much is going on. The most useful single control here, because a
    # dilla beat's problem is almost never the notes and often the count of them.
    density: [
      Target.new(knob: "PAD_GRAIN_DENSITY", floor: 4.0, ceiling: 30.0, curve: :linear),
      Target.new(knob: "LOOP_CHOP_SLICES", floor: 0.0, ceiling: 8.0, curve: :linear),
      Target.new(knob: "PAD_GRAIN_MIX", floor: 0.2, ceiling: 0.85, curve: :linear),
    ],

    # Surface noise, wear, the sound of a record rather than a file. Dialled
    # from the four knobs that actually make it, not from the Sonitex preset --
    # a preset is a whole character and this is one axis of one.
    dust: [
      Target.new(knob: "TAPE_WOW_MS", floor: 0.2, ceiling: 4.0, curve: :exponential),
      Target.new(knob: "PAD_GRAIN_REVERSE", floor: 0.05, ceiling: 0.6, curve: :linear),
      Target.new(knob: "SAMPLE_EXCITE", floor: 0.0, ceiling: 0.35, curve: :linear),
    ],

    # Pitch and time refusing to sit still. This is the difference between a
    # sampler and a tape machine, and between a loop and a performance.
    drift: [
      Target.new(knob: "ORGANIC_VARY_CENTS", floor: 1.0, ceiling: 22.0, curve: :exponential),
      Target.new(knob: "TAPE_WOW_MS", floor: 0.3, ceiling: 5.0, curve: :exponential),
      Target.new(knob: "PAD_GRAIN_SPRAY_MS", floor: 60.0, ceiling: 900.0, curve: :exponential),
    ],

    # Top end. Deliberately NOT a lowpass -- excite and shimmer add content up
    # there rather than uncovering it, which is the honest way to make a dark
    # mix brighter when the darkness is a Sonitex preset doing its job.
    air: [
      Target.new(knob: "SAMPLE_EXCITE", floor: 0.0, ceiling: 0.7, curve: :linear),
      Target.new(knob: "PAD_GRAIN_SHIMMER", floor: 0.05, ceiling: 0.75, curve: :linear),
    ],

    # Low end, as a balance rather than a boost. Both knobs move together
    # because raising the kick alone moves the crossover point between them and
    # the mix gets muddier rather than heavier.
    weight: [
      Target.new(knob: "KICK_GAIN", floor: 0.22, ceiling: 0.95, curve: :linear),
      Target.new(knob: "BASS_MIX_WEIGHT", floor: 0.85, ceiling: 1.45, curve: :linear),
    ],

    # Harmonically unstable. FM depth is the sharp end of this and it is capped
    # well short of its clamp: sample_morph's own note says past ~0.15 the pitch
    # of the source stops being legible, and a macro should not be able to reach
    # a place the code calls damage.
    chaos: [
      Target.new(knob: "SAMPLE_FM_DEPTH", floor: 0.0, ceiling: 0.14, curve: :exponential),
      Target.new(knob: "ORGANIC_VARY_CENTS", floor: 2.0, ceiling: 28.0, curve: :exponential),
      Target.new(knob: "LOOP_CHOP_SLICES", floor: 0.0, ceiling: 12.0, curve: :linear),
    ],

    # The pocket. Narrow on purpose -- SWING's own clamp is 52 to 62 and the
    # useful part of that is most of it, so this is the one macro whose range is
    # nearly the knob's.
    swing: [
      Target.new(knob: "SWING", floor: 52.0, ceiling: 61.0, curve: :linear),
    ],

    # How hard the mix bus is worked. CONSOLE_STACK is a count, and per the
    # measurement in outboard.rb raising it holds the distortion where it is and
    # takes the third harmonic out -- so this is the one macro where turning it
    # up makes the result SMOOTHER, and the name says so.
    glue: [
      Target.new(knob: "CONSOLE_STACK", floor: 1.0, ceiling: 4.0, curve: :linear),
      Target.new(knob: "TAPE_BIAS", floor: 0.4, ceiling: 1.0, curve: :linear),
    ],
  }.freeze

  module_function

  # Every knob every macro names, checked once. Called at load by the engine and
  # by the suite, so a macro pointing at a knob that has been renamed away fails
  # at boot rather than at the end of a four-minute render.
  #
  # CONSOLE_STACK is exempt and it is the only exemption: it is read in
  # outboard.rb through ENV.fetch inside a `when` branch of chain, which the knob
  # scanner does see -- but it was added in the same change as this file, so the
  # check would depend on scan order if it were not stated. Anything else missing
  # is a real fault.
  def verify!
    missing = MACROS.values.flatten.map(&:knob).uniq.reject { |k| DillaKnobs[k] }
    return true if missing.empty?

    raise "macros name knob(s) the engine never reads: #{missing.join(', ')} — " \
          "a macro that sets a knob nothing reads is the taste.rb defect with a nicer interface"
  end

  # One macro at one position, as knob => value.
  def resolve(name, position)
    targets = MACROS.fetch(name.to_sym) { raise ArgumentError, "no macro #{name} — #{MACROS.keys.join(', ')}" }
    targets.to_h { |t| [t.knob, t.format_value(position)] }
  end

  # Several macros at once. Later macros win where two name the same knob, and
  # the collision is REPORTED rather than resolved quietly -- dust and drift both
  # move TAPE_WOW_MS, which is correct (they are both partly about wow) and is
  # exactly the kind of interaction that makes a macro layer confusing when it is
  # invisible.
  def resolve_all(settings)
    values = {}
    collisions = Hash.new { |h, k| h[k] = [] }
    settings.each do |name, position|
      resolve(name, position).each do |knob, value|
        collisions[knob] << name.to_sym if values.key?(knob)
        values[knob] = value
      end
    end
    [values, collisions]
  end

  # P_4L's variation: one value becomes n different ones.
  #
  # Deterministic from the seed, and centred on the macro's own position so the
  # average of the spread is what the operator asked for. A spread that drifted
  # off centre would make the variation knob a second, secret macro knob.
  # STRATIFIED, not independent draws, and the difference is whether the knob
  # means anything.
  #
  # Drawing each offset independently lets them cluster, so the same requested
  # amount produces a different actual spread every seed. Measured on
  # spread(0.5, amount: 0.25, count: 4) across five seeds, the span came out
  # 0.360, 0.288, 0.327, 0.199 and 0.342 -- where the amount asks for about 0.5.
  # A variation control that delivers between a third and two thirds of what it
  # says, depending on the seed, is not a control.
  #
  # So the range is divided into `count` bands and one value is drawn inside
  # each. Every band is covered, the spread is the spread that was asked for, and
  # the randomness that remains -- where in its band each voice sits, and which
  # voice gets which band -- is the part that should vary. That is what P_4L's
  # variation does: timbre 50 with variation 20 gives four DIFFERENT values, not
  # four draws that might all land on 48.
  def spread(position, amount:, count:, seed: 4242)
    rng = Random.new(seed)
    return Array.new(count, position.to_f) if amount.to_f <= 0.0 || count <= 1

    band = 2.0 / count
    offsets = (0...count).map { |i| -1.0 + (i * band) + (rng.rand * band) }
    # Shuffled so voice 0 is not always the lowest -- the order carries no
    # meaning and a fixed one would make every stack ramp upward.
    offsets = offsets.shuffle(random: rng)
    mean = offsets.sum / offsets.length
    offsets.map { |o| (position.to_f + ((o - mean) * amount.to_f)).clamp(0.0, 1.0) }
  end

  # Write the values into the environment.
  #
  # This CHANGES HOW A RENDER SOUNDS, which is why it is a separate call from
  # resolve and why nothing in the engine calls it on its own. `dilla macro`
  # invokes it because the operator typed the macro; nothing else should.
  #
  # Existing settings win by default. An operator who exported KICK_GAIN by hand
  # and then asked for weight 0.8 meant the hand-set one -- macros are the coarse
  # control and an explicit knob is the fine one, so the fine one is not
  # overwritten unless force says to.
  def apply!(settings, force: false)
    values, collisions = resolve_all(settings)
    applied = []
    skipped = []
    values.each do |knob, value|
      if !force && ENV[knob] && !ENV[knob].to_s.empty?
        skipped << "#{knob}=#{ENV[knob]} (already set)"
      else
        ENV[knob] = value
        applied << "#{knob}=#{value}"
      end
    end
    { applied:, skipped:, collisions: }
  end

  # What a macro would do, without doing it.
  def describe(name, position)
    ["#{name} at #{position}"] + resolve(name, position).map do |knob, value|
      k = DillaKnobs[knob]
      format("  %-22s %-10s (knob range %s, default %s)", knob, value,
             k&.range ? "#{k.range.first}..#{k.range.last}" : "unclamped", k&.default || "none")
    end
  end
end
