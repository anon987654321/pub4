# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestSnapshotGenerator < Minitest::Test
  def test_snapshot_contains_tree_and_source
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "example.rb"), "# example\n")
      output = File.join(dir, "snapshot.md")
      path = Master::Snapshot.new(root: dir, output:).write!

      text = File.read(path)
      assert_includes text, "## Tree"
      assert_includes text, "lib"
      assert_includes text, "example.rb"
      assert_includes text, "## Source"
      assert_includes text, "# example"
    end
  end

  def test_snapshot_does_not_include_its_own_output
    Dir.mktmpdir do |dir|
      output = File.join(dir, "snapshot_MASTER.md")
      File.write(File.join(dir, "example.rb"), "puts :ok\n")
      Master::Snapshot.new(root: dir, output:).write!
      refute_includes File.read(output), "snapshot_MASTER.md"
    end
  end
end
