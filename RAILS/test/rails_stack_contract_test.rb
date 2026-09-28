# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"
require "yaml"

class RailsStackContractTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  RAILS_ROOT = File.join(REPO_ROOT, "RAILS")
  STACK = YAML.safe_load_file(File.join(REPO_ROOT, "MASTER", "data", "rules.yml")).fetch("rails_stack")
  RAILS_VERSION = Gem::Version.new(STACK.fetch("rails"))
  RAILS_REQUIREMENT = Gem::Requirement.new("~> #{RAILS_VERSION}")

  APP_ROOTS = %w[
    RAILS/brgen
    RAILS/amber
    RAILS/bsdports
    RAILS/eritel
    MASTER/web
  ].freeze

  LOCKED_ROOTS = %w[
    RAILS/brgen
    RAILS/amber
    RAILS/bsdports
    MASTER/web
  ].freeze

  def test_every_rails_gemfile_tracks_the_current_stack
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "Gemfile"))
      requirement = body[/gem "rails", "([^"]+)"/, 1]

      assert_equal RAILS_REQUIREMENT.to_s, requirement,
                   "#{root}/Gemfile must track Rails #{RAILS_VERSION}, not #{requirement.inspect}"
    end
  end

  def test_every_locked_app_resolves_the_current_rails_release
    LOCKED_ROOTS.each do |root|
      path = File.join(REPO_ROOT, root, "Gemfile.lock")
      body = File.read(path)
      rails = body[/^    rails \((\d+(?:\.\d+)+)\)$/m, 1]

      assert rails, "#{root}/Gemfile.lock has no locked Rails version"
      assert_equal RAILS_VERSION, Gem::Version.new(rails)

      railties = body[/^    railties \((\d+(?:\.\d+)+)\)$/m, 1]
      assert_equal rails, railties, "#{root}/Gemfile.lock splits Rails and railties versions"

      dependency = body[/^  rails \(([^)]+)\)$/m, 1]
      assert_equal RAILS_REQUIREMENT.to_s, dependency,
                   "#{root}/Gemfile.lock dependency no longer matches the Gemfile"
    end
  end

  def test_every_rails_app_uses_8_1_framework_defaults
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "config", "application.rb"))

      assert_includes body, "config.load_defaults 8.1",
                       "#{root} is on an older Rails framework-default target"
      refute_includes body, "config.load_defaults 8.0",
                      "#{root} still targets Rails 8.0 defaults"
    end
  end
end
