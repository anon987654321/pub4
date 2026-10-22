# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fix/scanner"

class TestFindingCache < Minitest::Test
  Finding = Master::Review::Scan::Finding

  class PureLaw
    def self.reads_beyond_file? = false
    def id = "PURE"
  end

  class SiblingLaw
    def self.reads_beyond_file? = true
    def id = "SIBLINGS"
  end

  def setup
    @dir = Dir.mktmpdir
    @was = ENV.fetch("MASTER_SCAN_CACHE", nil)
    ENV["MASTER_SCAN_CACHE"] = "1"
  end

  def teardown
    @was.nil? ? ENV.delete("MASTER_SCAN_CACHE") : ENV["MASTER_SCAN_CACHE"] = @was
    FileUtils.remove_entry(@dir)
  end

  def cache = Master::Fix::Scan::FindingCache.new(root: @dir)

  def finding(line)
    Finding.build(law: "PURE", message: "m#{line}", line:, severity: :error, tags: %i[STYLE],
                  impact_radius: { files_touched: 2 })
  end

  def fetch(code, laws: [PureLaw.new], calls: [])
    cache.fetch("a.rb", code:, laws:, ast: nil) do
      calls << code
      [finding(calls.size), { law: :PURE, line: 9, tags: [:X] }]
    end
  end

  def test_unchanged_content_replays_without_running_the_laws
    calls = []
    first = fetch("x = 1\n", calls:)
    second = fetch("x = 1\n", calls:)

    assert_equal 1, calls.size
    assert_equal first, second
  end

  # Symbols and Finding survive the trip, or a replayed finding matches no reader.
  def test_the_replay_keeps_findings_and_symbols
    fetch("x = 1\n")
    replayed = fetch("x = 1\n")

    assert_kind_of Finding, replayed.first
    assert_equal :error, replayed.first.severity
    assert_equal({ files_touched: 2 }, replayed.first.impact_radius)
    assert_equal({ law: :PURE, line: 9, tags: [:X] }, replayed.last)
  end

  def test_changed_content_or_laws_run_again
    calls = []
    fetch("x = 1\n", calls:)
    fetch("x = 2\n", calls:)
    fetch("x = 2\n", laws: [PureLaw.new, PureLaw.new.tap { |law| def law.id = "OTHER" }], calls:)

    assert_equal 3, calls.size
  end

  def test_a_law_that_reads_beyond_the_file_is_never_replayed
    refute cache.cacheable?(SiblingLaw.new)
    assert cache.cacheable?(PureLaw.new)
  end

  def test_switched_off_it_always_runs
    ENV["MASTER_SCAN_CACHE"] = "0"
    calls = []
    2.times { fetch("x = 1\n", calls:) }

    assert_equal 2, calls.size
  end
end
