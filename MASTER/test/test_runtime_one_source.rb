# frozen_string_literal: true

require "minitest/autorun"

class TestRuntimeOneSource < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_release_gate_delegates_runtime_selection
    source = read("../MASTER/gates/release.rb")
    assert_includes source, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes source, "[Operator::RubyRunner.ruby_cmd]"
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, '["ruby34"]'
  end

  def test_css_builder_delegates_bundle_selection
    source = read("../RAILS/tools/build_all_css.rb")
    assert_includes source, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, '["rbenv", "exec", "bundle"]'
  end

  def test_style_gate_delegates_bundler_and_ruby
    source = read("../MASTER/tools/style_gate.rb")
    assert_includes source, 'require_relative "../lib/operator/ruby_runner"'
    assert_includes source, %([BUNDLE, "exec", RUBY, "-S", "rubocop")
    assert_includes source, %([BUNDLE, "exec", RUBY, shared_rubocop])
    refute_includes source, "which ruby34"
  end
end
