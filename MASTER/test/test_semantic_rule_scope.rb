# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# `languages:` on a semantic rule was inert. SemanticRule.from_yaml kept prompt,
# severity, mode, reversibility and blast_radius and dropped the rest, so a rule
# declaring `css` was asked about every file and the declaration cost tokens
# without buying a scope. Its only reader had been the lexical bridge, which
# carries no rules now.
#
# Both halves are pinned here: the scope is honoured, and a rule that declares
# nothing still reaches everything — narrowing this into a rule that only ever
# asks about a handful of files would be worse than the inert key.
class TestSemanticRuleScope < Minitest::Test
  def rule = @rule ||= Master::Review::Scan::Rules::SemanticRule.new(agent: nil)

  def scoped(language) = rule.send(:rules_for, language).keys

  def test_a_ruby_rule_is_not_asked_about_a_stylesheet
    assert_includes scoped("ruby"), "RAILS_THIN_CONTROLLER_SEMANTIC"
    refute_includes scoped("css"), "RAILS_THIN_CONTROLLER_SEMANTIC"
  end

  def test_a_stylesheet_rule_is_not_asked_about_ruby
    assert_includes scoped("css"), "AESTHETIC_FLAT_SEMANTIC"
    refute_includes scoped("ruby"), "AESTHETIC_FLAT_SEMANTIC"
  end

  # The counterweight. Most rules declare no language and the scope must leave
  # them alone; a filter that dropped them would silently retire the corpus.
  def test_a_rule_declaring_no_language_reaches_every_language
    unscoped = rule.send(:load_semantic_rules).select { |_, a| a[:languages].empty? }
    refute_empty unscoped, "most of the corpus declares no language"

    %w[ruby css markdown html javascript yaml zsh json scss].each do |language|
      assert_empty unscoped.keys - scoped(language), "#{language} lost an unscoped rule"
    end
  end

  # A model handed the css frame that answers with a ruby rule has invented one
  # for this file. Accepting it would put the scope back where it was.
  def test_a_finding_outside_the_scope_asked_is_discarded
    css = rule.send(:rules_for, "css")
    response = "RAILS_THIN_CONTROLLER_SEMANTIC:3:fat controller\nAESTHETIC_FLAT_SEMANTIC:4:gradient\n"
    ids = rule.send(:parse_findings, response, css).map { |f| f[:rule] }

    assert_equal ["AESTHETIC_FLAT_SEMANTIC"], ids
  end

  def test_the_prompt_frame_differs_by_language
    ruby = rule.send(:prompt_frame_for, rule.send(:rules_for, "ruby"), "ruby")
    css = rule.send(:prompt_frame_for, rule.send(:rules_for, "css"), "css")

    assert_includes ruby, "RAILS_THIN_CONTROLLER_SEMANTIC"
    refute_includes css, "RAILS_THIN_CONTROLLER_SEMANTIC"
  end

  # The invariant Law::Rule#prove! already enforces on the law population, asked
  # of the other one. NEVER_BATCH_DELETE declared `shell` and could read no file
  # for it; rules.yml carried `rails`, `prose` and `erb` across 13 rows for the
  # same reason — nothing emits them, and while the key was unread nothing said
  # so. Now that it is read, a phantom language aims a rule at no file at all.
  def test_no_declared_language_is_one_no_file_can_carry
    known = Master::FILE_LANGUAGE_MAP.values.uniq
    declared = Master.flatten_rules(Master.load_rules(root: Master::ROOT).fetch("rules", {}))
                     .flat_map { |r| Array(r["languages"]).map { |l| [r["id"], l.to_s] } }
    phantom = declared.reject { |(_, language)| known.include?(language) }

    assert_empty phantom.map { |id, language| "#{id} declares #{language}" },
                 "FILE_LANGUAGE_MAP emits #{known.join(', ')} and nothing else"
  end
end
