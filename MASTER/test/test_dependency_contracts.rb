# frozen_string_literal: true

require_relative "test_helper"

class TestDependencyContracts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("../..", __dir__)

  def test_reek_dependency_is_declared_for_reek_rule
    gemfile = File.read(File.join(ROOT, "Gemfile"))
    lockfile = File.read(File.join(ROOT, "Gemfile.lock"))

    assert_includes gemfile, 'gem "reek", "~> 6.4", require: false'
    assert_match(/^    reek \(/, lockfile)
    assert_match(/^  reek \(~> 6\.4\)/, lockfile)
  end

  def test_prism_dependency_matches_ruby_language_support
    require "prism"

    rules = Master.load_yaml(File.join(ROOT, "data", "laws.yml"))
    ruby_version = rules.dig("languages", "ruby", "version")

    assert_equal "3.3+", ruby_version
    assert_operator Gem::Version.new(Prism::VERSION), :>=, Gem::Version.new("1.7.0")
  end

  def test_rubocop_uses_the_repository_ruby_pin
    paths = [
      File.join(ROOT, ".rubocop.yml"),
      File.join(REPO, "RAILS", "shared", ".rubocop.yml"),
    ]

    paths.each do |path|
      refute_match(/TargetRubyVersion:/, File.read(path),
                   "#{path} must derive its Ruby target from .ruby-version")
    end
  end

  def test_every_ruby_version_file_agrees
    pins = Dir[File.join(REPO, "{,MASTER/,RAILS/*/}.ruby-version")].to_h do |path|
      [path.sub("#{REPO}/", ""), File.read(path).strip]
    end

    refute_empty pins, "no .ruby-version found — this test would pass having measured nothing"
    assert_equal 1, pins.values.uniq.size, "the pin disagrees with itself: #{pins.inspect}"
  end

end
