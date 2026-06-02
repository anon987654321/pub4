# frozen_string_literal: true

require_relative "test_helper"
require "judge/scan/rule_dsl"
require "judge/scan/rules/structural_rules"

class TestScanRuleContracts < Minitest::Test
  Rules = Master::Judge::Scan::Rules

  def test_small_files_rule_flags_files_over_limit
    code = Array.new(Rules::SmallFilesRule::LIMIT + 1, "puts :x").join("\n")

    assert_finding Rules::SmallFilesRule.new, code, "large.rb", "file"
  end

  def test_small_functions_rule_flags_long_methods
    body = Array.new(Rules::SmallFunctionsRule::MAX + 1, "  puts :x").join("\n")
    code = "def oversized\n#{body}\nend\n"

    assert_finding Rules::SmallFunctionsRule.new, code, "large_method.rb", "method oversized"
  end

  def test_god_class_rule_flags_many_public_methods
    methods = (1..(Rules::GodClassRule::METHOD_LIMIT + 1)).map { |i| "  def m#{i}; end" }.join("\n")
    code = "class TooMuch\n#{methods}\nend\n"

    assert_finding Rules::GodClassRule.new, code, "god.rb", "god class TooMuch"
  end

  def test_cqs_rule_flags_mutation_plus_return
    code = <<~RUBY
      def update_and_read
        @value = 1
        return @value
      end
    RUBY

    assert_finding Rules::CqsRule.new, code, "cqs.rb", "mutates state and returns"
  end

  def test_secret_proximity_rule_flags_hardcoded_secret
    assert_finding rule("SECRET_PROXIMITY"), 'api_key = "123456789"', "app.rb", "hardcoded credential"
  end

  def test_magic_color_rule_flags_raw_css_color
    assert_finding rule("MAGIC_COLOR", path: "app.css"), ".x { color: #ff00aa; }", "app.css", "raw hex color"
  end

  def test_unbounded_retry_rule_flags_uncapped_retry
    assert_finding rule("UNBOUNDED_RETRY"), "begin\n  call\nrescue\n  retry\nend\n", "retry.rb", "unbounded retry"
  end

  def test_strict_mode_zsh_rule_flags_missing_set_e
    assert_finding rule("STRICT_MODE_ZSH"), "#!/usr/bin/env zsh\necho ok\n", "script.zsh", "missing set"
  end

  def test_keyword_args_rule_flags_three_positionals
    assert_finding rule("KEYWORD_ARGS"), "def call(a, b, c)\nend\n", "args.rb", "positional args"
  end

  def test_dead_code_rule_flags_unreachable_statement
    assert_finding rule("DEAD_CODE"), "def call\n  return :ok\n  puts :never\nend\n", "dead.rb", "unreachable code"
  end

  def test_trailing_commas_rule_flags_missing_final_comma
    code = "ITEMS = [\n  \"one\",\n  \"two\"\n]\n"

    assert_finding rule("TRAILING_COMMAS"), code, "items.rb", "missing trailing comma"
  end

  private

  def rule(id, path: nil)
    candidates = Master::Judge::Scan::Rule.registry.filter_map do |klass|
      instance = klass.new
      instance if instance.id == id
    rescue ArgumentError
      nil
    end
    candidates.first || flunk("missing rule #{id}")
  end

  def assert_finding(rule, code, path, message)
    findings = rule.check(code, path:)

    refute_empty findings
    assert findings.any? { |finding| finding[:message].include?(message) },
      "expected #{rule.id} finding containing #{message.inspect}, got #{findings.inspect}"
  end
end
