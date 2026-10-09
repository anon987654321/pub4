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
    refute_match(/\["ruby\d+"\]/, source)
  end

  def test_css_builder_delegates_bundle_selection
    source = read("../MASTER/tools/rails/build_all_css.rb")
    assert_includes source, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, '["rbenv", "exec", "bundle"]'
  end

  def test_style_gate_delegates_bundler_and_ruby
    source = read("../MASTER/tools/style_gate.rb")
    assert_includes source, 'require_relative "../lib/operator/ruby_runner"'
    assert_includes source, %([BUNDLE, "exec", RUBY, "-S", "rubocop")
    assert_includes source, %([BUNDLE, "exec", RUBY, shared_rubocop])
    refute_match(/which ruby\d+/, source)
  end
  # The preference order is written in three languages and must stay one list.
  def test_ruby_preference_order_is_the_same_in_every_resolver
    require_relative "../lib/operator/ruby_runner"
    order = Operator::RubyRunner::RUBY_NAMES
    assert_equal order.join(" "), read("bin/ruby")[/for name in ([^;]+); do/, 1]
    assert_equal order.join(" "), read("../OPENBSD/lib/ruby_select.sh")[/for _rs_candidate in ([^;]+); do/, 1]
  end
end
