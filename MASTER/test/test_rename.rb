# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "rbconfig"
require "tmpdir"

# The renamer, proved by loading what it renamed.
#
# A rename is the one fix here that reading the diff cannot check: the failure is
# a reference nobody rewrote, and that looks like nothing at all until a caller
# loads. So the fixture is a program, and the test runs it. One line of output
# carries four properties — the constant answers to its new name, the require
# found the moved file, the path written as a string still points at something,
# and the longer name that merely starts the same was left alone.
#
# Those last two are incidents, not hypotheticals. `File.join(LIB, "pub4",
# "status_report.rb")` survived the 2026-09-11 rename and failed a contract test
# an hour later, and `Pub4` glued to `Openbsd` is a different constant the sweep
# had to not touch.
#
# The environment goes inside the command array. `IO.popen(env, [ruby, tool])`
# dropped it on the way to the child and the first run of this file aimed the
# renamer at the real repository. The tool refuses a dirty tree now, which is the
# guard that makes that mistake cost nothing.
class TestRename < Minitest::Test
  TOOL = File.expand_path("../tools/rename.rb", __dir__)

  def setup
    @dir = Dir.mktmpdir("rename")
    write("lib/demo/demo_thing_manager.rb", <<~RUBY)
      module Demo
        class DemoThingManager
          def call = "renamed"
        end
      end
    RUBY
    write("lib/demo/demo_thing_manager_extra.rb", <<~RUBY)
      module Demo
        class DemoThingManagerExtra
          def call = "untouched"
        end
      end
    RUBY
    write("lib/caller.rb", <<~RUBY)
      require_relative "demo/demo_thing_manager"
      require_relative "demo/demo_thing_manager_extra"

      carried = File.join(__dir__, "demo", "demo_thing_manager.rb")
      puts [Demo::DemoThingManager.new.call,
            Demo::DemoThingManagerExtra.new.call,
            File.exist?(carried)].join(" ")
    RUBY
    git("init", "--quiet")
    git("add", "-A")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--quiet", "-m", "fixture")
  end

  def teardown = FileUtils.remove_entry(@dir)

  def test_a_category_suffix_is_a_candidate_and_the_proposal_drops_it
    row = candidates.find { |line| line.include?("DemoThingManager ") }

    refute_nil row, "Manager at the end of a name is what this rule is for:\n#{candidates.join("\n")}"
    assert_includes row, "-> DemoThing"
  end

  def test_the_renamed_program_still_runs_and_says_so
    apply!

    assert_equal "renamed untouched true", run_fixture.strip,
                 "the constant answers to its new name, the require found the moved file, the " \
                 "path written as a string still resolves, and the longer name was left alone"
  end

  def test_apply_moves_the_file_because_the_path_is_the_name
    apply!

    refute_path_exists File.join(@dir, "lib", "demo", "demo_thing_manager.rb")
    assert_path_exists File.join(@dir, "lib", "demo", "demo_thing.rb"),
                       "Zeitwerk resolves a constant by its path, so a rename that leaves the file " \
                       "where it was is a constant that stops loading"
  end

  def test_nothing_is_written_without_apply
    run_tool("DemoThingManager", "DemoThing")

    assert_equal "renamed untouched true", run_fixture.strip
    assert_path_exists File.join(@dir, "lib", "demo", "demo_thing_manager.rb")
  end

  def test_a_dirty_tree_refuses_the_rewrite
    write("lib/scratch.rb", "# someone else is mid-edit\n")
    output = apply!

    assert_match(/uncommitted/, output)
    assert_path_exists File.join(@dir, "lib", "demo", "demo_thing_manager.rb"),
                       "a bulk rewrite mixed into somebody else's diff cannot be reviewed or reverted"
  end

  private

  def write(relative, text)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def git(*args) = system("git", "-C", @dir, *args, out: File::NULL, err: File::NULL)

  def run_tool(*args)
    IO.popen([{ "RENAME_ROOT" => @dir }, RbConfig.ruby, TOOL, *args], err: [:child, :out], &:read)
  end

  def run_fixture
    IO.popen([RbConfig.ruby, File.join(@dir, "lib", "caller.rb")], err: [:child, :out], &:read)
  end

  def candidates = @candidates ||= run_tool.lines.map(&:chomp)

  def apply! = run_tool("DemoThingManager", "DemoThing", "--apply")
end
