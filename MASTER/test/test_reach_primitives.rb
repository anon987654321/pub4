# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class ReachPrimitivesTest < Minitest::Test
  class PermitAll
    def permit?(_name, _tier, _ctx = nil)
      Master::Result.ok(true)
    end
  end

  class FakeSession
    def snapshot(_path, _content); end
  end

  def setup
    @dir = Dir.mktmpdir("reach-primitives")
    @session = FakeSession.new
    @undo = Master::Trace::Undo.new(session: @session, root: @dir)
    @governor = PermitAll.new
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_read_file_returns_numbered_lines
    path = File.join(@dir, "sample.txt")
    File.write(path, "alpha\nbeta\n")

    tool = Master::Io::ReadFile.new(root: @dir, undo: @undo)
    result = tool.call(path: "sample.txt")

    assert result.ok?
    assert_includes result.value!, "1\talpha"
    assert_includes result.value!, "2\tbeta"
  end

  def test_write_file_creates_file
    tool = Master::Io::WriteFile.new(root: @dir, undo: @undo, governor: @governor)
    result = tool.call(path: "out.txt", content: "hello\n")

    assert result.ok?
    assert_equal "hello\n", File.read(File.join(@dir, "out.txt"))
  end

  def test_list_dir_lists_entries
    FileUtils.mkdir_p(File.join(@dir, "nested"))
    File.write(File.join(@dir, "nested", "child.txt"), "x")

    tool = Master::Io::ListDir.new(root: @dir)
    result = tool.call(path: ".", depth: 2)

    assert result.ok?
    assert_includes result.value!, "nested/"
    assert_includes result.value!, "child.txt"
  end

  def test_search_files_finds_match
    FileUtils.mkdir_p(File.join(@dir, "a"))
    File.write(File.join(@dir, "a", "needle.txt"), "findme")

    tool = Master::Io::SearchFiles.new(root: @dir)
    result = tool.call(pattern: "findme")

    assert result.ok?
    assert_includes result.value!, "needle.txt"
  end

  def test_str_replace_replaces_unique_match
    path = File.join(@dir, "edit.txt")
    File.write(path, "hello world\n")

    tool = Master::Io::StrReplace.new(root: @dir, undo: @undo, governor: @governor)
    result = tool.call(path: "edit.txt", old_string: "world", new_string: "universe")

    assert result.ok?
    assert_equal "hello universe\n", File.read(path)
  end

  def test_str_replace_rejects_ambiguous_match
    path = File.join(@dir, "dup.txt")
    File.write(path, "foo bar foo\n")

    tool = Master::Io::StrReplace.new(root: @dir, undo: @undo, governor: @governor)
    result = tool.call(path: "dup.txt", old_string: "foo", new_string: "baz")

    assert result.err?
    assert_match(/matches 2 times/, result.message)
  end

  def test_shell_runs_permitted_command
    tool = Master::Io::Shell.new(root: @dir, governor: @governor)
    result = tool.call(command: "echo reach-smoke")

    assert result.ok?
    assert_includes result.value!, "reach-smoke"
  end

  class RecordingBus
    attr_reader :events
    def initialize = @events = []
    def publish(name, payload = {}) = @events << [name, payload]
  end

  # With a bus wired, as the runtime always wires it, every call raised reading
  # an exit status off the stdout string, and a failing command read as success.
  def test_shell_with_a_bus_reports_success_and_failure_honestly
    bus = RecordingBus.new
    tool = Master::Io::Shell.new(root: @dir, governor: @governor, event_bus: bus)

    ok = tool.call(command: "echo reach-smoke")
    failed = tool.call(command: "echo broke >&2; exit 3")

    assert ok.ok?, (ok.message if ok.err?).to_s
    assert_includes ok.value!, "reach-smoke"
    assert failed.err?
    assert_match(/exit 3: broke/, failed.message)
    assert_equal [0, 3], bus.events.select { |name, _| name == "tool:after" }.map { |_, payload| payload[:exit_code] }
  end

  def test_shell_blocks_destructive_command
    tool = Master::Io::Shell.new(root: @dir, governor: @governor)
    result = tool.call(command: "rm -rf /tmp/master-reach-smoke-should-never-run")

    assert result.err?
    assert_match(/blocked/, result.message)
  end
end
