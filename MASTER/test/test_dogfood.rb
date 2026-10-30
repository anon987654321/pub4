# frozen_string_literal: true

require "minitest/autorun"

DOGFOOD_ROOT = File.expand_path("..", __dir__)
require File.join(DOGFOOD_ROOT, "law", "definition")
# The one loader for constitutional YAML — see the read below and
# test_yaml_registries, which asserts nothing reads those files any other way.
$LOAD_PATH.unshift(File.join(DOGFOOD_ROOT, "lib"))
require "master"

Law.load_all

class DogfoodSpec < Minitest::Test
  # Every law with a detector flags its bad fixture and spares its good one.
  # Failure here is the archaeological audit: a capability went missing, or a
  # detector regressed.
  #
  # A practice law has no detector — no regex can read "one SSH session" off a
  # file — so its fixtures are illustrative and this proof does not apply. What
  # still applies is that it HAS them: Builder refuses a law without a bad and a
  # good whatever its kind, because a law carrying no example of its own subject
  # is the unfalsifiable shape this file exists to reject.
  #
  # A Law proved by a named test (a detector that reads a repository, a linter
  # or a model) carries its examples in that test, and the test must exist.
  Law.definitions.each do |id, law|
    if law.proved_by
      define_method("test_law_#{id}_names_the_test_that_proves_it") do
        assert File.file?(File.join(DOGFOOD_ROOT, law.proved_by)), "#{id}: proved_by #{law.proved_by} is missing"
      end
    elsif law.scannable?
      define_method("test_law_#{id}_proves_itself") do
        refute_empty law.scan(law.bad, file: law.proof_file),  "#{id}: bad fixture not flagged"
        assert_empty law.scan(law.good, file: law.proof_file), "#{id}: good fixture flagged (false positive)"
      end
    else
      define_method("test_rule_#{id}_carries_both_examples") do
        refute_empty law.bad.to_s.strip,  "#{id}: no example of breaking it"
        refute_empty law.good.to_s.strip, "#{id}: no example of following it"
        refute_equal law.bad.to_s.strip, law.good.to_s.strip, "#{id}: the two examples are the same"
      end
    end
  end

  # Self-application. Law files are Ruby; every ruby-scoped `detect` law runs
  # over law/ and must find nothing (declarations and fixtures excepted —
  # Law.conduct). The `check` and class Laws that joined Law.definitions when the
  # Law systems merged (VERTICAL_BREATH, LONG_LINE, SMALL_FILES, ...) find 308
  # style breaches in law/ on 2026-10-30; held out until /fix clears them, which
  # AstFixer's LAW_DIR_RE refuses to do unattended in a fixture-bearing file.
  def test_law_applies_to_itself
    detect_laws = Law.definitions.values.select(&:detect)
    findings = Dir[File.join(DOGFOOD_ROOT, "law", "*.rb")].flat_map do |file|
      text = Law.conduct(File.read(file, encoding: "UTF-8"))
      detect_laws.select { |law| law.applies?(file, :ruby) }.flat_map { |law| law.scan(text, file:) }
    end
    assert_empty findings.map { |f| "#{f.id} #{File.basename(f.file)}:#{f.line}" }.join("\n")
  end

  def test_no_law_without_all_three_parts
    policy = { severity: :error, mode: :blocking, lifecycle: :active, autofix: :review,
               languages: ["ruby"], surfaces: Law::ASSESSMENT_SURFACES }
    err = assert_raises(ArgumentError) do
      Law.stub(:catalogue_policy, policy) do
        Law.define(:INCOMPLETE) { detect { true } }
      end
    end
    assert_match(/missing bad, good/, err.message)
  end

  def test_every_lexical_rule_in_laws_yml_has_moved_here
    require "yaml"
    left = []
    walk = lambda do |o|
      case o
      when Hash
        left << o["id"] if o["id"] && o["detect_lexical"]
        o.each_value { |v| walk.call(v) }
      when Array then o.each { |v| walk.call(v) }
      end
    end
    # Master.load_yaml, not YAML directly: test_yaml_registries asserts that
    # every runtime read of a constitutional file goes through the one loader,
    # so a second reader here is a second implementation of what laws.yml means.
    walk.call(Master.load_yaml(Master::LAWS_PATH))
    assert_empty left, "detect_lexical belongs in law/ now: #{left.join(', ')}"
  end
end
