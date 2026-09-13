# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Rollback stashes a dirty checkout and resets it when a pipeline result fails
# in a category that means the edit cannot be trusted. It must refuse a clean
# tree, a non-git directory, a success and an ordinary category, because every
# one of those would stash somebody's work for nothing.
class TestFixRollback < Minitest::Test
  FakeBus = Struct.new(:events) do
    def publish(name, **payload) = events << [name, payload]
  end

  def setup
    @root = Dir.mktmpdir("rollback_")
    git("init", "-q")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "t")
    File.write(File.join(@root, "a.rb"), "one\n")
    git("add", "a.rb")
    git("commit", "-q", "-m", "seed")
    @bus = FakeBus.new([])
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def git(*args)
    out, status = Open3.capture2e("git", "-C", @root, *args)
    raise out unless status.success?

    out
  end

  def failure(category) = Master::Result.err("the edit broke validation", category:)

  def test_a_dirty_tree_after_a_validation_failure_is_stashed_and_reset
    File.write(File.join(@root, "a.rb"), "two\n")

    assert Master::Fix::Rollback.new(root: @root, bus: @bus).call(failure(:validation))
    assert_equal "one\n", File.read(File.join(@root, "a.rb"))
    assert_match(/master:rollback:validation:/, git("stash", "list"))
    assert_equal %w[pipeline:rollback ops:rollback], @bus.events.map(&:first)
  end

  def test_a_clean_tree_is_left_alone
    refute Master::Fix::Rollback.new(root: @root, bus: @bus).call(failure(:validation))
    assert_empty @bus.events
  end

  def test_a_category_outside_the_list_is_left_alone
    File.write(File.join(@root, "a.rb"), "two\n")

    refute Master::Fix::Rollback.new(root: @root).call(failure(:timeout))
    assert_equal "two\n", File.read(File.join(@root, "a.rb"))
  end

  def test_a_success_is_never_rolled_back
    File.write(File.join(@root, "a.rb"), "two\n")

    refute Master::Fix::Rollback.new(root: @root).call(Master::Result.ok("fine"))
    assert_equal "two\n", File.read(File.join(@root, "a.rb"))
  end

  def test_a_directory_that_is_not_a_checkout_is_left_alone
    plain = Dir.mktmpdir("not_git_")
    File.write(File.join(plain, "a.rb"), "x\n")

    refute Master::Fix::Rollback.new(root: plain).call(failure(:validation))
  ensure
    FileUtils.rm_rf(plain)
  end
end
