# frozen_string_literal: true

require_relative "test_helper"

class TestGroundTruth < Minitest::Test
  def test_records_and_asserts_fresh_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::GroundTruth.new(max_age_seconds: 60)
      gt.record_read!(path)
      assert gt.fresh?(path)
      stale = gt.assert_fresh!(path, reason: "claim_task_complete")
      assert stale.ok?
    end
  end

  # The read hash is the version a whole-file write was composed against, so a
  # file somebody changed afterwards is refused and a reread lets it through.
  def test_write_file_refuses_a_file_changed_since_it_was_read
    Dir.mktmpdir do |dir|
      gt = Master::Ground::GroundTruth.new(max_age_seconds: 60)
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      reader = Master::Io::ReadFile.new(root: dir, undo:, ground_truth: gt)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: gt)
      File.write(File.join(dir, "notes.txt"), "mine\n")

      reader.call(path: "notes.txt")
      assert writer.call(path: "notes.txt", content: "first\n").ok?, "a write after a read goes through"
      assert writer.call(path: "notes.txt", content: "second\n").ok?, "its own write does not make the file stale"

      File.write(File.join(dir, "notes.txt"), "theirs\n")
      refused = writer.call(path: "notes.txt", content: "third\n")
      assert_match(/changed since it was read/, refused.message.to_s)
      assert_equal "theirs\n", File.read(File.join(dir, "notes.txt"))

      reader.call(path: "notes.txt")
      assert writer.call(path: "notes.txt", content: "third\n").ok?, "a reread, even from the turn cache, clears it"
      assert writer.call(path: "fresh.txt", content: "new\n").ok?, "a file never read is not stale"
    end
  end

  def test_stale_without_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::GroundTruth.new(max_age_seconds: 60)
      refute gt.fresh?(path)
      result = gt.assert_fresh!(path)
      assert result.err?
    end
  end
end
