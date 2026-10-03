# frozen_string_literal: true

# The engine's bookkeeping: frozen learned state, the dmesg log, seeds, the
# knob census, provenance sidecars, the learned priors and the asset
# fingerprints.

require "json"

# DILLA_FROZEN=1 — read the learned state, write none of it.
#
# The engine learns. session.json carries the performer, the groove and the
# generation counter; learned_engine.json carries what the source study found;
# promoted_profiles.json carries which profiles earned their place; the vocal
# and chop catalogues carry what has been ingested. All of it is read on the
# next run and all of it changes what comes out.
#
# That is the point of the feature and it is also why two renders of the same
# command are not the same render. Trying to A/B a change means holding
# everything else still, and this engine could not: a comparison take rendered
# before and after a refactor differed because session.json had moved between
# them, not because the refactor did anything. That comparison was abandoned
# rather than published, which is the honest outcome and a bad one -- it means
# the refactor shipped unmeasured.
#
# So: frozen reads exactly as before and writes nothing back. Renders still
# differ from each other by seed; what stops moving is the accumulated state
# underneath them. Every skipped write is announced once, because a mode that
# silently drops data would be a worse bug than the one it fixes.
#
# Not a substitute for RENDER_SEED. Seed pins the dice; this pins the table.
module DillaFrozen
  class << self
    def on? = ENV["DILLA_FROZEN"] == "1"

    # Every persistent-state write goes through here. Returns true when it
    # wrote, false when frozen -- callers that report a path to the operator
    # need to know which happened.
    def write(path, content)
      unless on?
        File.write(path, content)
        return true
      end

      skipped(path)
      false
    end

    def write_json(path, data)
      write(path, "#{JSON.pretty_generate(data)}\n")
    end

    # A record read back to be written again: the playlist catalogue, the
    # learned engine, the vocal catalogue. Absent is an empty record. Present and
    # unreadable is kept beside itself as <name>.unreadable before the empty
    # record comes back, because every one of these callers saves what it
    # loaded, and that save replaced the only copy of what had been there.
    def read_json(path, empty)
      return empty unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      keep = "#{path}.unreadable"
      keep = "#{keep}.#{Time.now.to_i}" if File.exist?(keep)
      File.write(keep, File.binread(path)) unless on?
      warn "#{path} is not readable JSON (#{e.message}); #{on? ? 'frozen, so not copied' : "kept as #{File.basename(keep)}"}, read as empty"
      empty
    end

    # What a run declined to write. Recorded so provenance can say the render
    # was made against held state rather than leaving that to be inferred.
    def skips = @skips ||= []

    def skipped(path)
      short = path.to_s.sub("#{File.expand_path('..', __dir__)}/", "")
      return if skips.include?(short)

      skips << short
      warn "frozen: not writing #{short} (DILLA_FROZEN=1)"
    end

    def reset! = @skips = []
  end
end

# OpenBSD-style kernel dmesg logging for the Dilla engine.
#
# Format (device-attach + fact lines), inspired by OpenBSD dmesg collections
# and MASTER house style (postpro / chat dmesg / OPENBSD/RUNBOOK.md):
#
#   dilla0 at mainbus0: ruby3.4.5 pid=12345 mode=dilla
#   stream0 at dilla0: continuous bars=32 mode=fast
#   track0 at stream0: quartal_west_coast pad=blend/wash lead=0
#   exec0 at dilla0: run ffmpeg exit=0 +1.24s
#   audio0 at dilla0: write demo.wav 15735666B
#   warn0 at dilla0: speech tts segment failed
#
# Control:
#   DILLA_DMESG=0   silence
#   DILLA_DMESG=1   normal (default)
#   DILLA_DMESG=2   verbose (full argv, tool stderr tails)
#   DILLA_VERBOSE=1 same as DILLA_DMESG=2
#   DILLA_DEBUG=1   same as DILLA_DMESG=2
module DillaDmesg
  BOOT_T0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  INTERACTIVE_BINS = %w[afplay ffplay].freeze

  module_function

  def enabled?
    ENV.fetch("DILLA_DMESG", "1") != "0"
  end

  def verbose?
    ENV["DILLA_DMESG"] == "2" || ENV["DILLA_VERBOSE"] == "1" || ENV["DILLA_DEBUG"] == "1"
  end

  def elapsed
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - BOOT_T0
  end

  def elapsed_tag
    "+%.3fs" % elapsed
  end

  # Core emit: "unit at parent: message" or "unit: message"
  def emit(unit, msg, parent: nil, stream: $stderr)
    return unless enabled?
    text = msg.to_s.strip.downcase
    text = text.gsub(/\s+/, " ")
    line = if parent
             "#{unit} at #{parent}: #{text}"
           else
             "#{unit}: #{text}"
           end
    stream.puts line
    stream.flush
    line
  end

  def ok(msg, unit: "dilla0", parent: nil)
    emit(unit, msg, parent:)
  end

  # These print to the stream rather than through Kernel#warn, so the
  # provenance tap on Warning.warn cannot see them; they are handed over here,
  # and before `emit`, because DILLA_DMESG=0 silences the line but not the fault.
  def warn(msg, unit: "warn0", parent: "dilla0")
    DillaProvenance.record_warning("#{unit}: warn #{msg}") if defined?(DillaProvenance)
    emit(unit, "warn #{msg}", parent:)
  end

  def error(msg, unit: "error0", parent: "dilla0")
    DillaProvenance.record_warning("#{unit}: error #{msg}") if defined?(DillaProvenance)
    emit(unit, "error #{msg}", parent:)
  end

  def attach(unit, parent, msg = nil)
    body = msg.to_s.strip.empty? ? "attached" : msg
    emit(unit, body, parent:)
  end

  def boot!(mode: nil, cmd: nil)
    host = RbConfig::CONFIG["host_os"].to_s.split.first
    bits = [
      "ruby#{RUBY_VERSION}",
      "os=#{host}",
      "pid=#{Process.pid}",
      ("mode=#{mode}" if mode),
      ("cmd=#{cmd}" if cmd),
      elapsed_tag,
    ].compact
    emit("dilla0", bits.join(" "), parent: "mainbus0")
  end

  def stream!(mode:, bars:, order_n: nil)
    bits = ["continuous", "bars=#{bars}", "mode=#{mode}", ("tracks=#{order_n}" if order_n), elapsed_tag]
    emit("stream0", bits.compact.join(" "), parent: "dilla0")
  end

  def track!(name, meta)
    emit("track0", "#{name} #{meta}", parent: "stream0")
  end

  def write!(path, bytes: nil)
    base = File.basename(path.to_s)
    size = bytes || (File.file?(path) ? File.size(path) : nil)
    bits = ["write", base, (size ? "#{size}B" : nil), elapsed_tag].compact
    emit("audio0", bits.join(" "), parent: "dilla0")
  end

  def read!(path, bytes: nil)
    base = File.basename(path.to_s)
    size = bytes || (File.file?(path) ? File.size(path) : nil)
    bits = ["read", base, (size ? "#{size}B" : nil)].compact
    emit("audio0", bits.join(" "), parent: "dilla0")
  end

  def run!(cmd_display, exitstatus:, seconds: nil, unit: "exec0")
    bin = cmd_display.to_s.split.first.to_s
    short = verbose? ? truncate(cmd_display, 200) : bin
    bits = ["run", short, "exit=#{exitstatus}", (seconds ? "+%.2fs" % seconds : nil), elapsed_tag].compact
    emit(unit, bits.join(" "), parent: "dilla0")
  end

  def play!(tool, path)
    emit("play0", "#{tool} #{File.basename(path.to_s)}", parent: "dilla0")
  end

  def style!(keys)
    emit("style0", keys.to_s, parent: "dilla0")
  end

  def metrics!(hash)
    return unless hash.is_a?(Hash)
    parts = hash.map { |k, v| "#{k}=#{v.is_a?(Float) ? format('%.1f', v) : v}" }
    emit("meter0", parts.join(" "), parent: "dilla0")
  end

  def truncate(s, n)
    s = s.to_s
    s.bytesize <= n ? s : "#{s.byteslice(0, n)}…"
  end

  def interactive_bin?(command)
    bin = Array(command).flatten.first.to_s
    INTERACTIVE_BINS.include?(File.basename(bin))
  end
