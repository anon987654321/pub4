# frozen_string_literal: true

require_relative "test_helper"

class TestBootEntrypoint < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/boot/entrypoint.rb", __dir__))

  def test_dependency_bootstrap_activates_the_master_bundle
    assert_match(/DependencyManager\.ensure!\(.*?\n.*?activate_bundle!\(root\)/m, SOURCE)
    assert_includes SOURCE, 'ENV["BUNDLE_GEMFILE"] = gemfile'
    assert_includes SOURCE, 'require "bundler/setup"'
  end
end
