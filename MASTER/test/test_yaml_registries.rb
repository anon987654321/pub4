# frozen_string_literal: true

require_relative "test_helper"
require "set"
require "unwrap_error"

DATA = File.expand_path("../data", __dir__)

YAML_SPECS = {
  "attention_context.yml"        => { required_keys: %w[protocol fields rendering when_to_emit], arrays: [] },
  "patterns.yml"                 => { required_keys: %w[gh openbsd zsh infer prompt_archaeology repo_topics], arrays: [] },
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

class TestRulesYamlRegistry < Minitest::Test
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
    assert_match(/Preserve behavior and intent/, preserve_rule.fetch("fix"))
    # The wording lives in law/, not in soul. This asserted soul.absolute.rules
    # still carried it, which test_soul.rb asserts soul must not — one of the
    # two had to be reading the tree as it is.
    refute soul.dig("absolute", "rules"), "soul must not hold rules; law/ is the registry"
    law_dir = File.expand_path("../law", __dir__)
    require File.join(law_dir, "law")
    ::Law.load_all(law_dir) if ::Law.rules.empty?
    assert_match(/never rewrite working code/i, ::Law.rules.fetch(:PRESERVE_FIRST).practice)
  end

  def test_patterns_do_not_reference_unknown_rules_yml_ids
    rule_ids = rules.map { |rule| rule.fetch("id") }.to_set
    referenced = rule_reference_values(patterns).flat_map { |value| value.scan(/\b[A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+\b/) }.uniq
    unknown = referenced.reject { |id| rule_ids.include?(id) }

    assert unknown.empty?, "patterns.yml references unknown rules.yml ids: #{unknown.join(', ')}"
  end

  def test_voice_yml_loads_strunk
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    strunk = voice.dig("voice", "strunk")
    assert strunk, "voice.yml must define voice.strunk"
  end

  def test_voice_yml_tts_policy_single_voice
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    tts = voice["tts"] || {}
    # Osman since 2026-08-13 (operator decision), replacing the Pernille of
    # 08-11, which had replaced the Osman of 08-10, which replaced the US English
    # of 08-04. ms-MY-OsmanNeural is a Malay voice reading English text — the
    # accent comes from the voice, which is why soul.yml keeps
    # language.primary: english and moves only dialect, to malaysian.
    #
    # This assertion has now been left behind by a voice.yml change twice, in
    # both directions, shipping MASTER's suite red on origin/main each time. The
    # data is the decision; the test follows it. The three structural assertions
    # below are the ones worth having — they hold whatever the name is.
    assert_equal "osman", tts["single_voice"]
    assert_equal "ms-MY-OsmanNeural", tts["neural"]
    assert_equal true, tts["persona_affects_text_only"]
    assert_equal :osman, Master::Voice::Policy.single_voice_key
    assert_equal "ms-MY-OsmanNeural", Master::Voice::Policy.neural_voice
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
  ALLOWED_DIRECT_LOADS = %w[
    lib/master.rb
    spec/smoke/static_syntax_spec.rb
  ].freeze

  def test_data_yml_runtime_readers_use_master_loader
    files = Dir.glob(File.join(Master::ROOT, "{bin,lib,test,spec}/**/*.{rb,rake}"))
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