end

require "digest"
require "json"

# The render seed, and the text seed that names one: swing, BPM and the RNG a
# render draws from.
module DillaSeeds
  module_function

  # The text seed is the only seed a render derives from something outside its
  # own knobs, and it stays in the process. DILLA_SEED_URL, SEISMIC_SEED and
  # WEATHER_SEED fetched a tempo and a swing from the network at render time,
  # which broke the two promises this engine is built on: it never phones home,
  # and a take is made again from its knobs and its seed. The USGS feed and the
  # forecast change by the hour, so a seeded take could not be rendered twice,
  # and SEISMIC_SEED's other write, HARM_VOL, reaches no render at all.
  def apply!
    apply_text_seed!
  end

  def apply_to_cfg!(cfg)
    apply!
    cfg[:swing] = ENV["SWING"].to_f if ENV["SWING"]
    cfg[:bpm] = ENV["BPM"].to_f if ENV["BPM"]
    cfg
  end

  # SEED_TEXT names a seed by its text, so the same text must name the same seed
  # in every process. Ruby randomises String#hash per process (a security
  # default), so it cannot carry that promise; a SHA-256 digest is stable across
  # runs. SWING and BPM are derived from the same value, so they were drifting too.
  def stable_seed(text) = Digest::SHA256.hexdigest(text.to_s).to_i(16) % (1 << 62)

  # The last resort was reached on every ordinary render. DillaProvenance sets
  # RENDER_SEED before any command runs, so a pinned seed was always sitting in
  # the environment while this drew a fresh one anyway: three processes given
  # RENDER_SEED=1615715775 answered 270549, 60260 and 344463. The value becomes
  # @render_seed and DILLA_RENDER_SEED, which groove_engine reads for its
  # per-bar phrase and pattern choices -- so the groove moved between two runs
  # of the same recipe and every sidecar's "Reproduce with:" line promised
  # something the engine could not do.
  #
  # GEN_SEED and SEED_TEXT still win, because someone who sets either has named
  # the seed on purpose. rand stays underneath for library use where provenance
  # never ran.
  def render_seed
    base = ENV["GEN_SEED"]&.to_i
    return base if base&.positive?
    text = ENV["SEED_TEXT"].to_s
    return stable_seed(text) % 1_000_000 if text.length.positive?
    pinned = ENV["RENDER_SEED"].to_i
    return pinned if pinned.positive?
    rand(1_000_000)
  end

  def apply_text_seed!
    text = ENV["SEED_TEXT"]
    return unless text && !text.empty?
    h = stable_seed(text)
    ENV["GEN_SEED"] ||= h.to_s
    ENV["SWING"] ||= (52 + (h % 11)).to_s
    ENV["BPM"] ||= (84 + (h % 18)).to_s
  end

  def drift_sleep(base = 0.5)
    return base if ENV["DRIFT_SLEEP"] == "0"
    jitter = Random.new(Process.pid + Time.now.to_i).rand(-0.12..0.18)
    [base + jitter, 0.05].max
  end
end

require_relative "engine_sources"

