# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

  def test_rejects_a_symlink_inside_root_that_points_outside
    Dir.mktmpdir do |dir|
      root = File.realpath(File.join(dir, "root").tap { |r| Dir.mkdir(r) })
      # Immutability refuses a root with no sacred manifest before the symlink
      # check under test is reached.
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/soul.yml\n")
      outside = File.join(dir, "outside").tap { |o| Dir.mkdir(o) }
      File.symlink(outside, File.join(root, "link"))
      tool = @tool.class.new(root)

      assert tool.resolve("link/secret.txt").err?, "an existing link must not lead out"
      assert tool.resolve("link/new/deeper.txt").err?, "nor a not-yet-created path beneath it"
      assert tool.resolve("plain/new.txt").ok?, "a not-yet-created path under the real root is fine"
    end
  end
end

# The prefix check alone passed a symlink inside the root that points out of it,
# and passed credential files to ReadFile. These run the tools on a scratch root.
class PathGuardEscapeTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir("path_guard"))
    @root = File.join(@dir, "root")
    @outside = File.join(@dir, "outside")
    FileUtils.mkdir_p([@root, @outside])
    File.write(File.join(@outside, "passwd"), "root:x:0:0\n")
    File.write(File.join(@root, "notes.txt"), "hello\n" * 5000)
    File.write(File.join(@root, ".env"), "SECRET=hunter2\n")
    File.symlink(@outside, File.join(@root, "link"))
  end

  def teardown = FileUtils.rm_rf(@dir)

  def read_file = Master::Io::ReadFile.new(root: @root, undo: nil)

  def test_a_symlink_out_of_the_root_is_refused_for_reads_and_writes
    refute read_file.call(path: "link/passwd").ok?
    writer = Master::Io::WriteFile.new(root: @root, undo: nil, governor: nil)
    result = writer.call(path: "link/planted.txt", content: "x")
    refute result.ok?
    refute File.exist?(File.join(@outside, "planted.txt"))
  end

  def test_credential_files_are_refused_on_read
    result = read_file.call(path: ".env")
    refute result.ok?
    refute_includes result.message.to_s, "hunter2"
  end

  def test_read_limit_is_clamped
    body = read_file.call(path: "notes.txt", limit: 1_000_000).value!
    assert_match(/truncated, 5000 total lines/, body) # source-assertion: ok — the tool's returned text, not a source file
  end

  def test_search_files_stays_inside_the_root
    search = Master::Io::SearchFiles.new(root: @root)
    %w[../outside/* link/* **/*].each do |glob|
      out = search.call(pattern: "root:x", glob:).value!
      refute_includes out, "root:x", "#{glob} reached outside the root"
    end
    refute_includes search.call(pattern: "SECRET", glob: ".*").value!, "hunter2"
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

  # Blame of a long file is model context; it passes through OutputFilter.
  def test_long_output_is_compressed
    body = @git.call(operation: "blame", path: "lib/io/path_guard.rb").value!.to_s
    assert_operator body.lines.size, :<=, 81
    assert_operator @git.call(operation: "log", limit: 100_000).value!.to_s.lines.size, :<=, 81
  end
end
