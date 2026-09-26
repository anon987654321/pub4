# frozen_string_literal: true

require "minitest/autorun"

class TestTriangleRuntimeContract < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SOURCE = File.read(File.join(ROOT, "bin", "triangle"), encoding: "UTF-8")

  def test_triangle_uses_the_shared_runtime
    assert_includes SOURCE, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes SOURCE, "RUBY = Operator::RubyRunner.ruby_cmd"
    assert_includes SOURCE, "BUNDLE = Operator::RubyRunner.bundle_cmd"
    refute_includes SOURCE, '"rbenv", "exec"'
  end

  def test_migrate_and_boot_run_the_pinned_ruby_inside_bundle
    assert_includes SOURCE, 'BUNDLE, "exec", RUBY, "bin/rails", "db:prepare"'
    assert_includes SOURCE, 'BUNDLE, "exec", RUBY, "bin/rails", "server"'
  end

  def test_triangle_does_not_boot_after_a_failed_migration
    assert_includes SOURCE, 'unless migrate(app)'
    assert_includes SOURCE, 'failed << app[:name]'
    assert_includes SOURCE, 'next'
  end
end
