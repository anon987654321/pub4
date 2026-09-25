# frozen_string_literal: true

require_relative "test_helper"
require "set"
require "unwrap_error"

DATA = File.expand_path("../data", __dir__)

YAML_SPECS = {
  "attention_context.yml"        => { required_keys: %w[protocol fields rendering when_to_emit], arrays: [] },
  "patterns.yml"                 => { required_keys: %w[infer prompt_archaeology repo_topics], arrays: [] },
  # zsh, injection and refusal_templates moved to rules.yml: they are law, and
  # patterns.yml is the register for what is not. The guarantee moved with them.
  "rules.yml"                    => { required_keys: %w[zsh injection refusal_templates laws rules], arrays: [] },
}.freeze

PATTERNS_NAMESPACES = {
  "infer"              => %w[commands],
  "prompt_archaeology" => %w[policy clusters orchestration_blueprint risk_tiers],
  "repo_topics"        => %w[clusters],
}.freeze

DELETED_FILES = %w[
  infer_patterns.yml prompt_archaeology_patterns.yml repo_topic_clusters.yml
  workflow.yml standing_orders.yml ruby_style.yml injection_patterns.yml zsh.yml
  sweep_prompts.yml zsh_patterns.yml council_patterns.yml
].freeze

# The bed is dilla's: voice.yml keeps the level under the voice and points at
# the declaration dilla renders from, so the bed tests read that file.
module BedDeclaration
  def bed_declaration
    pointer = Master::Voice::Policy.bed
    return unless pointer && pointer["source"]

    file = File.expand_path("../../#{pointer["source"]}", __dir__)
    File.file?(file) ? YAML.load_file(file, aliases: true) : nil
  end
end

class TestYamlRegistries < Minitest::Test
  YAML_SPECS.each do |filename, spec|
    define_method(:"test_#{filename.tr('.', '_')}_parses") do
      path = File.join(DATA, filename)
      assert File.exist?(path), "#{filename} missing"
      data = Master.load_yaml(path)
      assert_kind_of Hash, data, "#{filename} root must be a Hash"
    end

    define_method(:"test_#{filename.tr('.', '_')}_required_keys") do
      data = Master.load_yaml(File.join(DATA, filename))
      spec[:required_keys].each do |key|
        assert data.key?(key), "#{filename} missing top-level key: #{key}"
      end
    end

    define_method(:"test_#{filename.tr('.', '_')}_arrays_non_empty") do
      data = Master.load_yaml(File.join(DATA, filename))
      spec[:arrays].each do |key|
        next unless data.key?(key)
        val = data[key]
        assert val.is_a?(Array) && val.any?, "#{filename}[#{key}] must be a non-empty array"
      end
    end
  end
end

class TestPatternsNamespaces < Minitest::Test
  PATTERNS_NAMESPACES.each do |namespace, inner_keys|
    define_method(:"test_patterns_#{namespace}_namespace_populated") do
      data = Master.load_yaml(File.join(DATA, "patterns.yml"))
      ns = data[namespace]
      assert_kind_of Hash, ns, "patterns.yml[#{namespace}] must be a Hash"
      inner_keys.each do |key|
        assert ns.key?(key), "patterns.yml[#{namespace}] missing key: #{key}"
      end
    end
  end
end

class TestDeletedFilesAbsent < Minitest::Test
  DELETED_FILES.each do |filename|
    define_method(:"test_#{filename.tr('.', '_')}_removed") do
      refute File.exist?(File.join(DATA, filename)),
             "#{filename} should be removed — content merged into patterns.yml"
    end
  end
end

