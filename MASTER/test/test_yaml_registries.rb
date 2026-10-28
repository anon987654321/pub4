# frozen_string_literal: true

require_relative "test_helper"
require "set"
require "unwrap_error"

DATA = File.expand_path("../data", __dir__)

YAML_SPECS = {
  "attention_context.yml"        => { required_keys: %w[protocol fields rendering when_to_emit], arrays: [] },
  "patterns.yml"                 => { required_keys: %w[infer prompt_archaeology repo_topics], arrays: [] },
  # zsh, injection and refusal_templates moved to laws.yml: they are law, and
  # patterns.yml is the register for what is not. The guarantee moved with them.
  "laws.yml"                    => { required_keys: %w[transformation_policy architecture plugins runtime_policy self_test veto_patterns anti_patterns law_deps], arrays: [] },
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

class TestLawsYamlRegistry < Minitest::Test
  REQUIRED_LAW_FIELDS = %w[id priority statement].freeze

  def test_laws_yml_has_no_duplicate_rule_ids
    ids = rules.map { |rule| rule["id"] }.compact
    duplicates = ids.tally.select { |_, count| count > 1 }.keys

    assert duplicates.empty?, "laws.yml has duplicate rule ids: #{duplicates.join(', ')}"
  end

  def test_laws_yml_entries_have_required_fields
    missing = rules.filter_map do |rule|
      absent = REQUIRED_LAW_FIELDS.reject { |field| rule.key?(field) }
      "#{rule['id'] || '<missing id>'}: #{absent.join(', ')}" if absent.any?
    end

    assert missing.empty?, "laws.yml entries missing required fields: #{missing.join('; ')}"
  end

  def test_phantom_recovery_contract
    recovery = data.fetch("phantom_recovery")

    assert_match %r{\A/\^}, recovery.dig("detectors", "gaslighting_preamble")
    assert recovery.fetch("recovery").any? { |step| step.include?("discard last response") }
    assert recovery.fetch("recovery").any? { |step| step.include?("publish phantom:detected") }
  end

  def test_soul_golden_law_maps_to_kernel_preserve_rule
    soul = Master.load_yaml(File.join(DATA, "soul.yml"))
    assert_equal "PRESERVE_THEN_IMPROVE_NEVER_BREAK", soul.dig("absolute", "golden_law")
    # The wording lives in law/, not in soul or laws.yml. This asserted soul.absolute.rules
    # still carried it, which test_soul.rb asserts soul must not — one of the
    # two had to be reading the tree as it is.
    refute soul.dig("absolute", "rules"), "soul must not hold rules; law/ is the registry"
    law_dir = File.expand_path("../law", __dir__)
    require File.join(law_dir, "definition")
    ::Law.load_all(law_dir) if ::Law.definitions.empty?
    preserve_rule = ::Law.definitions.fetch(:PRESERVE_FIRST)
    assert_equal :error, preserve_rule.severity
    assert_match(/never rewrite working code/i, preserve_rule.practice)
    assert_match(/preserve behavior/i, preserve_rule.fix)
  end

  def test_patterns_do_not_reference_unknown_rules_yml_ids
    rule_ids = executable_law_ids.to_set
    referenced = rule_reference_values(patterns).flat_map { |value| value.scan(/\b[A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+\b/) }.uniq
    unknown = referenced.reject { |id| rule_ids.include?(id) }

    assert unknown.empty?, "patterns.yml references unknown laws.yml ids: #{unknown.join(', ')}"
  end

  def test_voice_yml_declares_language_specific_voices
    tts = Master.load_yaml(File.join(DATA, "voice.yml")).fetch("tts")
    assert_equal "christopher", tts.fetch("language_voices").fetch("en")
    assert_equal "pernille", tts.fetch("language_voices").fetch("nb")
    assert_equal "christopher", tts.fetch("single_voice")
  end

  def test_english_tts_never_selects_the_retired_second_voice
    tts = Master.load_yaml(File.join(DATA, "voice.yml")).fetch("tts")

    refute tts.fetch("language_voice_families").key?("en")
    refute_includes tts.fetch("rotation"), "jenny"
    refute Master::Voice::Speech::VOICES.key?(:jenny)
    assert_equal :christopher, Master::Voice::Speech.resolve_voice("en-US-JennyNeural")
    assert_equal :christopher, Master::Voice::Policy.voice_for_language(:en, gender: "female")
  end

  def test_voice_yml_loads_strunk
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    strunk = voice.dig("voice", "strunk")
    assert strunk, "voice.yml must define voice.strunk"
  end

  # A chain nothing applies is a declaration with no reader, which is this
  # tree's most-recorded defect — so this holds that Speech reaches for it, not
  # merely that voice.yml contains it.
  def test_the_post_chain_is_read_and_applied
    chain = Master::Voice::Policy.post_chain
    refute_nil chain, "voice.yml declares no post_chain"
    assert_equal chain, Master::Voice::Policy.browser_payload[:post_chain],
                 "the face shapes from browser_payload; it must carry the same chain"

    ran = shape_with_recorded_ffmpeg
    assert_equal ["-af", Master::Voice::Policy.shaped_chain], ran[:argv][ran[:argv].index("-af"), 2],
                 "Speech never applies the chain (post_chain plus the room)"
    assert ran[:argv][ran[:argv].index("-af") + 1].start_with?(chain)
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

  # A rotation is additive: single_voice stays the contract, every name in the
  # list has to be a voice the synthesiser knows, and an absent or single-entry
  # rotation must leave the one-voice behaviour exactly as it was. The last
  # clause is the one worth holding — it is what lets this be reverted by
  # deleting four lines of YAML.
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
    face = File.read(File.expand_path("../../RAILS/master/public/face.part1.txt", __dir__))
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
    assert_includes strunk.fetch("hedges").fetch("en"), "will"
    assert_includes strunk.fetch("hedges").fetch("nb"), "kanskje"
  end

  private

  def rules
    Master.law_entries(root: File.expand_path("..", __dir__))
  end

  def executable_law_ids
    law_dir = File.expand_path("../law", __dir__)
    require File.join(law_dir, "definition")
    ::Law.load_all(law_dir) if ::Law.definitions.empty?
    ::Law.definitions.keys.map(&:to_s)
  end

  def data
    @data ||= Master.load_yaml(File.join(DATA, "laws.yml"))
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
  # These run without booting Master: the commit-msg hook, the standalone
  # ratchet instrument, a test file that requires nothing but minitest, and the
  # two readers bin/operator loads bare (`affiliate`, the inter-model measure).
  ALLOWED_DIRECT_LOADS = %w[
    lib/master.rb
    spec/static_syntax_spec.rb
    lib/ground/commit_format.rb
    lib/ground/agent_brief.rb # deliberately unbooted SessionStart reader
    lib/operator/ratchets.rb
    test/test_future_face.rb
    test/test_cli_face_contract.rb # standalone; boots no Master to load through
    lib/finance/tradedoubler.rb
    lib/review/council/inter_model_contract.rb
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
end

class TestLawsPhysicalOrder < Minitest::Test
  # Root-key order is a reading contract: constitutional laws first, operational
  # flow next, then adapters/topology, the derived map, and the separate browser
  # authority boundary. Tokens live in tokens.yml and must not re-enter this file.
  ORDER = %w[
    CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
    PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES INTER_MODEL_CONTRACT languages markdown_style visual_identity_contract
    prose zsh detection_calibration phantom_recovery transformation_policy self_test veto_patterns anti_patterns
    architecture runtime_policy law_deps plugins law_ratchets law_map browser_policy
    face_ascii personal_privacy law_catalogue
  ].freeze
  TRANSFORMATION_ORDER = %w[
    remove defragment flatten decouple split hoist merge relocate rename reorder
    reflow simplify recommend
  ].freeze

  def test_laws_follow_constitutional_reading_order
    data = Master.load_yaml(File.join(DATA, "laws.yml"))
    assert_equal ORDER, data.keys.reject { |key| key == "schema" }
  end

  def test_transformation_flow_matches_its_implementation_contract
    policy = Master.load_yaml(File.join(DATA, "laws.yml")).fetch("transformation_policy")

    assert_equal %w[inventory classify], policy.fetch("preflight")
    assert_equal TRANSFORMATION_ORDER, policy.fetch("order")
    assert_equal TRANSFORMATION_ORDER, policy.fetch("operations").keys
    assert_equal ["prove"], policy.fetch("postflight")
    %w[semantic_meaning public_contracts reference_graph side_effect_order rendered_output].each do |invariant|
      assert_includes %w[required required_when_applicable], policy.fetch("preservation").fetch(invariant),
                   "transformation flow must preserve #{invariant}"
    end
  end
end
