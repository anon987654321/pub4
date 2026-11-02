# frozen_string_literal: true

require_relative "test_helper"
require "digest"

class TestGroundTruth < Minitest::Test
  # laws.yml has no ground_truth_check key, so the default window must be positive
  # or every read is stale the moment it is recorded.
  def test_default_window_keeps_a_just_read_file_fresh
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new
      gt.record_read!(path)
      assert gt.fresh?(path)
    end
  end

  def test_records_and_asserts_fresh_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
      gt.record_read!(path)
      assert gt.fresh?(path)
      stale = gt.assert_fresh!(path, reason: "claim_task_complete")
      assert stale.ok?
    end
  end

  def test_reads_from_an_earlier_turn_remain_fresh_but_cannot_authorize_current_turn_writes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new(max_age_seconds: 60)

      truth.record_read!(path)
      assert truth.fresh?(path)
      assert truth.fresh_in_current_turn?(path)
      previous_turn = truth.current_turn_id

      truth.begin_turn!

      assert_equal previous_turn + 1, truth.current_turn_id
      assert truth.fresh?(path), "age/content freshness remains available to non-write checks"
      refute truth.fresh_in_current_turn?(path), "a prior turn cannot authorize a replacement"
    end
  end

  def test_read_file_shows_the_whole_file_digest_for_a_bounded_slice
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.rb")
      content = (1..8).map { |line| "line #{line}\n" }.join
      File.write(path, content)
      truth = Master::Ground::Truth.new
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      result = reader.call(path: "source.rb", offset: 2, limit: 2)

      assert result.ok?, result.to_s
      assert_includes result.value!, "3\tline 3"
      assert_includes result.value!, "4\tline 4"
      refute_includes result.value!, "2\tline 2"
      assert_includes result.value!, "sha256=#{Digest::SHA256.hexdigest(content)}"
      assert_includes result.value!, "bytes=#{content.bytesize} lines=8 shown=2 offset=2 scope=whole_file"
      assert truth.fresh?(path)
    end
  end

  def test_read_file_refreshes_an_expired_cached_receipt
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      truth = Master::Ground::Truth.new(max_age_seconds: -1, event_bus: bus)
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      first = reader.call(path: "source.rb")
      second = reader.call(path: "source.rb")

      assert first.ok?
      assert second.ok?
      assert_equal 2, events.count { |event, _| event == "ground_truth:read" }
    end
  end

  def test_read_file_refreshes_a_cached_receipt_at_the_start_of_a_new_turn
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      truth = Master::Ground::Truth.new(event_bus: bus)
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      first = reader.call(path: "source.rb")
      truth.begin_turn!
      second = reader.call(path: "source.rb")

      assert first.ok?
      assert second.ok?
      assert_equal 2, events.count { |event, _| event == "ground_truth:read" }
      assert truth.fresh_in_current_turn?(File.join(dir, "source.rb"))
    end
  end

  def test_read_file_does_not_report_success_when_ground_truth_receipt_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      truth = Object.new
      truth.define_singleton_method(:record_read!) { |*| nil }
      truth.define_singleton_method(:changed_since_read?) { |_| false }
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      result = reader.call(path: "source.rb")

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_match(/receipt could not be recorded/, result.message)
    end
  end

  # The read hash is the version a whole-file write was composed against, so a
  # file somebody changed afterwards is refused and a reread lets it through.
  def test_write_file_refuses_a_file_changed_since_it_was_read
    Dir.mktmpdir do |dir|
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
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

  def test_write_file_refuses_a_read_from_the_previous_turn
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new(max_age_seconds: 60)
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      reader = Master::Io::ReadFile.new(root: dir, undo:, ground_truth: truth)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: truth)

      assert reader.call(path: "existing.txt").ok?
      truth.begin_turn!
      result = writer.call(path: "existing.txt", content: "replacement\n")

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/must be read in this turn/, result.message)
      assert_equal "original\n", File.read(path)
    end
  end

  def test_write_file_refuses_to_overwrite_an_existing_file_without_a_fresh_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: truth)

      result = writer.call(path: "existing.txt", content: "replacement\n")

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/must be read in this turn/, result.message)
      assert_equal "original\n", File.read(path)
    end
  end

  def test_stale_without_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
      refute gt.fresh?(path)
      result = gt.assert_fresh!(path)
      assert result.err?
    end
  end
end
