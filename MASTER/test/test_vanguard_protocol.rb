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
    result = Review::Security::CommandGuard.secure_execute(["echo", "ok"])
    assert result.ok?
    assert_includes result.value!, "ok"
  end

  def test_autonomous_repairer_heals_trailing_whitespace
    path = File.join(Dir.mktmpdir, "sample.rb")
    File.write(path, "def ok\n  1\nend  \n")
    result = Review::Scan::AutonomousRepairer.heal(path: path, source: File.read(path))
    assert result.ok?
    refute_includes result.value!, "  \n"
  end

  def test_runtime_loop_guards_allow_non_falcon_context
    assert Ops::RuntimeLoopGuards.guard_subprocess_context!
  end

  def test_git_hooks_skip_without_git_dir
    result = Ground::GitHooks.ensure_pre_commit!(root: Dir.mktmpdir)
    assert result.ok?
    assert_equal :no_git, result.value![:skipped]
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