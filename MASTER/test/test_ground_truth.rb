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
