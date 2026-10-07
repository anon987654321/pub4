# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../tools/snapshot_extract"

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

  def test_operator_snapshot_marks_completion_and_uses_zsh_shell_fences
    source = File.read(File.expand_path("../tools/snapshot.rb", __dir__))

    assert_includes source, '".sh" => "zsh"'
    assert_includes source, '".zsh" => "zsh"'
    assert_includes source, '"## Snapshot part complete"'
    assert_includes source, 'part=#{part_index}/#{part_count}'
    assert_includes source, 'snapshot0: complete tree='
    assert_includes source, '"STUDIO" => "STUDIO"'
    assert_includes source, '"OPENBSD" => "snapshot_OPENBSD.md"'
    assert_includes source, '" — git "'
    assert_includes source, 'git=#{sha}'
  end

  def test_snapshot_generator_declares_hard_share_size_ceiling
    source = File.read(File.expand_path("../tools/snapshot.rb", __dir__))
    assert_includes source, "MAX_BYTES = 750_000"
    assert_includes source, 'snapshot_#{tree}.partNNN.md'
    assert_includes source, "Rehydrate all parts into a fresh temporary repository-shaped directory"
    assert_includes source, "snapshot_extract.rb"
    assert_includes source, "omitted=0"
    assert_includes source, "SOURCE_FRAGMENT_BYTES = 600_000"
  end

  def test_snapshot_extractor_reassembles_fragments_and_rejects_mixed_packs
    Dir.mktmpdir do |dir|
      fence = "`" * 3
      heading1 = "## `MASTER/example.rb [fragment 1/2 bytes=6 newline=1]`"
      heading2 = "## `MASTER/example.rb [fragment 2/2 bytes=7 newline=1]`"
      part1 = File.join(dir, "snapshot_MASTER.md")
      part2 = File.join(dir, "snapshot_MASTER.part002.md")
      File.write(part1, ["# MASTER", "", "Pack: tree=MASTER git=abc123 part=1/2 text_total=1 fragments_total=2 binary=0 omitted=0", "", heading1, "", "#{fence}ruby", "first", fence, "", "## Snapshot part complete", ""].join("\n"))
      File.write(part2, ["# MASTER", "", "Pack: tree=MASTER git=abc123 part=2/2 text_total=1 fragments_total=2 binary=0 omitted=0", "", heading2, "", "#{fence}ruby", "second", fence, "", "## Snapshot part complete", ""].join("\n"))

      target = File.join(dir, "rehydrated")
      packs = [part1, part2].map { |path| Operator::SnapshotExtract.parse(path) }
      assert_equal 1, Operator::SnapshotExtract.write(packs, target)
      assert_equal "first\nsecond\n", File.read(File.join(target, "MASTER", "example.rb"))

      mismatched = Operator::SnapshotExtract.parse(part2).merge(git: "different")
      error = assert_raises(RuntimeError) do
        Operator::SnapshotExtract.write([packs.first, mismatched], File.join(dir, "bad"))
      end
      assert_includes error.message, "mixed git revisions"
    end
  end
  def test_snapshot_does_not_include_its_own_output
    Dir.mktmpdir do |dir|
      output = File.join(dir, "snapshot_MASTER.md")
      File.write(File.join(dir, "example.rb"), "puts :ok\n")
      Master::Snapshot.new(root: dir, output:).write!
      refute_includes File.read(output), "snapshot_MASTER.md" # source-assertion: ok — the snapshot write! just produced
    end
  end

  # The README promises one snapshot per governed tree from a bare /snapshot;
  # the command must use the same bounded generator as bin/operator.
  def test_bare_snapshot_command_uses_the_bounded_full_tree_generator
    source = File.read(File.expand_path("../lib/cli/command_registry.rb", __dir__))
    assert_includes source, "::Operator::Snapshot::TREES"
    assert_includes source, "::Operator::Snapshot.write(tree)"
    assert_includes source, "Array(::Operator::Snapshot.write(tree))"
    assert_includes source, "snapshot0: wrote root/"
    refute_includes source, "Master::Snapshot.new(root: Master::REPO_ROOT).write!"
    refute_includes source, "paths = Operator::Snapshot::TREES"
    refute_includes source, "Operator::Snapshot::MAX_BYTES)"
    refute_includes source, "paths = ::Operator::Snapshot::TREES.map"
  end

  def test_generated_snapshot_parts_are_ignored
    ignore = File.read(File.expand_path("../../.gitignore", __dir__))
    assert_includes ignore, "snapshot_*.md"
  end

  def test_operator_snapshot_runs_the_full_root_snapshot_pack
    source = File.read(File.expand_path("../bin/operator", __dir__))
    assert_equal 1, source.scan('when "snapshot"').size
    assert_includes source, 'MASTER/tools/snapshot.rb'
  end

  def test_snapshot_preserves_large_files_without_truncation
    Dir.mktmpdir do |dir|
      large = "0123456789abcdef" * 4_000
      File.write(File.join(dir, "large.txt"), large)
      output = File.join(dir, "snapshot.md")

      Master::Snapshot.new(root: dir, output:).write!

      text = File.read(output)
      assert_includes text, large
      assert_match(/## Snapshot complete|## Source/, text)
    end
  end

end
