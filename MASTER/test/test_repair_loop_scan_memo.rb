# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# A repaired file is scanned once per distinct content, not once per question asked of it.
class TestRepairLoopScanMemo < Minitest::Test
  # Counts scans and reports one finding per scan.
  class CountingScanner
    attr_reader :scans

    def initialize = @scans = 0

    def scan(path)
      @scans += 1
      Master::Result.ok([{ law: "CQS", file: path, line: 1 }])
    end
  end

  # A repair loop whose only collaborator is the scanner.
  class Loop < Master::Fix::RepairLoop
    def initialize(scanner) = @scanner = scanner
    def scan(path) = scan_all(path)
  end

  def test_identical_bytes_are_scanned_once_and_an_edit_scans_again
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      scanner = CountingScanner.new
      loop = Loop.new(scanner)

      2.times { loop.scan(path) }
      File.write(path, "A = 2\n")
      loop.scan(path)

      assert_equal 2, scanner.scans
    end
  end
end
