# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?

class TestLawContract < Minitest::Test
  def test_concurrent_law_loads_share_one_registry
    dir = File.expand_path("../law", __dir__)
    threads = 8.times.map { Thread.new { Law.load_all(dir) } }
    results = threads.map(&:value)

    assert_equal 1, results.map(&:object_id).uniq.size
    assert_operator results.first.size, :>, 100
    assert_equal results.first.keys.sort, Law.rules.keys.sort
  end

  def test_law_loader_restores_previous_registry_when_reload_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "probe.rb")
      File.write(path, <<~RUBY)
        Law.define(:LOAD_ROLLBACK_PROBE) do
          source "test"
          severity :info
          practice "stable"
          fix "keep it"
          bad "bad"
          good "good"
        end
      RUBY

      Law.load_all(dir)
      assert_equal "stable", Law.rules.fetch(:LOAD_ROLLBACK_PROBE).practice

      File.write(path, <<~RUBY)
        Law.define(:LOAD_ROLLBACK_PROBE) do
          source "test"
          severity :info
          practice "updated"
          fix "keep it"
          bad "bad"
          good "good"
        end
      RUBY

      Law.load_all(dir)
      assert_equal "updated", Law.rules.fetch(:LOAD_ROLLBACK_PROBE).practice

      File.write(path, <<~RUBY)
        Law.define(:LOAD_ROLLBACK_PROBE) do
          source "test"
          severity :info
          practice "broken"
          fix "keep it"
          bad "bad"
          good "good"
        end
        raise "broken law shard"
      RUBY

      assert_raises RuntimeError { Law.load_all(dir) }
      assert_equal "updated", Law.rules.fetch(:LOAD_ROLLBACK_PROBE).practice
    ensure
      Law.load_all(File.join(Master::ROOT, "law"))
    end
  end

  def test_contract_has_stable_machine_readable_shape
    data = JSON.parse(Law::Contract.render)

    assert_equal 1, data.fetch("contract_version")
    assert_match(/\A[0-9a-f]{64}\z/, data.fetch("law_digest"))
    assert_equal Law::Contract::PROTOCOL, data.fetch("protocol")
    assert data.fetch("law_policy").fetch("lifecycle").key?("states")
    assert_equal %w[inventory classify], data.fetch("transformation_policy").fetch("preflight")
    assert_operator data.fetch("laws").length, :>, 100
    assert data.fetch("laws").all? { |law| law.key?("id") && law.key?("severity") }
  end

  def test_full_contract_contains_enforcement_material
    data = JSON.parse(Law::Contract.render(full: true))
    rule = data.fetch("laws").find { |law| law["id"] == "FAIL_VISIBLY" }

    assert rule
    assert rule.key?("question")
    assert rule.key?("fix")
    assert rule.key?("bad")
    assert rule.key?("good")
  end

  def test_digest_covers_governing_transformation_policy
    original = Master.method(:law)
    before = Law::Contract.digest
    Master.define_singleton_method(:law) do |section, root: Master::ROOT|
      value = original.call(section, root:)
      section.to_s == "transformation_policy" ? value.merge("_probe" => "changed") : value
    end

    refute_equal before, Law::Contract.digest
  ensure
    Master.define_singleton_method(:law, original) if original
  end

  def test_digest_changes_with_the_executable_law_set
    first = Law::Contract.digest
    assert_equal first, JSON.parse(Law::Contract.render).fetch("law_digest")
  end
  def test_derived_index_is_complete_and_machine_readable
    rows = Law::Index.validate!
    assert_operator rows.length, :>, 100
    assert rows.all? { |row| row.key?("id") && row.key?("lifecycle") && row.key?("proof") }
    assert_operator rows.count { |row| row["principle_scope"] == "universal" }, :>, 0

    rendered = JSON.parse(Law::Index.render)
    assert_equal rows.length, rendered.fetch("rule_count")
    assert_equal rows.count { |row| row["principle_scope"] == "universal" }, rendered.fetch("universal_count")
  end

  def test_deterministic_law_proof_checks_each_declared_language
    rule = Law::Rule.new(
      id: :MULTI_LANGUAGE_PROOF,
      source: "test",
      severity: :warn,
      mode: :violation,
      languages: %i[ruby scss],
      scope: :file,
      principle_scope: :domain,
      lifecycle: :active,
      autofix: :review,
      path: nil,
      path_exclude: nil,
      absent: nil,
      detect: ->(text) { text.include?("FORBIDDEN") },
      ask: nil,
      practice: nil,
      fix: "remove it",
      bad: "/* FORBIDDEN */\n",
      good: "clean\n",
      reads_comments: false,
    )

    error = assert_raises(ArgumentError) { rule.prove! }

    assert_match(/fixture\.scss/, error.message)
  end

  def test_lifecycle_transitions_are_published_on_rule
    assert Law::Rule.const_defined?(:LIFECYCLE_TRANSITIONS, false)
    assert_equal %i[proposed proven active observed trusted advisory retired],
                 Law::Rule::LIFECYCLE_TRANSITIONS.keys
  end

  def test_lifecycle_transitions_are_closed
    rule = Law.rules.fetch(:VERIFICATION_REQUIRED_FOR_COMPLETION)
    assert_equal :trusted, rule.lifecycle
    assert rule.can_transition_to?(:advisory)
    assert rule.can_transition_to?(:retired)
    assert rule.can_transition_to?(:active)
    refute rule.can_transition_to?(:proposed)

    candidate = rule.with(lifecycle: :active)
    assert candidate.can_transition_to?(:observed)
    refute candidate.can_transition_to?(:trusted)

    observed = candidate.with(lifecycle: :observed)
    assert observed.can_transition_to?(:trusted)
  end

end
