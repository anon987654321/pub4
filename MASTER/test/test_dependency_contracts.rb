# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestDependencyContracts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_reek_dependency_is_declared_for_reek_rule
    gemfile = File.read(File.join(ROOT, "Gemfile"))
    lockfile = File.read(File.join(ROOT, "Gemfile.lock"))

    assert_includes gemfile, 'gem "reek", "~> 6.4", require: false'
    assert_match(/^    reek \(/, lockfile)
    assert_match(/^  reek \(~> 6\.4\)/, lockfile)
  end

  def test_prism_dependency_matches_ruby_language_support
    require "prism"

    rules = YAML.load_file(File.join(ROOT, "data", "rules.yml"), aliases: true)
    ruby_version = rules.dig("languages", "ruby", "version")

    assert_equal "3.3+", ruby_version
    assert_operator Gem::Version.new(Prism::VERSION), :>=, Gem::Version.new("1.7.0")
  end
end
