# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# /commit commits the paths it is given and nothing else. The checkout is shared
# by several sessions, so a commit that swept up every modified file would
# publish someone else's half-finished work under this session's message.
class TestCommitCommand < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  class ScriptedAgent
    attr_reader :prompts

    def initialize = @prompts = []

    def ask_once(prompt)
      @prompts << prompt
      "Record the named change"
    end
  end

  def setup
    @prior = ENV["MASTER_SELF_EVOLUTION"]
    ENV["MASTER_SELF_EVOLUTION"] = "0"
    @root = Dir.mktmpdir("commit_command")
    git("init", "-q")
    git("config", "user.email", "test@example.invalid")
    git("config", "user.name", "test")
    File.write(File.join(@root, "mine.rb"), "A = 1\n")
    File.write(File.join(@root, "theirs.rb"), "B = 1\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    File.write(File.join(@root, "mine.rb"), "A = 2\n")
    File.write(File.join(@root, "theirs.rb"), "B = 2\n")
    File.write(File.join(@root, "new.rb"), "C = 1\n")
    @agent = ScriptedAgent.new
  end

  def teardown
    @prior ? ENV["MASTER_SELF_EVOLUTION"] = @prior : ENV.delete("MASTER_SELF_EVOLUTION")
    FileUtils.remove_entry(@root)
  end

  def test_commits_only_the_named_paths
    Registry.dispatch_commit(@agent, @root, ctx: { args: "mine.rb new.rb" })

    assert_equal "Record the named change", git("log", "-1", "--format=%s").strip
    assert_equal %w[mine.rb new.rb], git("show", "--name-only", "--format=", "HEAD").split.sort
    assert_includes git("status", "--porcelain"), " M theirs.rb", "an unnamed change must stay uncommitted"
  end

  def test_no_paths_is_refused_before_the_model_is_asked
    out = Registry.dispatch_commit(@agent, @root, ctx: { args: "" })

    assert_equal Registry::COMMIT_USAGE, out
    assert_empty @agent.prompts
    assert_equal "base", git("log", "-1", "--format=%s").strip
  end

  def test_a_clean_path_commits_nothing
    git("checkout", "--", "mine.rb")

    out = Registry.dispatch_commit(@agent, @root, ctx: { args: "mine.rb" })

    assert_equal "commit: nothing to commit in mine.rb", out
    assert_equal "base", git("log", "-1", "--format=%s").strip
  end

  def test_the_built_verb_waits_for_confirmation
    command = Registry::Command.new(Registry, :dispatch_commit, @agent, @root, review_gate: true)

    assert_includes command.call(args: "mine.rb"), Registry::Command::CONFIRM_FLAG
    assert_equal "base", git("log", "-1", "--format=%s").strip

    command.call(args: "mine.rb --confirm")
    assert_equal "Record the named change", git("log", "-1", "--format=%s").strip
  end

  private

  def git(*args)
    out, err, status = Open3.capture3("git", "-C", @root, *args)
    assert status.success?, err
    out
  end
end
