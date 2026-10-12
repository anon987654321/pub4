# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"
require "yaml"

class RailsStackContractTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  STACK = YAML.safe_load_file(File.join(REPO_ROOT, "RAILS", "apps.yml")).fetch("rails_stack")
  RAILS_VERSION = Gem::Version.new(STACK.fetch("rails"))
  RAILS_SOURCE = STACK.fetch("rails_source")
  RAILS_REF = STACK.fetch("rails_ref")

  APP_ROOTS = %w[
    RAILS/brgen
    RAILS/amber
    RAILS/bsdports
    RAILS/master_web
  ].freeze

  LOCKED_ROOTS = %w[
    RAILS/brgen
    RAILS/amber
    RAILS/bsdports
    RAILS/master_web
  ].freeze

  def test_every_rails_gemfile_tracks_the_current_stack
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "Gemfile"))
      match = body.match(/gem "rails", github: "([^"]+)", ref: "([^"]+)"/)
      assert match, "#{root}/Gemfile must pin Rails from the audited git source"
      assert_equal RAILS_SOURCE, match[1]
      assert_equal RAILS_REF, match[2]
    end
  end

  def test_every_locked_app_resolves_the_current_rails_source
    LOCKED_ROOTS.each do |root|
      path = File.join(REPO_ROOT, root, "Gemfile.lock")
      body = File.read(path)
      rails = body[/^    rails \(([^)]+)\)$/m, 1]

      assert rails, "#{root}/Gemfile.lock has no locked Rails version"
      assert_equal RAILS_VERSION, Gem::Version.new(rails)

      railties = body[/^    railties \(([^)]+)\)$/m, 1]
      assert_equal rails, railties, "#{root}/Gemfile.lock splits Rails and railties versions"

      git = body[/^  revision: (\h+)$/m, 1]
      assert_equal RAILS_REF, git, "#{root}/Gemfile.lock is not pinned to Rails #{RAILS_REF}"
    end
  end

  def test_every_rails_app_uses_8_2_framework_defaults
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "config", "application.rb"))

      assert_includes body, "config.load_defaults 8.2",
                       "#{root} is not on the Rails 8.2 framework-default target"
      refute_includes body, "config.load_defaults 8.1",
                      "#{root} still carries Rails 8.1 defaults"
    end
  end
  def test_ruby_pins_and_lockfiles_match_their_tree_owner
    root_version = File.read(File.join(REPO_ROOT, ".ruby-version")).strip
    master_version = File.read(File.join(REPO_ROOT, "MASTER", ".ruby-version")).strip

    assert_equal "4.0.5", root_version, "change the root/Rails runtime deliberately with this contract"
    assert_equal "4.0.7", master_version, "change MASTER's runtime deliberately with this contract"

    APP_ROOTS.each do |root|
      app_version = File.read(File.join(REPO_ROOT, root, ".ruby-version")).strip
      assert_equal root_version, app_version, "#{root}/.ruby-version disagrees with the root Rails runtime"

      lock = File.read(File.join(REPO_ROOT, root, "Gemfile.lock"))
      locked_version = lock[/^  ruby (\\S+)$/, 1]
      assert_equal app_version, locked_version, "#{root}/Gemfile.lock was resolved under another Ruby"
    end

    master_lock = File.read(File.join(REPO_ROOT, "MASTER", "Gemfile.lock"))
    master_locked_version = master_lock[/^  ruby (\\S+)$/, 1]
    assert_equal master_version, master_locked_version,
                 "MASTER/Gemfile.lock was resolved under another Ruby"
  end

end
