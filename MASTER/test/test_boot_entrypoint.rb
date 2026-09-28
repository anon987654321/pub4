# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestBootEntrypoint < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/boot/entrypoint.rb", __dir__))

  def test_dependency_bootstrap_activates_the_master_bundle
    assert_match(/DependencyManager\.ensure!\(.*?\n.*?activate_bundle!\(root\)/m, SOURCE)
    assert_includes SOURCE, 'ENV["BUNDLE_GEMFILE"] = gemfile'
    assert_includes SOURCE, 'require "bundler/setup"'
  end

  def test_bundle_activation_uses_the_lockfile_bundler_version
    assert_match(/version = locked_bundler_version\(root\)/, SOURCE)
    assert_match(/gem\("bundler", version\) unless version\.empty\?/, SOURCE)
    assert_match(/require "bundler\/setup"/, SOURCE)
  end

  def test_lockfile_bundler_version_is_read_from_the_master_lock
    Dir.mktmpdir("master-entrypoint") do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/

        DEPENDENCIES

        BUNDLED WITH
          4.0.7
      LOCK

      reader = Master::Boot::Entrypoint.method(:locked_bundler_version)
      assert_equal "4.0.7", reader.call(root)
    end
  end
end
