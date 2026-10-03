# frozen_string_literal: true

require "prism"
require_relative "test_helper"

class TestVanguardProtocol < Minitest::Test
  include Master

  def test_command_guard_rejects_banned_tokens
    assert_raises(Master::SecurityError) do
      Review::Security::CommandGuard.validate_command!(["grep", "-R", "foo", "."])
    end
  end

  def test_command_guard_secure_execute_returns_result
    result = Review::Security::CommandGuard.secure_execute(%w[echo ok])
    assert result.ok?
    assert_includes result.value!, "ok"
  end

  def test_autonomous_repairer_heals_trailing_whitespace
    path = File.join(Dir.mktmpdir, "sample.rb")
    File.write(path, "def ok\n  1\nend  \n")
    result = Review::Scan::AutonomousRepairer.heal(path:, source: File.read(path))
    assert result.ok?
    refute_includes result.value!, "  \n"
  end

  def test_runtime_loop_guards_allow_non_falcon_context
    assert Ops::RuntimeLoopGuards.guard_subprocess_context!
  end

  # Rule.inherited registers every subclass, and the builder instantiates every
  # auto-built one, so without the opt-out this fixture joins every scan the
  # process runs afterwards and fails each file it is handed.
  class ExplodingAstRule < Review::Scan::Rule
    declare id: "exploding_ast", severity: :error

    def self.auto_build? = false

    def check_ast(_ast, _code, path:)
      raise "fixture AST failure at #{path}"
    end
  end

  def test_ast_rule_failure_is_not_clean
    rule = ExplodingAstRule.new
    error = assert_raises(RuntimeError) do
      rule.check("class Broken", path: "broken.rb")
    end
    assert_match(/exploding_ast AST check failed/, error.message)
  end

  def test_symbol_visitor_tracks_metrics
    source = <<~RUBY
      module Demo
        class Widget
          def ping = true
        end
      end
    RUBY
    ast = Prism.parse(source).value
    visitor = Review::CodeIndex::SymbolVisitor.new(file: "demo.rb", root: Dir.pwd)
    ast.accept(visitor)
    assert_equal 1, visitor.metrics[:modules]
    assert_equal 1, visitor.metrics[:classes]
    assert_equal 1, visitor.metrics[:defs]
  end
end
