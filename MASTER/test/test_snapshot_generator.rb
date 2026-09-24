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

  def test_snapshot_ignores_dot_paths_and_binary_media
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".hidden"))
      FileUtils.mkdir_p(File.join(dir, "nested", ".cache"))
      FileUtils.mkdir_p(File.join(dir, "media"))
      File.write(File.join(dir, ".hidden", "secret.rb"), "puts :hidden\n")
      File.write(File.join(dir, "nested", ".cache", "cache.rb"), "puts :cache\n")
      File.write(File.join(dir, "visible.rb"), "puts :visible\n")
      File.binwrite(File.join(dir, "media", "cover.png"), "\x89PNG\r\n")
      File.binwrite(File.join(dir, "media", "take.wav"), "RIFF")
      output = File.join(dir, "snapshot.md")

      Master::Snapshot.new(root: dir, output:).write!

      text = File.read(output)
      assert_includes text, "visible.rb"
      refute_includes text, "secret.rb"
      refute_includes text, "cache.rb"
      refute_includes text, "cover.png"
      refute_includes text, "take.wav"
    end
  end

  def test_snapshot_ignores_temp_generated_and_precompiled_assets
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "temp"))
      FileUtils.mkdir_p(File.join(dir, "generated"))
      FileUtils.mkdir_p(File.join(dir, "public", "assets"))
      File.write(File.join(dir, "temp", "scratch.rb"), "puts :scratch\n")
      File.write(File.join(dir, "generated", "output.rb"), "puts :generated\n")
      File.write(File.join(dir, "public", "assets", "bundle.js"), "console.log('built')\n")
      File.write(File.join(dir, "kept.md"), "# kept\n")
      output = File.join(dir, "snapshot.md")

      Master::Snapshot.new(root: dir, output:).write!

      text = File.read(output)
      assert_includes text, "kept.md"
      refute_includes text, "scratch.rb"
      refute_includes text, "output.rb"
      refute_includes text, "bundle.js"
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

  # The README promises one snapshot per governed tree from a bare /snapshot;
  # Snapshot#write! gives that only when rooted at the repository.
  def test_bare_snapshot_command_roots_at_the_repository
    roots = []
    fake = Object.new
    def fake.write! = %w[snapshot_MASTER.md snapshot_RAILS.md]
    capture = ->(root:, **) { roots << root; fake }

    out = Master::Snapshot.stub(:new, capture) { Master::CLI::CommandRegistry.dispatch_snapshot(nil, ctx: { args: "" }) }

    assert_equal [Master.repo_root], roots
    assert_equal "snapshot_MASTER.md\nsnapshot_RAILS.md", out
  end
end
