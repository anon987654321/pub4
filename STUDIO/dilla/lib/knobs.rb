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

    # The sites disagree about what this is. Not an error -- SAMPLE_LOOP really
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

    # A read is very often `raw = ENV["X"].to_s` with the coercion that says what
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
    # Ordered by how much each piece of evidence claims. A path knob very often
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
