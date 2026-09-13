# frozen_string_literal: true

require_relative "test_helper"

# LibraryVerify is the pre-flight Io::Shell and SelfTest run before trusting a
# gem, a path or a binary. A root with no Gemfile.lock cannot refuse a gem, so
# it answers ok rather than blocking every tree that is not a bundle.
class TestGroundLibraryVerify < Minitest::Test
  def setup
    @root = Dir.mktmpdir("library_verify_")
    File.write(File.join(@root, "Gemfile.lock"), "GEM\n  specs:\n    prism (1.4.0)\n    zeitwerk (2.7.2)\n")
    @verify = Master::Ground::LibraryVerify.new(root: @root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_gems_are_checked_by_name_and_optionally_by_exact_version
    assert @verify.verify_gem!("prism").ok?
    assert @verify.verify_gem!("prism", version: "1.4.0").ok?
    refute @verify.verify_gem!("prism", version: "1.4").ok?, "a version prefix is not the version"
    refute @verify.verify_gem!("pris").ok?, "a name prefix is not the gem"
    assert_equal :validation, @verify.verify_gem!("rails").category
  end

  def test_a_root_without_a_lock_cannot_refuse_a_gem
    bare = Dir.mktmpdir("library_verify_bare_")

    assert Master::Ground::LibraryVerify.new(root: bare).verify_gem!("anything").ok?
  ensure
    FileUtils.rm_rf(bare)
  end

  def test_paths_resolve_against_the_root
    assert_equal File.join(@root, "Gemfile.lock"), @verify.verify_path!("Gemfile.lock").value!
    refute @verify.verify_path!("missing/file.rb").ok?
  end

  def test_binaries_are_looked_up_on_path_and_not_executed
    assert @verify.verify_binary!("ruby").ok?
    refute @verify.verify_binary!("no-such-binary-#{Process.pid}").ok?
    refute @verify.verify_binary!("ruby; touch #{File.join(@root, 'pwned')}").ok?
    refute File.exist?(File.join(@root, "pwned")), "the name is escaped, never run"
  end
end
