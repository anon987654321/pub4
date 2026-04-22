# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "yaml"
require "json"

# Invariant tests that guard properties no self-modification may violate.
# These run without LLM keys and protect the system's own foundations.
class TestSelfRefactorSafety < Minitest::Test
  def test_all_lib_files_parse
    # Batch all files into a single ruby -c invocation for speed
    files = MASTER.source_files
    _out, err, status = Open3.capture3("ruby", "-c", *files)
    assert status.success?, "Syntax errors found:\n#{err}"
  end

  def test_axiom_count_never_decreases
    axioms = load_axioms
    # axioms.yml had 68 entries as of the axiom expansion; use >= floor
    assert axioms.size >= 68,
      "Axiom count dropped to #{axioms.size}, expected >= 68"
  end

  def test_golden_rule_exists
    constitution = load_constitution
    assert_equal "PRESERVE_THEN_IMPROVE_NEVER_BREAK", constitution["golden_rule"],
      "golden_rule missing or changed in constitution.yml"
  end

  def test_no_file_exceeds_hard_limit
    max_lines = 500
    # Pre-existing files that exceeded the limit before this guard was added.
    # They should be refactored but are not blocked by this test.
    known_exceptions = %w[lib/commands.rb lib/commands/code_commands.rb].map { |f| File.join(MASTER.root, f) }
    MASTER.source_files.each do |file|
      next if known_exceptions.include?(file)

      count = File.readlines(file).size
      assert count <= max_lines,
        "#{relative(file)} is #{count} lines (limit: #{max_lines})"
    end
  end

  def test_result_monad_contract_intact
    ok = MASTER::Result.ok("hello")
    assert ok.ok?
    refute ok.err?
    assert_equal "hello", ok.value

    err = MASTER::Result.err("boom")
    assert err.err?
    refute err.ok?
    assert_equal "boom", err.failure
  end

  def test_constitution_has_protection_levels
    constitution = load_constitution
    levels = constitution.fetch("protection_levels", {})
    %w[ABSOLUTE PROTECTED NEGOTIABLE FLEXIBLE].each do |level|
      assert levels.key?(level),
        "protection_levels missing #{level} in constitution.yml"
    end
  end

  def test_deferred_debt_file_is_valid_jsonl
    path = File.join(MASTER.root, "data", "deferred_debt.jsonl")
    return unless File.exist?(path)

    required_keys = %w[axiom_id file line reason_deferred blocking_axiom timestamp]
    File.readlines(path).each_with_index do |line, idx|
      next if line.strip.empty?

      entry = JSON.parse(line)
      required_keys.each do |key|
        assert entry.key?(key),
          "deferred_debt.jsonl line #{idx + 1} missing key: #{key}"
      end
    end
  end

  def test_absolute_axioms_exist
    axioms = load_axioms
    absolutes = axioms.select { |a| a["protection"] == "ABSOLUTE" }
    ids = absolutes.map { |a| a["id"] }

    assert_includes ids, "PRESERVE_FIRST"
    assert_includes ids, "SELF_APPLY"
  end

  private

  def load_axioms
    path = File.join(MASTER.root, "data", "axioms.yml")
    YAML.safe_load_file(path) || []
  end

  def load_constitution
    path = File.join(MASTER.root, "data", "constitution.yml")
    YAML.safe_load_file(path) || {}
  end

  def relative(path)
    path.sub("#{MASTER.root}/", "")
  end

  def assert_silent_syntax(file)
    result = system("ruby", "-c", file, out: File::NULL, err: File::NULL)
    assert result, "Syntax error in #{relative(file)}"
  end
end