# What every environment knob is, derived from the engine rather than listed.
#
# Every ENV name the engine reads or writes, with the type, default, range and
# accepted literals its own call sites prove it has, and which side of the line
# it sits on: an input the operator sets, or a value the engine writes. The count
# moves with the engine, so it is not written down here -- `dilla knobs` prints
# it, split into the two halves. Four consequences of having none of this, all of
# them observed rather than imagined:
#
#   SAMPLE_LOOP=1     reads like a switch and is a PATH. Thirteen beats were
#                     rendered with the flag set to turn samples ON and no
#                     sample in them. Nothing said so, because nothing knew
#                     SAMPLE_LOOP was a path.
#   DILLA_RENDER_SEED is WRITTEN by the drum_kit engine part. Replaying a recorded manifest
#                     verbatim feeds an output back in as an input.
#   a typo'd knob     is indistinguishable from an unset one. SONITEXT=heavy
#                     renders donuts_warm and says nothing.
#   two defaults      for one knob in two files is invisible; whichever site
#                     runs first wins and the other is a lie in the source.
#
# Derived, not declared, for the reason ledger.rb's own comment gives: a
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

  Knob = Struct.new(:name, :types, :defaults, :ranges, :compares, :read_in, :written_in,
                    :default_sites, :opaque_sites, keyword_init: true) do
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

    # A knob with a non-literal default somewhere has a conflict list that is
    # incomplete rather than wrong, and the difference matters. BPM is the case
    # that proves it: two literal sites say 92 and 90, and the site that decides
    # every render says `ENV["BPM"] || DEFAULT_BPM`, which is 86 and which no
    # scan of literals can see. Reporting "92 against 90" without this reads as
    # the whole story and names neither the real default nor a site that touches
    # audio.
    def incomplete_defaults? = opaque_sites.any?
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
  ].freeze

  # What a switch does when it is turned on, which no scan of a comparison can
  # tell. Three kinds, and the difference decides what folding one into the
  # defaults means:
  #
  #   additive     adds a layer, a device or a variation on top of what already
  #                plays: turning it on is a new sound over the old one, and the
  #                "devices on" direction is about these.
  #   fork         plays one path instead of another -- a timing, a kit, a
  #                harmony language, a source -- so on is a different render,
  #                not a richer one, and two forks can contradict each other.
  #   operational  changes how a run behaves and not what it sounds like: logs,
  #                locks, supervisors, gates, caches, the demo's bookkeeping.
  #
  # Hand-kept, because the kind is a fact about the branch a switch guards, and
  # checked against the scan by test_every_classified_switch_is_a_knob_the_engine_
  # reads, so a switch that stops existing fails a test rather than lingering
  # here. A flag in no list is additive until someone reads its branch and says
  # otherwise; `dilla knobs flags` prints the three lists.
  FLAG_KINDS = {
    fork: %w[
      BASS_CONTRARY BPM_STAIRCASE CHORAL_PADS CREEPY_PATCHES DILLA_COMFORT DILLA_FS_DRY DILLA_MIX_BUSES
      DRUM_ROTATE_CURATED DRUM_SAMPLE_RAW ELECTRONIUM_CLASSIC EUCLIDEAN_HATS FLIP FLIP_RECORDS FLUTES
      FM_DRUMS FM_NATIVE GENRE_HARMONY GOLDEN_SWING HALFTIME HARMONIC_KEEP HARMONIC_SHUFFLE KICK_SNARE_SWAP
      LAYER_KICK LEAD_FORCE_ARP LOOP_PAD_ROTATE MELODIC_LEAD MIDI_BAG NO_QUANTIZE OWN_VOCALS
      PATCH_PER_PROGRESSION RAP_VOCAL_RAW RAP_VOCAL_SKIP_LOUDNORM RAW_KICK REHARM_LOOP SAMPLE_FM SAMPLE_SCALE
      SLASH_BASS SOUL_ENRICH STREAM_COMFORT STREAM_CREATIVE STREAM_PUNCH TECHNO_HARMONY TEMPO_ACCEL TEMPO_RAMP
      THEORY_BACH THEORY_PEDAL WONKY_DRUMS_ONLY
    ].freeze,
    operational: %w[
      CHOP_FRESH CRATE_ALLOW_SHARE_ALIKE DEBUG_NO_LOUDNORM DEMO_ALBUM_NORM DEMO_CRATE DEMO_EACH DEMO_FORCE
      DEMO_KEEP_PARTS DEMO_NO_LOCK DILLA_AGENT_LAUNCHED DILLA_DETACH DILLA_FORCE_TERMINAL DILLA_FROZEN
      DILLA_JSON DILLA_NO_PROVENANCE DILLA_OVERWRITE DILLA_QUIET DILLA_RAW DILLA_SOFT_SH DILLA_STREAMING
      DILLA_STREAM_LAUNCHED DILLA_STREAM_SUPERVISOR ELECTRONIUM_RENDER FORCE_KIT GROK_AGENT HATE_ARRIVED
      MODE_UNCERTAIN PHONE_PREVIEW_GATE REBUILD SAMPLE_CARRIES_HARMONY SKIP_VOLUME_NUDGE STREAM_CONTINUOUS
      STREAM_DEEP STREAM_ITERATE STREAM_LOCK STREAM_NORMALIZE STREAM_TRACK VOICE_STACK_STEMS
    ].freeze,
  }.freeze

  # DILLA_STREAM_LAUNCHED is deliberately NOT on that list, though the engine
  # does write it (stream.rb, twice). It fails both criteria above: it is not an
  # output of a render, and the operator does set it -- stream.rb reads it as
  # "I already have a shell, do not open Terminal.app", which is the only way to
  # run a continuous stream from an agent shell on macOS. Listing it here meant
  # using the documented escape hatch printed a warning telling you not to, and
  # believing that warning let stream() spawn a Terminal window and exit.

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

    # Every switch that is off unless set, by kind: FLAG_KINDS's two named lists,
    # and additive for the rest. A default-on switch is already part of the
    # sound, so what turning it on does is not a question it raises.
    def flags_by_kind
      flags = all.values.select { |knob| knob.type == :flag && !knob.default_on? }.map(&:name).sort
      named = FLAG_KINDS.values.flatten
      FLAG_KINDS.transform_values { |names| names & flags }.merge(additive: flags - named)
    end

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
          # a slug -- ledger.rb says so in as many words -- and the slug
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
        # The enclosing method, carried down the scan. Two of the seven remaining
        # conflicts are the two arms of one `if` inside a single method
        # (evolve_weights), and two more are two different gates; a reader who
        # sees the method name adjudicates in a glance where a file name alone
        # sent them grepping.
        enclosing = nil
        lines.each_with_index do |code, index|
          enclosing = Regexp.last_match(1) if code =~ /^\s*def\s+(?:self\.)?([a-z_][\w?!]*)/
          writes_here = code.scan(WRITE).flatten
          writes_here.each { |name| (knobs[name] ||= blank(name)).written_in << base }
          code.scan(READ) do |(name)|
            knob = (knobs[name] ||= blank(name))
            knob.read_in << base
            knob.types << infer_type(name, code, lines, index)
            found = infer_default(name, code, writes_here:)
            # The site, not just the value. Adjudicating "0.18 against 0.08
            # against 0.12" meant grepping three files to discover that two of
            # the three are the arms of one `if`; with the line numbers it takes
            # a glance.
            site = "#{base}:#{index + 1}"
            case found
            when :opaque then knob.opaque_sites << site
            when nil then nil
            else
              knob.defaults << found
              knob.default_sites << "#{site} #{found}#{enclosing ? " (#{enclosing})" : ''}"
            end
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
      Knob.new(name:, types: [], defaults: [], ranges: [], compares: [], read_in: [], written_in: [],
               default_sites: [], opaque_sites: [])
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
    # is :opaque, which is true and is counted; a wrong one would be believed.
    LITERAL = /("(?:[^"\\]|\\.)*"|'[^']*'|-?\d+(?:\.\d+)?)/
    # A default of some kind is present here, literal or not.
    ANY_DEFAULT = /(?:ENV\.fetch[\[(]\s*["']NAME["']\s*,|ENV\[\s*["']NAME["']\s*\]\s*\|\|)/

    # Two shapes carry a literal that is provably not this knob's default, and
    # both were being reported as one. Each cost an audit: the ten-conflict list
    # of 2026-09-10 was six false positives, and the sharpest of them —
    # MELODIC_LEAD reading "0" at one site and "1" at another — was a sentinel
    # against a real default, so a reader was invited to pick a sound where there
    # was nothing to pick.
    #
    # The presence sentinel. `ENV.fetch("MELODIC_LEAD", "0") != "0"` asks whether
    # the knob is set to anything; the fetch default exists so the answer is no
    # when it is unset, and it is the comparand rather than a value the engine
    # ever uses. Only when the two literals are the SAME literal —
    # `ENV.fetch("SAMPLE_NATIVE_BPM", "1") != "0"` defaults to "1".
    SENTINEL = /ENV\.fetch[\[(]\s*["']NAME["']\s*,\s*(["'][^"']*["']|-?\d+(?:\.\d+)?)\s*[)\]]\s*(?:==|!=)\s*\1(?![\w.])/

    # The self-updating fallback. `ENV["PAD_VOL"] = ((ENV["PAD_VOL"] || "52")
    # .to_i + 2).to_s` reads a knob to raise it; "52" is the base of an increment,
    # not what the engine renders with when nobody set it. Recorded as opaque
    # rather than dropped, because a line that both reads and writes a knob is
    # exactly where a real default can hide.
    def infer_default(name, line, writes_here: [])
      pattern = ->(re) { Regexp.new(re.source.sub("NAME", Regexp.escape(name))) }
      return nil if line.match?(pattern.call(SENTINEL))
      return :opaque if writes_here.include?(name)

      # A chained fallback belongs to the chain. In `ENV["STREAM_HARMONY_EVERY"]
      # || ENV["EVOLVE_EVERY"] || "2"` the literal is reached only when both are
      # unset, so calling it EVOLVE_EVERY's default and comparing it against the
      # "3" a different method uses invents a disagreement between two cadences
      # that were never the same cadence.
      before = line.split(/ENV(?:\.fetch)?[\[(]\s*["']#{Regexp.escape(name)}["']/, 2).first.to_s
      chained = before.match?(/ENV(?:\.fetch)?[\[(]\s*["'][A-Z][A-Z0-9_]{2,}["']/)

      if (m = line.match(/ENV\.fetch[\[(]\s*["']#{name}["']\s*,\s*#{LITERAL}\s*[,)\]]/))
        return chained ? :opaque : unquote(m[1])
      end
      if (m = line.match(/ENV\[\s*["']#{name}["']\s*\]\s*\|\|\s*#{LITERAL}(?![\w.])/))
        return chained ? :opaque : unquote(m[1])
      end

      line.match?(pattern.call(ANY_DEFAULT)) ? :opaque : nil
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
# Eight words for seven hundred and twenty-nine knobs.
#
# `dilla knobs` counts them on demand and is the figure to trust; a number typed
# into this comment is stale the next time a knob lands. It reports 729 across 45
# files as this is written. Every one is real, most are
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
    # measurement in sound.rb raising it holds the distortion where it is and
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
  # sound.rb through ENV.fetch inside a `when` branch of chain, which the knob
  # scanner does see -- but it was added in the same change as this file, so the
  # check would depend on scan order if it were not stated. Anything else missing
  # is a real fault.
  def verify!
    missing = MACROS.values.flatten.map(&:knob).uniq.reject { |k| DillaKnobs[k] }
    return true if missing.empty?

    raise "macros name knob(s) the engine never reads: #{missing.join(', ')} — " \
          "a macro that sets a knob nothing reads is the listen.rb defect with a nicer interface"
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

require "json"
require "digest"
require "time"
require "English"

# Every rendered file gets a recipe beside it, so any render can be made again.
#
# Before this, none could. RENDER_SEED already pinned the whole engine — patch
# selection, all 31 anoisesrc sites, the 26 seeds built out of
# Ruby's per-process String#hash — and that work was thorough. What was missing
# is that nothing ever wrote the seed down. Unset, the engine draws from
# Process.pid and ffmpeg's own RNG, so a render was gone the moment it finished:
# su_tunnel_choir.wav (2026-08-11 03:35) cannot be reproduced, and neither can
# any of the 616 audio files beside it.
#
# So the seed is always chosen now, never left to chance-without-a-record. If
# RENDER_SEED is set, that is used and honoured exactly as before. If it is not,
# one is drawn at random — the render still differs from the last, which is the
# behaviour the engine documents and wants — and then written into a sidecar
# next to every audio file the run produced: <audio>.provenance.json.
#
# The consequence worth stating plainly: an unpinned render is now produced
# through the pinned code paths, because ENV["RENDER_SEED"] is set before any of
# them run. render_pinned? is true, so noise comes from seed_for(tag) rather than
# ffmpeg's seed=-1, and every draw is seeded rather than rand. Two unpinned
# renders still differ from each other exactly as they did. What changes is that
# each one is now a draw that can be replayed instead of one that cannot.
#
# DILLA_NO_PROVENANCE=1 restores the old behaviour completely, seed and all.
module DillaProvenance
  MANIFEST_EXT = ".provenance.json"
  AUDIO = %w[.wav .mp3 .flac .ogg .m4a .aiff .aif].freeze
  SCHEMA = "dilla.render.v1"

  # Directories whose contents are inputs rather than outputs. Recording a
  # recipe for a sample someone dragged in would be a lie about where it came
  # from, and .cache holds generated copies nothing should be asked to rebuild.
  SKIP = %r{/(\.git|\.cache|node_modules)/}

  # See tap_warnings!. The limit keeps a stream that warns every bar from
  # writing a megabyte of sidecar; the count still says how many there were.
  WARNING_LIMIT = 200

  module WarningTap
    def warn(message, *args, **kwargs)
      DillaProvenance.record_warning(message)
      super
    end
  end

  class << self
    attr_reader :seed, :started_at

    def disabled? = ENV["DILLA_NO_PROVENANCE"] == "1"

    # Called once, before any command runs.
    def begin!(root: Dir.pwd, argv: ARGV)
      return if disabled?

      @root = root
      @argv = argv.dup
      @started_at = Time.now
      @seed = pin_seed!
      @before = snapshot
      @explicit = @explicit_seed
      tap_warnings!
      at_exit { finish! }
    end

    # What the run said went wrong, kept for the manifest.
    #
    # The engine rescues an optional stage — a missing sample, a gem that hangs,
    # a tool that is not installed — by warning and carrying on, over a hundred
    # times in dilla.rb alone. That is right for a render and wrong for its
    # record: the take comes out degraded and its sidecar read exactly like a
    # clean one's. Every such warning goes through Kernel#warn, which calls
    # Warning.warn, so tapping that one method sees all of them without touching
    # a single rescue. A manifest with no `warnings` key is a run that warned
    # about nothing.
    def tap_warnings!
      Warning.extend(WarningTap) unless Warning.singleton_class.include?(WarningTap)
    end

    def record_warning(message)
      @warning_count = warning_count + 1
      recorded_warnings << message.to_s.strip if recorded_warnings.size < WARNING_LIMIT
    end

    def warning_count = @warning_count || 0
    def recorded_warnings = @recorded_warnings ||= []

    def warnings_record
      return nil if warning_count.zero?

      { "count" => warning_count, "lines" => recorded_warnings.dup }
    end

    # A seed exists for every render. An explicitly set RENDER_SEED is left
    # alone — someone comparing two renders has chosen their constant and this
    # must not move it.
    def pin_seed!
      given = ENV["RENDER_SEED"].to_s
      if given.empty?
        @explicit_seed = false
        drawn = Random.new_seed % (2**31)
        ENV["RENDER_SEED"] = drawn.to_s
        drawn
      else
        @explicit_seed = true
        given.to_i
      end
    end

    def finish!
      return if disabled? || @before.nil?
      return if @finished

      @finished = true
      produced.each { |path| write_manifest(path) }
    rescue StandardError => e
      # A render that succeeded must not be reported as failed because its
      # bookkeeping did not.
      warn "provenance: #{e.class}: #{e.message}"
    end

    def produced
      snapshot.reject { |path, mtime| @before[path] == mtime }.keys
    end

    def snapshot
      Dir.glob(File.join(@root, "**", "*{#{AUDIO.join(',')}}"))
         .reject { |p| p.match?(SKIP) }
         .each_with_object({}) { |p, acc| acc[p] = (File.mtime(p).to_f rescue nil) }
    end

    def manifest_for(path)
      {
        "schema" => SCHEMA,
        # The pins belong in the sentence that claims reproduction. Without them
        # it read "Reproduce with: RENDER_SEED=… ruby dilla.rb out.wav" over a
        # take rendered with fifteen knobs set, and RELEASE.mp3's own sidecar is
        # the proof that a confident note over an incomplete command gets
        # believed for months.
        "note" => "Reproduce with: #{reproduce_command}",
        "render_seed" => @seed,
        "seed_was" => @explicit ? "given" : "drawn and recorded",
        "command" => { "argv" => @argv, "cwd" => @root },
        "engine" => engine_identity,
        "environment" => recorded_env,
        # The knobs the OPERATOR set, as opposed to the ones a defaults table
        # filled in. This is the difference between a recipe and a transcript.
        "pinned" => pinned_env,
        # Knobs this run computed for itself. Not inputs; see derived_env.
        "derived" => derived_env,
        # A frozen render read the learned state and wrote none of it back, so
        # the take beside this manifest was made against state that has not
        # moved since. Worth recording: it is the difference between a take that
        # can be compared with another and one that cannot.
        "frozen" => (DillaFrozen.skips if DillaFrozen.on?),
        # Present only when something warned, so its presence is the flag: a
        # stage fell back or gave up, and the take may be missing a layer.
        "warnings" => warnings_record,
        # What this file was joined from, when it was joined rather than
        # rendered. A compilation gets both blocks: the environment describes
        # the run that produced its parts, `assembly` describes the parts.
        "assembly" => assemblies[path.to_s],
        "artifact" => artifact(path),
        "rendered_at" => @started_at&.utc&.iso8601,
      }.compact
    end

    def reproduce_command
      pins = pinned_env.map { |k, v| "#{k}=#{v}" }
      (["RENDER_SEED=#{@seed}"] + pins + ["ruby dilla.rb"] + @argv).join(" ")
    end

    # What the caller actually typed.
    #
    # `environment` records all 172 knobs the run ended up with, and replaying
    # that is not replaying the run: env_locks.rb distinguishes a value the
    # operator pinned from one a style table soft-filled, and soft fill only
    # wins when nothing set the key first. Feed the whole recorded environment
    # back in and every engine-chosen default arrives as an operator pin, so the
    # tables that would have chosen them are locked out and the replay diverges
    # from the take it claims to reproduce -- most visibly on tracks whose own
    # progression is supposed to overwrite the default.
    #
    # USER_PINNED_ENV is captured in dilla.rb before any require can mutate ENV,
    # which is exactly the set wanted here. Absent (provenance loaded on its own,
    # as the tests do) this records nothing rather than guessing.
    def pinned_env
      return {} unless Object.const_defined?(:USER_PINNED_ENV)

      keys = engine_env_keys
      Object.const_get(:USER_PINNED_ENV).select do |key, value|
        keys.include?(key) && !value.to_s.empty? &&
          !ENV_DENY.include?(key) && !TOOLCHAIN_ENV.include?(key) &&
          !key.match?(ENV_DENY_PATTERN) &&
          !DillaKnobs::ENGINE_WRITTEN.include?(key)
      end
    end

    # The knobs that change what comes out, derived from the engine rather than
    # listed by hand.
    #
    # The first version was a hand-kept allow-list of eleven names. v4 was
    # rendered with fifteen knobs set and the manifest recorded six of them --
    # PAD_VOL, GROOVE_FEEL, KICK_GAIN, ANALOG_CHAIN, SONITEX and RAP_VOCAL all
    # missing -- so the file said "reproduce with" above a command that would
    # not. A provenance record that is silently partial is worse than none,
    # because it is believed.
    #
    # So the set is whatever the engine actually reads: every ENV["X"] and
    # ENV.fetch("X" in dilla.rb and lib/. That cannot go stale against a new
    # knob, which a list maintained beside the code always does.
    #
    # It went stale anyway, against a moved knob rather than a new one. The glob
    # was `lib/*.rb`, one level deep, which was every file lib/ had until the
    # engine was split into lib/engine/ (c94fe8b00). After it, the scan found 126
    # of 610 knobs: PROGRESSION, SONITEX, RAP_VOCAL, ANALOG_CHAIN, PAD_VOL and
    # KICK_GAIN were all missing again — five of the six names in the paragraph
    # above, recorded there as the reason the hand-kept list was abandoned. The
    # manifests written between the split and this fix say "reproduce with" over
    # a command that will not.
    #
    # Recursing fixed that instance and left the cause: this file still had its
    # own opinion about which files the engine is, and so did four other places.
    # It reads DillaSources now, which is the only one. A directory move cannot
    # produce a third occurrence unless it defeats that file too, and that file
    # is what the tests point at.
    #
    # Deliberately not "every variable currently set": this file is written next
    # to audio that gets shared, and the environment holds credentials.
    ENV_READ = /ENV(?:\.fetch)?\[?\(?["']([A-Z][A-Z0-9_]{2,})["']/

    def engine_env_keys
      @engine_env_keys ||=
        DillaSources.all.flat_map { |f| File.read(f).scan(ENV_READ).flatten rescue [] }.uniq.freeze
    end

    # The engine reads HOME and PATH like any program does, and they are not
    # knobs. RENDER_SEED has its own field. The pattern is the safety net the
    # comment above promises: this file sits beside audio that gets shared, and
    # a manifest is a bad place to learn that an API key was in the environment.
    #
    # The toolchain names are here for the same reason and were found the same
    # way: BUNDLE_GEMFILE is read by lib/music_gems.rb, so it is a knob by this
    # module's definition and turned up in `pinned` next to BARS and SONITEX as
    # though someone had chosen it. It says which Gemfile the shell happened to
    # export, which is not part of how a beat was made.
    ENV_DENY = %w[
      HOME PATH PWD OLDPWD SHELL SHLVL TERM TMPDIR USER LOGNAME LANG LC_ALL
      EDITOR VISUAL DISPLAY SSH_AUTH_SOCK RENDER_SEED
      BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH GEM_HOME GEM_PATH
      RBENV_VERSION RUBYOPT RUBYLIB
      GROK_AGENT
    ].freeze

    # dilla's own switches, which decide whether a check runs rather than what
    # comes out of the render. They were reaching `pinned` because they are read
    # by the engine, which is the test for a knob and not the test for a pin.
    #
    # DILLA_ASSET_CHECK=0 skips the missing-input abort and DILLA_KNOB_CHECK=0
    # skips knob validation, so recording them as operator pins puts them in the
    # reproduce command — and replaying a take would turn off the two guards
    # that tell you the take cannot be reproduced. DILLA_QUIET only silences a
    # warn line, but it is the same kind of thing and belongs with them.
    #
    # Found because the suite sets all three, so provenance recorded the test
    # harness's plumbing as the operator's choices. That test passed alone and
    # failed in the suite, which is the shape of every leak like this.
    TOOLCHAIN_ENV = %w[
      DILLA_QUIET DILLA_ASSET_CHECK DILLA_KNOB_CHECK
    ].freeze
    ENV_DENY_PATTERN = /KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|COOKIE|SESSION/i

    def recorded_env
      recorded = engine_env_keys.each_with_object({}) do |key, acc|
        next if ENV_DENY.include?(key) || key.match?(ENV_DENY_PATTERN)
        # A knob the engine WRITES is an output of this render, not an input to
        # it. DILLA_RENDER_SEED is set by the drum_kit engine part from the seed that is
        # already recorded above, so replaying a manifest verbatim fed a result
        # back in as a cause. Recorded separately below, under a name that says
        # what it is.
        next if DillaKnobs::ENGINE_WRITTEN.include?(key)

        value = ENV[key]
        acc[key] = value unless value.nil? || value.empty?
      end
      recorded.merge(instrument_env)
    end

    # Which instrument played the pads, recorded even when unset. An unset knob
    # is left out of `environment`, and ANALOG_SYNTH is the one whose default
    # changed under old takes: soundfonts before d6ab8a0c8, oscillators after.
    # The engine owns the default (ANALOG_SYNTH_DEFAULT in dilla.rb); loaded on
    # its own, as the tests do, this records only what ENV says.
    def instrument_env
      value = ENV["ANALOG_SYNTH"].to_s
      value = Object.const_get(:ANALOG_SYNTH_DEFAULT) if value.empty? && Object.const_defined?(:ANALOG_SYNTH_DEFAULT)
      value.to_s.empty? ? {} : { "ANALOG_SYNTH" => value.to_s }
    end

    # What the run computed for itself. Kept because it is useful to see, and
    # kept out of `environment` because replaying it would be wrong.
    def derived_env
      DillaKnobs::ENGINE_WRITTEN.each_with_object({}) do |key, acc|
        value = ENV[key]
        acc[key] = value unless value.nil? || value.empty?
      end
    end

    # The engine root is lib/'s parent, and the pathspecs are relative to it. The
    # first version ran git from lib/ with `-- dilla.rb lib`, which matches
    # nothing from there: the commit came back null and, worse, `status
    # --porcelain` came back empty and was read as "clean". It reported a clean
    # working tree having failed to look at one, while dilla.rb was in fact
    # dirty. An unknown is recorded as null now, never as the good answer.
    def engine_root = File.expand_path("..", __dir__)

    def git(*args)
      out = IO.popen(["git", "-C", engine_root, *args], err: File::NULL, &:read)
      $CHILD_STATUS&.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def engine_identity
      sha = git("log", "-1", "--format=%H", "--", "dilla.rb", "lib")
      status = git("status", "--porcelain", "--", "dilla.rb", "lib")
      {
        "file" => "dilla.rb",
        "commit" => (sha unless sha.to_s.empty?),
        # A dirty engine means the commit alone will not rebuild this. nil means
        # git could not be asked, which is not the same as clean.
        "working_tree_clean" => status.nil? ? nil : status.empty?,
        "ruby" => RUBY_VERSION,
        # Every filter in a render is ffmpeg's and every General MIDI voice is
        # fluidsynth's, so the same seed and commit on another version of
        # either is a different render. The Mac and vm23 do not carry the same
        # builds. nil means the tool could not be asked, not that it is absent.
        "ffmpeg" => toolchain["ffmpeg"],
        "fluidsynth" => toolchain["fluidsynth"],
      }
    end

    # One process asks once: a render writes a manifest per file it produces.
    def toolchain
      @toolchain ||= {
        "ffmpeg" => tool_version(%w[ffmpeg -version], /ffmpeg version (\S+)/),
        "fluidsynth" => tool_version(%w[fluidsynth --version], /FluidSynth runtime version (\S+)/),
      }
    end

    def tool_version(argv, pattern)
      out = IO.popen(argv, err: File::NULL, &:read)
      out[pattern, 1] if $CHILD_STATUS&.success?
    rescue StandardError
      nil
    end

    # --- assembly ---------------------------------------------------------------
    #
    # A recipe per rendered file was never enough, because the files that matter
    # most are not rendered, they are assembled.
    #
    # RELEASE.mp3 is 44 minutes and its sidecar describes a 160-second render:
    # the same seed, the same command, one sixteenth of the artifact. Working out
    # what was actually in it took envelope fingerprinting of every audio file
    # still on disk against the master, and the answer was four identifiable
    # takes, fifteen minutes that matched nothing, and a 21-minute compilation
    # that was itself an assembly of about ten more. None of that was written
    # down anywhere, and most of the parts no longer exist -- renders are
    # gitignored and the seed rotates, so a part that is gone is gone.
    #
    # Which is why each part's own recipe is INLINED here rather than referenced.
    # A manifest that points at a sidecar beside a deleted wav records
    # nothing. Inlined, the assembly still says what every part was made from
    # after every part has been swept.
    ASSEMBLY_SCHEMA = "dilla.assembly.v1"

    def assemblies = @assemblies ||= {}

    # parts: the files joined, in order. how: a sentence about the join.
    def record_assembly!(output, parts:, how:)
      return if disabled?

      # Assemblies happen from commands that may never have called begin!.
      @root ||= Dir.pwd
      @argv ||= []
      @started_at ||= Time.now
      offset = 0.0
      described = parts.map do |part|
        seconds = duration_of(part)
        entry = {
          "path" => part.to_s.sub("#{@root}/", ""),
          "starts_at" => offset.round(3),
          "seconds" => seconds&.round(3),
          "bytes" => (File.size(part) if File.file?(part)),
          "sha256" => (Digest::SHA256.file(part).hexdigest if File.file?(part)),
          # The part's own recipe, copied in. See the note above.
          "recipe" => part_recipe(part),
        }.compact
        offset += seconds.to_f
        entry
      end

      assemblies[output.to_s] = {
        "schema" => ASSEMBLY_SCHEMA,
        "how" => how,
        "parts" => described.length,
        "seconds" => offset.round(3),
        "assembled_at" => Time.now.utc.iso8601,
        "from" => described,
      }
      write_manifest(output) if File.file?(output)
      assemblies[output.to_s]
    rescue StandardError => e
      # An assembly that succeeded must not be reported as failed because its
      # bookkeeping did not -- the same rule finish! follows.
      warn "provenance: assembly record failed: #{e.class}: #{e.message}"
      nil
    end

    # The sidecar for an audio file. One suffix, read and written: pub4 keeps no
    # fallback for a renamed file, so an old sidecar is renamed on disk instead.
    def manifest_path(audio)
      "#{audio}#{MANIFEST_EXT}"
    end

    def part_recipe(part)
      manifest = manifest_path(part)
      return unless File.file?(manifest)

      doc = JSON.parse(File.read(manifest))
      {
        "render_seed" => doc["render_seed"],
        "pinned" => doc["pinned"],
        "note" => doc["note"],
        "engine_commit" => doc.dig("engine", "commit"),
      }.compact
    rescue StandardError
      nil
    end

    def duration_of(path)
      return unless File.file?(path)

      out = ToolRun.capture3(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                              "-of", "default=nk=1:nw=1", path.to_s]).first
      value = out.to_s.strip.to_f
      value.positive? ? value : nil
    rescue StandardError
      nil
    end

    def artifact(path)
      {
        "path" => path.sub("#{@root}/", ""),
        "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end

    def write_manifest(path)
      File.write("#{path}#{MANIFEST_EXT}", JSON.pretty_generate(manifest_for(path)) + "\n")
    end

    # `dilla replay <file.provenance.json>` — prints the command that rebuilds it.
    #
    # From `pinned` when the manifest has one, because that is what the operator
    # typed and letting the engine choose the rest is what the original run did.
    # Manifests written before `pinned` existed only have `environment`, and for
    # those this falls back to it and says so -- an imperfect replay the reader
    # knows is imperfect beats a perfect-looking one that is not.
    def replay_command(manifest_path)
      doc = JSON.parse(File.read(manifest_path))
      pinned = doc["pinned"]
      source = pinned && !pinned.empty? ? pinned : doc["environment"]
      env = source.map { |k, v| "#{k}=#{v}" }
      command = (["RENDER_SEED=#{doc['render_seed']}"] + env + ["ruby dilla.rb"] + doc["command"]["argv"]).join(" ")
      return command if pinned

      "# no `pinned` in this manifest (written before it was recorded); every engine-chosen\n" \
      "# default below arrives as an operator pin, which is not how the take was rendered.\n#{command}"
    end
  end
end

# The vinyl level, following the ghost notes against the kicks.
module DillaMl
  module_function

  def groove_synced_vinyl(ghost_count, kick_count, base: 0.06)
    base = base.to_f
    return 0.0 if base <= 0.0
    g = ghost_count.to_f / [kick_count, 1].max
    # Honor low bases (e.g. VINYL=10 → ~0.018); do not force a 0.04 floor of hiss.
    lo = [base * 0.85, 0.008].max
    (base + g * 0.012).clamp(lo, 0.12).round(3)
  end
end

require "json"
require "digest"

# The inputs a render names, and whether they are still there.
#
# A recipe can name a sample that is not on this machine. RELEASE.mp3's sidecar
# names EXTERNAL_KIT=03-soulful-vintage, which is not in the repository at all --
# it lives in a git clone under ~/.cache that nothing records the identity of --
# and SAMPLE_LOOP as an absolute path into samples/, where 46 of the files are
# untracked. Neither fact is discoverable from the manifest, and a render that
# cannot find a named input does not stop: it falls back, substitutes, and
# produces a perfectly good beat that is not the one the recipe describes.
#
# Two halves, and they answer different questions:
#
#   missing_inputs did THIS run get what it asked for? Runs at startup, before
#                  a note is rendered, and refuses rather than substitutes.
#   verify         is the crate itself intact? Compares the recorded hashes
#                  against what is on disk, so a sample that was replaced,
#                  re-encoded or truncated is visible.
#
# The manifest is written by hand (`dilla assets record`) rather than on every
# render, because a manifest that updates itself records whatever happened
# instead of what was supposed to happen, and would have nothing to say the day
# a sample changes underneath a take.
module DillaAssets
  SCHEMA = "dilla.assets.v1"

  class << self
    def root = File.expand_path("..", __dir__)
    def manifest_path = File.join(root, "data", "assets.json")

    # The recorded crate, or nil when data/assets.json is there and is not JSON.
    # An absent manifest is a crate nobody recorded; an unreadable one is a
    # record that exists and says nothing, and verify has to tell the two apart,
    # or `dilla assets` checks zero fingerprints and exits 0 over a broken file.
    def manifest
      return { "assets" => {} } unless File.file?(manifest_path)

      JSON.parse(File.read(manifest_path))
    rescue JSON::ParserError => e
      warn "assets: #{manifest_path} is not readable JSON (#{e.message})"
      nil
    end

    # Everything a recipe can name and a render can quietly do without.
    #
    # Derived from the engine where it can be: the sample-loop rack knows its
    # own paths, and lib/ledger.rb knows which knobs are read as file paths. The
    # drum one-shots are the floor every kit falls back to, so they are named
    # here -- if those are gone, every render is wrong and nothing says so.
    # drums/fm/ is regenerated by generate_fm_drum_kit! and drums/custom/ is a
    # copy of an installed kit whose identity external_kit_cache records, so
    # neither is fingerprinted here.
    def tracked_paths
      paths = []
      if defined?(TRACK_SAMPLE_LOOPS_BUILTIN)
        paths += TRACK_SAMPLE_LOOPS_BUILTIN.values.filter_map { |entry| entry[:path] }
      end
      paths += Dir[File.join(root, "samples", "drums", "*.wav")]
      paths.select { |path| File.file?(path) }.uniq.sort
    end

    def fingerprint(path)
      {
        "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      }
    end

    def record!
      assets = tracked_paths.to_h { |path| [relative(path), fingerprint(path)] }
      payload = {
        "schema" => SCHEMA,
        "note" => "The inputs a recipe can name. `dilla assets` checks them; a mismatch means a take " \
                  "rendered from this crate cannot be rendered from it again.",
        "external_kit_cache" => external_kit_identity,
        "assets" => assets,
      }
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "#{JSON.pretty_generate(payload)}\n")
      payload
    end

    # missing: recorded and not on disk. changed: on disk and different.
    # unrecorded: on disk, tracked, and never written down. unreadable: the
    # manifest exists and could not be parsed, so nothing above was checked.
    def verify
      doc = manifest
      recorded = doc ? doc["assets"] || {} : {}
      missing = []
      changed = []
      recorded.each do |name, want|
        path = File.join(root, name)
        next missing << name unless File.file?(path)

        got = fingerprint(path)
        changed << "#{name} (#{describe_change(want, got)})" if got["sha256"] != want["sha256"]
      end
      unrecorded = tracked_paths.map { |p| relative(p) } - recorded.keys
      { missing:, changed:, unrecorded:, recorded: recorded.length, unreadable: doc.nil? }
    end

    # The comparison is on the hash, so the report has to name the hash.
    #
    # It used to print `#{want['bytes']} bytes → #{got['bytes']}` for a mismatch
    # it decided on sha256, and a re-encoded one-shot keeps its size: seven drum
    # samples report as "CHANGED samples/drums/ghost.wav (12426 bytes → 12426)",
    # which reads as a bug in the check rather than a difference in the file, and
    # a reader who does not believe the check stops running it.
    def describe_change(want, got)
      shas = "sha #{want['sha256'].to_s[0, 12]} → #{got['sha256'].to_s[0, 12]}"
      return "same #{got['bytes']} bytes, #{shas}" if want["bytes"] == got["bytes"]

      "#{want['bytes']} → #{got['bytes']} bytes, #{shas}"
    end

    # The external drum kits are a shallow git clone outside the repository, so
    # the only honest identity for them is that clone's commit. Absent, renders
    # fall back to the synthesized kit -- which sounds different, and said so
    # nowhere.
    def external_kit_cache = File.expand_path("~/.cache/dilla-samples/free-drum-samples")

    def external_kit_identity
      return { "present" => false } unless Dir.exist?(external_kit_cache)

      head = `git -C #{external_kit_cache.inspect} rev-parse HEAD 2>/dev/null`.strip
      kits = Dir[File.join(external_kit_cache, "drum-samples", "*")].map { |d| File.basename(d) }.sort
      { "present" => true, "commit" => (head unless head.empty?), "kits" => kits }
    end

    # What this run asked for, checked before it renders a note.
    #
    # Returns a list of sentences. Empty means every named input resolved.
    def missing_inputs(env = ENV)
      problems = []

      DillaKnobs.all.each do |name, knob|
        next unless knob.type == :path

        value = env[name].to_s
        next if value.empty? || DillaKnobs::TRUTHY.include?(value.downcase) || DillaKnobs::FALSY.include?(value.downcase)
        # Only values that are actually spelled as a file. A knob read as a path
        # at one site can still be given a slug -- SAMPLE_LOOP takes both.
        next unless value.include?("/") || value.match?(/\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i)
        next if File.exist?(value)

        problems << "#{name}=#{value} names a file that is not here"
      end

      kit = env["EXTERNAL_KIT"].to_s
      unless kit.empty?
        # A kit the engine builds from oneshots it already ships is never in the
        # download cache, and looking for it there refuses a render that would
        # have been correct. external_kit_resolvable? answers for both sources,
        # beside the installer whose branches it mirrors, so a third source is
        # one edit rather than two.
        unless external_kit_resolvable?(kit)
          problems << "EXTERNAL_KIT=#{kit} does not resolve — not in " \
                      "#{relative_home(external_kit_cache)}, and not a builtin kit whose " \
                      "oneshots are here; the render would fall back to the synthesized " \
                      "kit, which is a different sound"
        end
      end

      problems
    end

    private

    def relative(path) = path.sub("#{root}/", "")
    def relative_home(path) = path.sub(Dir.home, "~")
  end
end
