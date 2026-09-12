# frozen_string_literal: true

require "test_helper"

class PathGuardTest < Minitest::Test
  def setup
    @root = Master::ROOT
    @tool = Class.new do
      include Master::Io::PathGuard
      def initialize(root) = @root = root
    end.new(@root)
  end

  def test_rejects_prefix_escape_paths
    result = @tool.resolve("#{@root}_evil/secret.txt")
    assert result.err?
    assert_match(/escapes project root/, result.message)
  end

  def test_accepts_paths_inside_root
    result = @tool.resolve("lib/io/path_guard.rb")
    assert result.ok?
    assert result.value!.start_with?(@root)
  end
end

# GitContext#show is the one operation in that class taking no path: its argument
# is a git ref, handed straight to `git show`. `git show <rev>:<path>` prints that
# path's blob, so the colon form was a file read that never passed through
# PathGuard at all — any tracked file, at any revision, including ones deleted
# since — and Io::LLM::GitContext exposes it to a model. Refused at the ref.
class GitContextShowTest < Minitest::Test
  def setup
    @git = Master::Io::GitContext.new(root: Master::ROOT)
  end

  def show(ref) = @git.call(operation: "show", path: ref)

  def test_a_plain_ref_still_describes_a_commit
    result = show("HEAD")

    assert result.ok?, "HEAD should resolve"
    assert_match(/commit [0-9a-f]{7}/, result.value!.to_s)
  end

  def test_a_rev_path_ref_is_refused
    ["HEAD:TODO.md", "HEAD:MASTER/data/security.yml", "HEAD~1:CLAUDE.md"].each do |ref|
      result = show(ref)

      refute result.ok?, "#{ref} must not reach git show"
      assert_match(/must name a commit/, result.message.to_s)
    end
  end

  # The refusal is the colon, not a filename-looking argument: a ref that merely
  # reads file-ish is still a ref.
  def test_the_refusal_is_the_colon_and_not_the_shape
    assert show("HEAD").ok?
    refute show("HEAD:").ok?
  end
end