class TestRulesYamlRegistry < Minitest::Test
  include BedDeclaration
  REQUIRED_RULE_FIELDS = %w[id name tier severity autofix].freeze

  def test_rules_yml_has_no_duplicate_rule_ids
    ids = rules.map { |rule| rule["id"] }.compact
    duplicates = ids.tally.select { |_, count| count > 1 }.keys

    assert duplicates.empty?, "rules.yml has duplicate rule ids: #{duplicates.join(', ')}"
  end

  def test_rules_yml_entries_have_required_fields
    missing = rules.filter_map do |rule|
      absent = REQUIRED_RULE_FIELDS.reject { |field| rule.key?(field) }
      "#{rule['id'] || '<missing id>'}: #{absent.join(', ')}" if absent.any?
    end

    assert missing.empty?, "rules.yml entries missing required fields: #{missing.join('; ')}"
  end

  def test_failure_taxonomy_retry_contract
    taxonomy = data.fetch("failure_taxonomy")

    assert_operator taxonomy.dig("transient", "max_retries"), :<=, 3
    assert_equal "exponential_backoff", taxonomy.dig("transient", "strategy")
    assert_equal 0, taxonomy.dig("permanent", "max_retries")
    assert_equal "fail_fast", taxonomy.dig("permanent", "strategy")
  end

  def test_phantom_recovery_contract
    recovery = data.fetch("phantom_recovery")

    assert_match %r{\A/\^}, recovery.dig("detectors", "gaslighting_preamble")
    assert recovery.fetch("recovery").any? { |step| step.include?("discard last response") }
    assert recovery.fetch("recovery").any? { |step| step.include?("publish phantom:detected") }
  end

  def test_soul_golden_rule_maps_to_kernel_preserve_rule
    soul = Master.load_yaml(File.join(DATA, "soul.yml"))
    preserve_rule = rules.find { |rule| rule["id"] == "PRESERVE_FIRST" }

    assert_equal "PRESERVE_THEN_IMPROVE_NEVER_BREAK", soul.dig("absolute", "golden_rule")
    assert_equal "kernel", preserve_rule.fetch("tier")
    # The wording lives in law/, not in soul or rules.yml. This asserted soul.absolute.rules
    # still carried it, which test_soul.rb asserts soul must not — one of the
    # two had to be reading the tree as it is.
    refute soul.dig("absolute", "rules"), "soul must not hold rules; law/ is the registry"
    law_dir = File.expand_path("../law", __dir__)
    require File.join(law_dir, "law")
    ::Law.load_all(law_dir) if ::Law.rules.empty?
    assert_match(/never rewrite working code/i, ::Law.rules.fetch(:PRESERVE_FIRST).practice)
    assert_match(/Preserve behavior and intent/, ::Law.rules.fetch(:PRESERVE_FIRST).fix)
  end

  def test_patterns_do_not_reference_unknown_rules_yml_ids
    rule_ids = rules.map { |rule| rule.fetch("id") }.to_set
    referenced = rule_reference_values(patterns).flat_map { |value| value.scan(/\b[A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+\b/) }.uniq
    unknown = referenced.reject { |id| rule_ids.include?(id) }

    assert unknown.empty?, "patterns.yml references unknown rules.yml ids: #{unknown.join(', ')}"
  end

  def test_voice_yml_declares_language_specific_voices
    tts = Master.load_yaml(File.join(DATA, "voice.yml")).fetch("tts")
    assert_equal "jenny", tts.fetch("language_voices").fetch("en")
    assert_equal "pernille", tts.fetch("language_voices").fetch("nb")
    assert_equal "jenny", tts.fetch("single_voice")
  end

  def test_voice_yml_loads_strunk
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    strunk = voice.dig("voice", "strunk")
    assert strunk, "voice.yml must define voice.strunk"
  end

# A rotation is additive: single_voice stays the contract, every name in the
# list has to be a voice the synthesiser knows, and an absent or single-entry
# rotation must leave the one-voice behaviour exactly as it was. The last
# clause is the one worth holding — it is what lets this be reverted by
# deleting four lines of YAML.
# A chain nothing applies is a declaration with no reader, which is this
# tree's most-recorded defect — so this holds that Speech reaches for it, not
# merely that voice.yml contains it.
def test_the_post_chain_is_read_and_applied
  chain = Master::Voice::Policy.post_chain
  refute_nil chain, "voice.yml declares no post_chain"
  assert_equal chain, Master::Voice::Policy.browser_payload[:post_chain],
               "the face shapes from browser_payload; it must carry the same chain"

  ran = shape_with_recorded_ffmpeg
  assert_equal ["-af", chain], ran[:argv][ran[:argv].index("-af"), 2], "Speech never applies the chain"
  assert ran[:result].end_with?("_shaped.mp3"), "Speech kept the unshaped file"

  # No per-file normalisation: the chain runs once per utterance, and loudnorm
  # levelled every sentence to the same loudness (measured: two clips 20 dB
  # apart both left it at -3.9 LUFS).
  refute_includes chain, "loudnorm", "a per-utterance chain must not normalise per file"
  assert_operator chain.index("volume="), :<, chain.index("alimiter"),
                  "the gain must come before the limiter"
end

# Speech.shaped over a scratch mp3, with ffmpeg replaced by a recorder that
# writes the output it was asked for.
def shape_with_recorded_ffmpeg
  exec = Master::Io::Exec
  original = exec.method(:capture3)
  argv = nil
  exec.define_singleton_method(:capture3) do |*args, **|
    argv = args
    File.write(args.last, "shaped")
    ["", "", Struct.new(:success?).new(true)]
  end
  Dir.mktmpdir do |dir|
    clip = File.join(dir, "utterance.mp3")
    File.write(clip, "raw")
    result = Master::Voice::Speech.shaped(clip)
    { argv:, result: }
  end
ensure
  exec.define_singleton_method(:capture3, original) if original
end

  # The bed is declared here and rendered by whoever plays it, so what this can
  # hold is the shape of the declaration: that it points at dillas table rather
  # than copying it, that every chord has a patch to reach for, and that the
  # drums are not routed through the pad chain.
  def test_the_bed_reads_dillas_progression_table
    pointer = Master::Voice::Policy.bed
    skip "no bed declared" unless pointer

    assert_operator pointer["gain_db"].to_i, :<, 0, "the bed must sit under the voice"
    bed = bed_declaration
    assert bed, "voice.yml names #{pointer["source"]}, which is not a bed declaration"
    assert_equal "artist_verified", bed["progressions"],
                 "the theory half of the table sounds like an exercise under speech"
    dilla = File.join(File.dirname(File.expand_path("../../#{pointer["source"]}", __dir__), 2), "dilla.rb")
    assert_match(/^module Bed$/, File.read(dilla), "dilla renders the bed; #{dilla} holds no module Bed")
  end

  # One instrument per progression, and more than one instrument per pass. A
  # band does not change keyboards every chord, and one timbre all pass is
  # wallpaper. Every oscillator family keeps presets to move between, and no
  # preset detunes past five cents, where a chord stops reading as chorus and
  # starts reading as out of tune.
  def test_every_bed_family_has_an_instrument_to_play
    bed = bed_declaration
    skip "no bed declared" unless bed

    families = bed["families"] || {}
    assert_operator families.size, :>=, 3, "one family all pass is one instrument playing one long piece"
    patches = Array(bed["patches"])
    assert_equal patches.size, patches.map { |patch| patch["name"] }.uniq.size, "two patches share a name"
    families.each do |name, spec|
      assert_equal "oscillator", spec["source"], "#{name}: dilla synthesises every sound it plays"
      next unless spec["source"] == "oscillator" || spec["struck"]

      assert_operator patches.count { |patch| patch["family"] == name }, :>=, 2,
                      "#{name}: a family with one preset cannot move inside itself"
    end
    patches.each do |patch|
      assert_includes %w[saw square pulse triangle sine fm_bell fm_wood fm_glass], patch["wave"],
                      "#{patch["name"]}: unknown oscillator"
      assert_operator patch["cutoff"].to_i, :>, 0, "#{patch["name"]}: no ladder cutoff"
      assert Array(patch["detune_cents"]).all? { |cents| cents.to_f.abs <= 5.0 },
             "#{patch["name"]}: detune past five cents reads as out of tune"
    end
  end

  # The voicing rules a render can undo without anyone hearing the edit: the
  # upper structure inside two octaves, and the harmonic rhythm carried by the
  # transcription itself, one length per chord.
  def test_the_bed_voices_chords_the_way_a_player_does
    bed = bed_declaration
    skip "no bed declared" unless bed

    voicing = bed["voicing"] || {}
    assert_operator voicing["max_span"].to_i, :<=, 24, "a spread past two octaves is a synth patch, not a hand"
    assert_operator voicing["drop_fifth_from"].to_i, :>=, 5, "the fifth goes only where a ninth needs its room"
    assert bed["bars_per_chord"], "the rows carry their rhythm as repetition; a meter laid over them scrambles it"
    assert_nil bed["meter"], "a meter over the transcriptions rewrites their harmonic rhythm"
  end

  # The bed is measured, not guessed: a loudness target every pass is set to, a
  # true-peak ceiling under which nothing clips between samples, and a reference
  # curve of nine bands that `bed.rb --check` compares against.
  def test_the_bed_is_measured_against_a_record
    bed = bed_declaration
    skip "no bed declared" unless bed

    assert_operator bed.dig("loudness", "true_peak_db").to_f, :<=, -1.0, "a sample-peak limiter still clips between samples"
    bands = Array(bed["reference_bands"])
    assert_equal 9, bands.size, "nine octave bands, sub to top"
    assert_equal 0.0, bands.first.to_f, "the curve is relative to its own sub, so level cannot confuse it"
  end

  # The bed exists to sit under talking, so it moves for the talking.
  def test_the_bed_gets_out_of_the_voices_way
    bed = bed_declaration
    skip "no bed declared" unless bed

    speech = bed["speech"] || {}
    assert_operator speech["duck_db"].to_f, :<, 0, "a bed that does not move for a sentence competes with it"
    assert_includes 2000..4000, speech.dig("carve", "hz").to_i, "speech intelligibility lives between 2 and 4 kHz"
    assert_operator speech["release_ms"].to_i, :>, speech["attack_ms"].to_i,
                    "fast in, slow out, or the bed swells back between words"
  end

# Dilla time is a juxtaposition, not a wobble: some elements rigid on the
# grid while others are pulled off it. Two ways to lose it  swing everything,
# or swing nothing  and both read as "fixed the drums" in a diff.
def test_the_bed_drums_keep_conflicting_time_feels
  bed = bed_declaration
  skip "no bed declared" unless bed
  drums = bed["drums"]
  skip "no drums declared" unless drums

  feels = drums["feels"]
  assert_equal 0.0, feels.dig("hat", "swing").to_f,
               "the hats are the rigid reference; swing them and there is no friction"
  assert_operator feels.dig("kick", "swing").to_f, :>, 0, "the kick carries the swing"
  assert_operator feels.dig("snare", "shift").to_f, :<, 0, "the snare is rushed, not laid back"
  assert_operator feels.dig("kick", "shift").to_f, :>, 0, "the kick lags"
  assert_equal "sonitex_sp1200", drums["finish"],
               "the kit is finished on dillas sampler, not left raw"
end

  # The bed is a band now, and the two relationships that make it one are the
  # ones an edit breaks silently: the bass reading the kicks own placement, and
  # the harmony ducking under the kit. Lose either and it is two records played
  # at once.
  def test_the_bed_is_locked_to_its_drummer
    bed = bed_declaration
    skip "no bed declared" unless bed

    assert_equal "samples/drums", bed.dig("drums", "crate"),
                 "a drum is a recording; you cannot filter your way to one from a sine"
    assert bed.dig("drums", "samples", "kick"), "the kit must name its files"
    assert_equal "bar_shape", bed.dig("lead", "rhythm_from"),
                 "Ringtone Tools decouple rhythm from pitch; the rhythm is the bars"
    assert_equal "chord_bag", bed.dig("lead", "pitch_from"),
                 "the lead reads the chord back and cannot play outside it"
    assert bed.dig("sidechain", "pads"), "the pads must duck under the kick"
    assert_equal "sonitex_sp1200", bed.dig("drums", "finish"),
                 "the kit is finished on dillas sampler, not left as a synthesiser"
  end

  # The grids are dillas, read from its own MIDI library rather than guessed
  # at from a description of how Dilla programmed. Its own import-midi reads
  # the same directory, so the path is a contract between two readers.
  def test_the_bed_reads_dillas_grid_library
    bed = bed_declaration
    skip "no bed declared" unless bed

    assert_equal "samples/midi", bed.dig("drums", "grids"),
                 "dillas export-midi and import-midi are built around this directory"
    banks = bed.dig("drums", "grid_banks")
    assert_operator banks.keys.size, :>=, 3, "one bank is one pocket all session"
    assert banks["dilla"], "the bank the whole bed is named for"
  end

  # A shape holds for a block of whole phrases before the next bank takes over,
  # and every bank the order names is one the grid library declares.
  def test_the_bed_arrangement_holds_its_groove
    bed = bed_declaration
    skip "no bed declared" unless bed

    arrangement = bed.dig("drums", "arrangement") || {}
    bars = arrangement["bars_per_shape"].to_i
    assert_operator bars, :>=, 4, "re-rolling the shape every bar sounds busy and reads as indecision"
    assert_equal 0, bars % 4, "a block that ends mid-phrase breaks the groove where nobody chose to"
    banks = (bed.dig("drums", "grid_banks") || {}).keys
    Array(arrangement["bank_order"]).each do |bank|
      assert_includes banks, bank, "the arrangement names a bank the grid library does not declare"
    end
  end

  # A synthesis bug that was audible before it was visible, and the spectrogram
  # named it. It is not a preference, so it is pinned.
  def test_the_bed_does_not_alias
    bed = bed_declaration
    skip "no bed declared" unless bed

    assert_operator bed["oversample"].to_i, :>=, 2,
                    "a modulo saw has a vertical edge; at 1x its harmonics fold back as bleeps"
  end

  def test_voice_rotation_is_additive
    tts = Master.load_yaml(File.join(DATA, "voice.yml"))["tts"] || {}
    rotation = Array(tts["rotation"])

    rotation.each do |name|
      assert Master::Voice::Speech::VOICES.key?(name.to_sym),
             "voice.yml rotation names #{name}, which Speech::VOICES does not have"
    end

    if rotation.size > 1
      assert Master::Voice::Policy.rotating?
      assert_includes rotation.map(&:to_sym), Master::Voice::Policy.voice_for_utterance
      assert_includes rotation, tts["single_voice"],
                      "single_voice must be one of the voices actually spoken"
    else
      refute Master::Voice::Policy.rotating?
      assert_equal Master::Voice::Policy.single_voice_key,
                   Master::Voice::Policy.voice_for_utterance
    end

    assert_equal rotation.map(&:to_s), Master::Voice::Policy.browser_payload[:rotation],
                 "the face rotates from browser_payload; it must carry the same list"
  end

  def test_the_face_resolves_voice_names_from_the_servers_table
    voices = Master::Voice::Policy.browser_payload.fetch(:voices)

    Master::Voice::Speech::VOICES.each do |name, neural|
      next if name.to_s.end_with?("Neural")

      assert_equal neural, voices.fetch(name.to_s), "the face cannot resolve #{name}, which the server speaks"
    end
    refute(voices.keys.any? { |name| name.end_with?("Neural") }, "the aliases are short names only")
    face = File.read(File.expand_path("../web/public/face.part1.txt", __dir__))
    refute_match(/christopher:\s*'en-US-ChristopherNeural'/, face,
                 "a second name table in the face is the drift this payload replaced")
  end

  def test_voice_yml_tts_policy_single_voice
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    tts = voice["tts"] || {}
    # No voice name is asserted here. This test was left behind by a voice.yml
    # change three times, in both directions, shipping MASTER's suite red on
    # origin/main each time — a check measuring a spelling while the behaviour
    # it stood for was right. data/voice.yml is the operator's decision and owns
    # the name; what a test can hold is that every reader agrees with it, which
    # is what the assertions below do and what actually broke each time.
    assert_equal true, tts["persona_affects_text_only"]
    assert_equal tts["single_voice"].to_sym, Master::Voice::Policy.single_voice_key
    assert_equal tts["neural"], Master::Voice::Policy.neural_voice
    # The pair has to agree: single_voice is what Ruby hands the synthesizer,
    # neural is what the browser reads, and they drifted apart once already.
    assert_equal tts["neural"], Master::Voice::Speech::VOICES.fetch(tts["single_voice"].to_sym)
    assert_equal Master::Voice::Policy::FALLBACK["single_voice"], tts["single_voice"]
    assert_equal Master::Voice::Policy::FALLBACK["neural"], tts["neural"]
  end

  def test_standing_order_voice_directives_match_rules_voice_strunk
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    strunk = voice.dig("voice", "strunk") || data.dig("voice", "strunk")
    orders = Master.load_yaml(Master.state_path)
    autocommit = orders.find { |order| order["name"] == "autocommit_post_chat" }

    assert_includes strunk.fetch("apply_to"), "prose"
    assert_match(/Strunk-style/, autocommit.fetch("description"))
    assert_includes strunk.fetch("hedges"), "will"
  end

  private

  def rules
    Master.flatten_rules(merged_rules.fetch("rules", {}))
  end

  def data
    @data ||= Master.load_yaml(File.join(DATA, "rules.yml"))
  end

  def merged_rules
    @merged_rules ||= Master.load_rules(root: File.expand_path("..", __dir__))
  end

  def patterns
    @patterns ||= Master.load_yaml(File.join(DATA, "patterns.yml"))
  end

  def rule_reference_values(object)
    case object
    when Hash
      object.flat_map do |key, value|
        key.to_s == "rule" || key.to_s == "rules" ? Array(value).map(&:to_s) : rule_reference_values(value)
      end
    when Array
      object.flat_map { |value| rule_reference_values(value) }
    else
      []
    end
  end
end

class TestPhantomRecoveryRuntime < Minitest::Test
  EventBus = Struct.new(:events) do
    def publish(name, payload)
      events << [name, payload]
    end
  end

  def setup
    Master::PhantomRecovery.remove_instance_variable(:@detectors) if Master::PhantomRecovery.instance_variable_defined?(:@detectors)
  end

  def test_gaslighting_preamble_discards_response_and_publishes_event
    bus = EventBus.new([])
    result = Master::PhantomRecovery.detect("Sure, I can handle that.", bus:)

    assert_includes result.fetch(:patterns), "gaslighting_preamble"
    assert result.fetch(:recovery).any? { |step| step.include?("discard last response") }
    assert_equal "phantom:detected", bus.events.fetch(0).fetch(0)
  end
end

class TestClusterConsistency < Minitest::Test
  def test_patterns_repo_topics_no_duplicate_ids
    data  = Master.load_yaml(File.join(DATA, "patterns.yml"))
    items = Array(data.dig("repo_topics", "clusters"))
    ids   = items.map { |c| c["id"] || c["name"] }.compact
    dups  = ids.tally.select { |_, n| n > 1 }.keys
    assert dups.empty?, "patterns.yml[repo_topics][clusters] has duplicate ids: #{dups.join(', ')}"
  end

  def test_patterns_prompt_archaeology_no_duplicate_ids
    data  = Master.load_yaml(File.join(DATA, "patterns.yml"))
    items = Array(data.dig("prompt_archaeology", "clusters"))
    ids   = items.map { |c| c["id"] || c["name"] }.compact
    dups  = ids.tally.select { |_, n| n > 1 }.keys
    assert dups.empty?, "patterns.yml[prompt_archaeology][clusters] has duplicate ids: #{dups.join(', ')}"
  end
end

class TestConstitutionYamlLoading < Minitest::Test
  include BedDeclaration
  ALLOWED_DIRECT_LOADS = %w[
    lib/master.rb
    spec/static_syntax_spec.rb
  ].freeze

  def test_data_yml_runtime_readers_use_master_loader
    files = Dir.glob(File.join(Master::ROOT, "{bin,lib,test}/**/*.{rb,rake}"))
    offenders = files.flat_map do |path|
      rel = path.delete_prefix("#{Master::ROOT}/")
      next [] if ALLOWED_DIRECT_LOADS.include?(rel)

      File.readlines(path, chomp: true).filter_map.with_index(1) do |line, line_no|
        next unless line.match?(/YAML\.(?:safe_)?load_file/)
        next unless line.match?(/Master\.data_path|Master::DATA|File\.join\([^)]*\bDATA\b|File\.join\([^)]*"data"/)

        "#{rel}:#{line_no}"
      end
    end

    assert_empty offenders, "constitutional YAML must load through Master.load_yaml: #{offenders.join(', ')}"
  end
# The tilt is the one thing here that was measured rather than chosen, and
# both facts about it are load-bearing: where it sits in the chain, and that
# only part of the delta is applied.
def test_the_bed_tilt_sits_after_the_compressor
  bed = bed_declaration
  skip "no bed declared" unless bed
  tilt = bed["tilt"]
  skip "no tilt declared" unless tilt

  assert_equal "after_compressor", tilt["position"],
               "a compressors makeup gain simply puts a cut midrange back"
  assert_operator tilt["applied_fraction"].to_f, :<, 1.0,
                  "a full correction chases the reference into its own arrangement"
  assert_operator Array(tilt["bells"]).size, :>=, 5, "a tilt is a curve, not a bell"
end

# A synth is silent between the notes and a record never is.
def test_the_bed_carries_surface_noise
  bed = bed_declaration
  skip "no bed declared" unless bed

  assert bed["dust"], "the imperfection is the sound, not a garnish on it"
  assert_operator bed.dig("dust", "hiss_db").to_i, :<, -20,
                  "audible hiss is a fault; inaudible hiss is the absence of digital silence"
  assert_in_delta 1.8, bed.dig("dust", "rotation_s").to_f, 0.05,
                  "a record's crackle comes round once a turn, and a turn at 33 rpm is 1.8 s"
end

end
