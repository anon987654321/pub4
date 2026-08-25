# frozen_string_literal: true

require_relative "test_helper"

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

    rules = Master.load_yaml(File.join(ROOT, "data", "rules.yml"))
    ruby_version = rules.dig("languages", "ruby", "version")

    assert_equal "3.3+", ruby_version
    assert_operator Gem::Version.new(Prism::VERSION), :>=, Gem::Version.new("1.7.0")
  end

  REPO = File.expand_path("../..", __dir__)

  # No workflow may name a Ruby version. `.ruby-version` is the pin — five files,
  # all 3.4.9, one per tree — and a workflow that restates it is a second source
  # that drifts silently: master-improve and master-through-master installed 3.3
  # against a repo pinned at 3.4.9, so two of five CI jobs were testing a
  # different interpreter than anyone runs locally or on vm23.
  #
  # setup-ruby resolves `.ruby-version` against the step's working directory, and
  # each of those directories has one, so this reads the same pin everywhere.
  def test_no_workflow_hardcodes_a_ruby_version
    offenders = Dir[File.join(REPO, ".github/workflows/*.yml")].filter_map do |path|
      literal = File.read(path)[/^\s*ruby-version:\s*["']?(\d[\d.]*)["']?\s*$/, 1]
      "#{File.basename(path)} pins #{literal}" if literal
    end

    assert_empty offenders, "workflows must read .ruby-version, not restate it"
  end

  def test_every_ruby_version_file_agrees
    pins = Dir[File.join(REPO, "{,MASTER/,RAILS/*/}.ruby-version")].to_h do |path|
      [path.sub("#{REPO}/", ""), File.read(path).strip]
    end

    refute_empty pins, "no .ruby-version found — this test would pass having measured nothing"
    assert_equal 1, pins.values.uniq.size, "the pin disagrees with itself: #{pins.inspect}"
  end
end
