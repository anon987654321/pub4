# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class RailsStackContractTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  STACK = YAML.safe_load_file(File.join(REPO_ROOT, "MASTER", "data", "rules.yml")).fetch("rails_stack")
  RAILS_VERSION = STACK.fetch("rails")
  RAILS_REF = "c9e85dbe297e248dd2f217d04f84a94881ac046a"

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

  def test_every_rails_gemfile_pins_the_exact_8_2_source
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "Gemfile"))
      assert_includes body,
        %(gem "rails", github: "rails/rails", ref: "#{RAILS_REF}"),
        "#{root}/Gemfile must pin Rails #{RAILS_VERSION} at #{RAILS_REF}"
    end
  end

  def test_every_locked_app_carries_the_exact_8_2_framework
    LOCKED_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "Gemfile.lock"))
      assert_includes body, "remote: https://github.com/rails/rails"
      assert_includes body, "revision: #{RAILS_REF}"
      assert_includes body, "actioncable (8.2.0.alpha)"
      assert_includes body, "actionview (8.2.0.alpha)"
      assert_includes body, "activesupport (8.2.0.alpha)"
      assert_includes body, "rails (8.2.0.alpha)"
      assert_includes body, "railties (8.2.0.alpha)"
      assert_includes body, "herb (0.11.0)"
      assert_includes body, "ractor-dispatch (0.3.0)"
      assert_includes body, "marcel (2.1.0)"
      assert_includes body, "rails!"
      refute_includes body, "rails (8.1.4)"
      refute_includes body, "rails (~> 8.1.4)"
    end
  end

  def test_every_rails_app_uses_8_2_framework_defaults
    APP_ROOTS.each do |root|
      body = File.read(File.join(REPO_ROOT, root, "config", "application.rb"))

      assert_includes body, "config.load_defaults 8.2",
                      "#{root} is not on Rails 8.2 defaults"
      refute_includes body, "config.load_defaults 8.1",
                      "#{root} still carries Rails 8.1 defaults"
    end
  end
end
