# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestBootEntrypoint < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/boot/entrypoint.rb", __dir__))
  GEMFILE = File.read(File.expand_path("../Gemfile", __dir__))
  LOCKFILE = File.read(File.expand_path("../Gemfile.lock", __dir__))

  def test_json_matches_ruby_4_default_gem
    assert_includes GEMFILE, 'gem "json", "= 2.18.0"'
    assert_match(/^    json \(2\.18\.0\)$/, LOCKFILE)
    assert_match(/^  json \(= 2\.18\.0\)$/, LOCKFILE)
    assert_match(/^  json \(2\.18\.0\) sha256=b10506aee4183f5cf49e0efc48073d7b75843ce3782c68dbeb763351c08fd505$/, LOCKFILE)
  end

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

  def test_json_is_loaded_only_after_bundler_activation
    bundle_index = SOURCE.index("activate_bundle!(root)")
    json_index = SOURCE.index('require "json"')
    refute_nil bundle_index
    refute_nil json_index
    assert_operator json_index, :>, bundle_index
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


  def test_android_accepts_supported_ruby_four_patch_release
    assert_match(/ANDROID_RUBY_PATTERN/, SOURCE)
    assert_includes SOURCE, 'RUBY_PLATFORM.include?("android")'
  end

  def test_preloaded_wrong_bundler_reexecs_into_a_clean_process
    Dir.mktmpdir("master-entrypoint") do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/

        DEPENDENCIES

        BUNDLED WITH
          4.0.5
      LOCK

      active = Struct.new(:version).new(Gem::Version.new("4.0.7"))
      env = {
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/wrong/bundler/lib",
        "BUNDLE_GEMFILE" => "/wrong/Gemfile",
        "BUNDLE_LOCKFILE" => "/wrong/Gemfile.lock",
      }
      captured = nil

      Master::Boot::Entrypoint.stub(:exec, ->(clean, program, *argv) { captured = [clean, program, argv] }) do
        Gem.stub(:loaded_specs, { "bundler" => active }) do
          Master::Boot::Entrypoint.reexec_mismatched_bundler!(
            root:, env:, out: StringIO.new, argv: ["--fast"], program: "/tmp/bin/cli"
          )
        end
      end

      refute_nil captured
      clean, program, argv = captured
      assert_equal "/tmp/bin/cli", program
      assert_equal ["--fast"], argv
      assert_equal "1", clean["MASTER_BUNDLER_REEXEC_DONE"]
      refute clean.key?("RUBYOPT")
      refute clean.key?("RUBYLIB")
      refute clean.key?("BUNDLE_GEMFILE")
      refute clean.key?("BUNDLE_LOCKFILE")
    end
  end
end
