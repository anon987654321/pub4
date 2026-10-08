# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "test_helper"

class TestFixCorpus < Minitest::Test
  def test_the_tree_is_written_before_every_other_file_is_read
    Dir.mktmpdir("fix_corpus") do |root|
      File.write(File.join(root, "keep.rb"), "puts :ok\n")
      FileUtils.mkdir_p(File.join(root, ".git", "objects"))
      File.write(File.join(root, ".git", "objects", "pack"), "secret\n")
      FileUtils.mkdir_p(File.join(root, "vendor", "gem"))
      File.write(File.join(root, "vendor", "gem", "dep.rb"), "dep\n")
      FileUtils.mkdir_p(File.join(root, "temp"))
      File.write(File.join(root, "temp", "scratch.txt"), "scratch\n")
      FileUtils.mkdir_p(File.join(root, "git"))
      File.write(File.join(root, "git", "note.txt"), "note\n")
      File.write(File.join(root, ".env"), "TOKEN=1\n")

      result = Master::Fix::Corpus.establish(root)
      tree = File.read(result.tree_path)

      assert result.ok?
      assert_equal [File.join(root, "keep.rb")], result.files
      assert_equal File.size(File.join(root, "keep.rb")), result.bytes
      assert_equal Digest::SHA256.file(File.join(root, "keep.rb")).hexdigest, result.digest(result.files.first)
      assert_includes tree, "keep.rb"
      refute_includes tree, "dep.rb"
      refute_includes tree, "scratch.txt"
      refute_includes tree, "note.txt"
      refute_includes tree, ".env"
    end
  end

  def test_a_directory_without_audio_is_left_untouched
    Dir.mktmpdir("auditory") do |dir|
      File.write(File.join(dir, "note.rb"), "puts :ok\n")
      before = Dir.children(dir).sort
      pass = Master::Fix::AuditoryPass.new(root: dir)
      result = pass.run(target: dir)

      assert result.ok?
      assert_equal :no_audio, result.value![:state]
      assert_empty result.value![:findings]
      assert_equal before, Dir.children(dir).sort
    end
  end

  def test_a_writing_fix_asks_every_clean_file_and_a_skip_still_wins
    processor = Master::Fix::Scan::FileProcessor.new
    processor.ask_every_rule!
    assert processor.send(:semantic_due?, [], "lib/fix/protocol.rb")
    processor.skip_semantic!
    refute processor.send(:semantic_due?, [], "lib/fix/protocol.rb")
  end
end
