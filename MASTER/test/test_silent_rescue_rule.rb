# frozen_string_literal: true

require_relative "test_helper"

Master::Judge::Scan::RuleDSL # trigger autoload → rule files registered

# SILENT_RESCUE (:error) flags blanket rescues that discard the error.
# NARROW_SILENT_RESCUE (:warning) flags narrow-class rescues that do the same.
# Both are RuleDSL rules — anonymous Rule subclasses found via the registry by id.
class TestSilentRescueRule < Minitest::Test
  def setup
    reg     = Master::Judge::Scan::Rule.registry
    @silent = reg.find { |k| k.new.id == "silent_rescue" }&.new
    @narrow = reg.find { |k| k.new.id == "narrow_silent_rescue" }&.new
    refute_nil @silent, "SILENT_RESCUE must be registered"
    refute_nil @narrow, "NARROW_SILENT_RESCUE must be registered"
  end

  # --- SILENT_RESCUE: blanket rescues -----------------------------------------

  def test_flags_blanket_rescue_returning_nil
    code = <<~RUBY
      def risky
        do_work
      rescue StandardError
        nil
      end
    RUBY
    findings = @silent.check(code, path: "x.rb")
    refute_empty findings
    assert_equal :error, findings.first[:severity]
  end

  def test_flags_bare_rescue_with_discard_body
    code = "def f\n  go\nrescue\n  nil\nend\n"
    refute_empty @silent.check(code, path: "x.rb")
  end

  def test_flags_inline_blanket_discard
    code = "def f\n  go\nrescue StandardError; nil\nend\n"
    refute_empty @silent.check(code, path: "x.rb")
  end

  def test_flags_blanket_rescue_binding_unused_error
    code = <<~RUBY
      def f
        go
      rescue StandardError => _e
        []
      end
    RUBY
    refute_empty @silent.check(code, path: "x.rb")
  end

  # --- SILENT_RESCUE: things it must NOT flag ---------------------------------

  def test_ignores_blanket_rescue_that_logs
    code = <<~RUBY
      def f
        go
      rescue StandardError => e
        warn e.message
      end
    RUBY
    assert_empty @silent.check(code, path: "x.rb")
  end

  def test_ignores_blanket_rescue_that_reraises
    code = "def f\n  go\nrescue StandardError\n  raise\nend\n"
    assert_empty @silent.check(code, path: "x.rb")
  end

  def test_ignores_blanket_rescue_with_meaningful_return
    code = <<~RUBY
      def f
        go
      rescue StandardError
        default_value
      end
    RUBY
    assert_empty @silent.check(code, path: "x.rb")
  end

  def test_silent_rescue_does_not_flag_narrow_class
    code = "def f\n  go\nrescue JSON::ParserError\n  nil\nend\n"
    assert_empty @silent.check(code, path: "x.rb"),
                 "narrow-class rescue belongs to NARROW_SILENT_RESCUE, not SILENT_RESCUE"
  end

  # --- NARROW_SILENT_RESCUE: narrow-class rescues -----------------------------

  def test_narrow_flags_specific_class_discard
    code = "def f\n  go\nrescue JSON::ParserError\n  nil\nend\n"
    findings = @narrow.check(code, path: "x.rb")
    refute_empty findings
    assert_equal :warning, findings.first[:severity]
  end

  def test_narrow_ignores_blanket_rescue
    code = "def f\n  go\nrescue StandardError\n  nil\nend\n"
    assert_empty @narrow.check(code, path: "x.rb"),
                 "blanket rescue belongs to SILENT_RESCUE, not NARROW_SILENT_RESCUE"
  end

  def test_narrow_ignores_handled_specific_class
    code = <<~RUBY
      def f
        go
      rescue JSON::ParserError => e
        warn e.message
      end
    RUBY
    assert_empty @narrow.check(code, path: "x.rb")
  end

  # --- both rules skip the rule definitions themselves ------------------------

  def test_both_rules_skip_rule_source_files
    code = "def f\n  go\nrescue StandardError\n  nil\nend\n"
    assert_empty @silent.check(code, path: "lib/judge/scan/rules/lexical_rules.rb")
    assert_empty @narrow.check(code, path: "lib/judge/scan/rules/lexical_rules.rb")
  end
end
