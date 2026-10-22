# frozen_string_literal: true

require_relative "test_helper"

# A requested /fix reads a rotating tenth of the clean files semantically, so every file is read
# once across ten days and no run reads them all.
class TestSemanticRotation < Minitest::Test
  # A processor pinned to one day and one sample rate.
  class OnDay < Master::Fix::Scan::FileProcessor
    def on(day) = tap { @day = day }

    def rotation_day = @day
    def semantic_sample = 0.1
    def due?(path, findings: []) = semantic_due?(findings, path)
  end

  def test_ten_days_read_every_file_exactly_once
    paths = Array.new(200) { |n| "lib/file_#{n}.rb" }

    reads = (1..10).flat_map do |day|
      processor = OnDay.new.on(day)
      paths.select { |path| processor.due?(path) }
    end

    assert_equal paths.sort, reads.sort
  end

  def test_a_file_with_a_finding_is_always_read
    processor = OnDay.new.on(1)
    paths = Array.new(50) { |n| "lib/f#{n}.rb" }

    assert(paths.all? { |path| processor.due?(path, findings: [{ law: "CQS" }]) })
  end
end
