# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"

# Semantic interpretation is universal. Language declarations govern
# deterministic/AST adapter reach, not whether an invariant may be considered
# when reading a complete artifact as prose, source, or structured text.
class TestSemanticLawScope < Minitest::Test
  def rule = @rule ||= Master::Review::Scan::Laws::SemanticLaw.new(agent: nil)

  def scoped(language) = rule.send(:laws_for, language).keys

  def test_missing_model_agent_is_inconclusive_not_clean
    semantic = Master::Review::Scan::Laws::SemanticLaw.new(agent: nil)

    error = assert_raises(RuntimeError) { semantic.check("def foo; end", path: "foo.rb") }
    assert_match(/INCONCLUSIVE.*no model agent configured/, error.message)
  end

  def test_provider_configuration_failure_is_inconclusive_not_clean
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      raise "missing configuration: API key"
    end
    semantic = Master::Review::Scan::Laws::SemanticLaw.new(agent:)

    error = assert_raises(RuntimeError) { semantic.check("def foo; end", path: "foo.rb") }
    assert_match(/INCONCLUSIVE.*provider capability/, error.message)
  end

  def test_an_unexpected_model_failure_is_not_reported_as_clean
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, operation:| raise "upstream exploded" }
    rule = Master::Review::Scan::Laws::SemanticLaw.new(agent:)

    assert_raises(RuntimeError) { rule.check("def foo; end", path: "foo.rb") }
  end

  def test_virtual_files_with_equal_lengths_do_not_share_semantic_cache_entries
    calls = 0
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      calls += 1
      operation == :scan_semantic_opportunities ? "NONE" : "CLEAN"
    end
    rule = Master::Review::Scan::Laws::SemanticLaw.new(agent:)

    rule.check("x = 1\n", path: "virtual.rb")
    rule.check("y = 2\n", path: "virtual.rb")

    assert_equal 4, calls
  end

  def test_violation_and_opportunity_assessments_use_separate_calls_and_verdicts
    observations = []
    agent = Object.new
    agent.define_singleton_method(:ask) do |prompt, operation:|
      observations << [operation, prompt]
      if operation == :scan_semantic_violations
        "RAILS_THIN_CONTROLLER_SEMANTIC:2:unhandled breach\n"
      else
        "RAILS_THIN_CONTROLLER_SEMANTIC:3:possible simplification\n"
      end
    end
    semantic = Master::Review::Scan::Laws::SemanticLaw.new(agent:)
    findings = semantic.check("class PostsController; end\n", path: "posts_controller.rb")

    assert_equal %i[scan_semantic_violations scan_semantic_opportunities], observations.map(&:first)
    assert_includes observations[0][1], "SEMANTIC VIOLATIONS"
    assert_includes observations[1][1], "SEMANTIC OPPORTUNITIES"
    assert_equal [:violation, :opportunity], findings.map { |finding| finding[:tags].last }
    assert_equal [2, 3], findings.map { |finding| finding[:line] }
  end

  def test_all_semantic_laws_are_available_for_every_language
    %w[ruby css markdown html javascript yaml zsh json scss].each do |language|
      assert_includes scoped(language), "RAILS_THIN_CONTROLLER_SEMANTIC", language
      assert_includes scoped(language), "AESTHETIC_FLAT_SEMANTIC", language
    end
  end

  # The counterweight. Most rules declare no language and the scope must leave
  # them alone; a filter that dropped them would silently retire the corpus.
  def test_a_rule_declaring_no_language_reaches_every_language
    unscoped = rule.send(:load_semantic_laws).select { |_, a| a[:languages].empty? }
    refute_empty unscoped, "most of the corpus declares no language"

    %w[ruby css markdown html javascript yaml zsh json scss].each do |language|
      assert_empty unscoped.keys - scoped(language), "#{language} lost an unscoped rule"
    end
  end

  def test_semantic_findings_from_any_active_law_are_retained
    laws = rule.send(:laws_for, "css")
    response = "RAILS_THIN_CONTROLLER_SEMANTIC:3:controller cohesion\nAESTHETIC_FLAT_SEMANTIC:4:gradient coherence\n"
    ids = rule.send(:parse_findings, response, laws).map { |finding| finding[:law] }

    assert_equal %w[RAILS_THIN_CONTROLLER_SEMANTIC AESTHETIC_FLAT_SEMANTIC], ids
  end

  def test_prompt_frame_is_language_independent
    ruby = rule.send(:prompt_frame_for, rule.send(:laws_for, "ruby"), "ruby")
    css = rule.send(:prompt_frame_for, rule.send(:laws_for, "css"), "css")

    assert_equal ruby, css
    assert_includes ruby, "RAILS_THIN_CONTROLLER_SEMANTIC"
    assert_includes ruby, "AESTHETIC_FLAT_SEMANTIC"
  end

  def test_malformed_or_unrequested_law_output_is_inconclusive
    laws = rule.send(:laws_for, "css")
    error = assert_raises(RuntimeError) do
      rule.send(:parse_findings, "UNKNOWN_LAW:1:hallucinated finding\n", laws)
    end

    assert_match(/INCONCLUSIVE.*unrequested Law/, error.message)
  end

  # The invariant Law::Rule#prove! already enforces on the law population, asked
  # of the other one. NEVER_BATCH_DELETE declared `shell` and could read no file
  # for it; laws.yml carried `rails`, `prose` and `erb` across 13 rows for the
  # same reason — nothing emits them, and while the key was unread nothing said
  # so. Now that it is read, a phantom language aims a rule at no file at all.
  def test_semantic_population_matches_the_canonical_law_catalogue
    catalogue = Master.law("law_catalogue").fetch("entries").keys.map(&:upcase).sort
    assessed = rule.send(:load_semantic_laws).keys.sort

    assert_equal catalogue, assessed
    assert_includes assessed, "RUBOCOP", "class-based detectors must not be omitted from semantic review"
    assert_includes assessed, "INTERCONNECT", "non-DSL detector classes must not be omitted"
  end

  def test_no_declared_language_is_one_no_file_can_carry
    known = Master::FILE_LANGUAGE_MAP.values.uniq
    declared = Master.law_entries(root: Master::ROOT)
                     .flat_map { |r| Array(r["languages"]).map { |l| [r["id"], l.to_s] } }
    phantom = declared.reject { |(_, language)| known.include?(language) }

    assert_empty phantom.map { |id, language| "#{id} declares #{language}" },
                 "FILE_LANGUAGE_MAP emits #{known.join(', ')} and nothing else"
  end
end
