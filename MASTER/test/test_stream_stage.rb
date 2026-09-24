# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop"

# The pass runner's collaborators, cut down to what streaming touches: a
# scanner that yields file by file, and a repair that records when it ran.
class StreamStageTest < Minitest::Test
  include Master::Fix::FixLoop::PassRunner::StreamStage

  Rule = Struct.new(:id)

  # Scans three files. The third is not read until the first has been
  # repaired, so a runner that waits for the whole scan never gets there.
  class GatedScanner
    def initialize(repaired) = @repaired = repaired

    def violations(files)
      files.each_with_index.flat_map do |path, index|
        @repaired.pop(timeout: 5) || raise("no repair started while the scan ran") if index == 2
        rows = [{ rule: "LONG_METHOD", file: File.basename(path) }, { rule: "DRY", file: File.basename(path) }]
        yield path, rows if block_given?
        rows
      end
    end
  end

  class NullCommitter
    attr_reader :commits

    def initialize = @commits = []
    def commit_if_dirty(message, **) = @commits << message
  end

  RuleOrder = Struct.new(:rules) do
    def ordered(violation_counts:) = rules
  end

  def setup
    @root = "/repo"
    @events = Queue.new
    @log = []
    @loop_scanner = GatedScanner.new(@events)
    @committer = NullCommitter.new
    @rule_order = RuleOrder.new([Rule.new("LONG_METHOD"), Rule.new("DRY")])
    @violation_counts = Hash.new(0)
  end

  def test_repairs_start_before_the_scan_finishes
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    assert_equal 6, found.size, "the pass still sees every finding"
    assert_equal %w[/repo/a.rb /repo/b.rb /repo/c.rb], @log
    assert_includes streamed, ["a.rb", "LONG_METHOD"]
    assert_equal ["fix_loop: stream-fix [pass 1]"], @committer.commits
  end

  def test_duplication_waits_for_the_whole_scan
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    refute(streamed.any? { |_file, rule| rule == "DRY" })
    assert_equal 3, unstreamed(found, streamed).size
    assert(unstreamed(found, streamed).all? { |row| row[:rule] == "DRY" })
  end

  def test_no_repair_after_the_deadline
    @events << :go
    @events << :go
    streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now - 1)

    assert_empty @log
    assert_empty @committer.commits
  end

  private

  def run_rule_once(rule, files, _pass)
    @log.concat(files) if rule.id == "LONG_METHOD"
    @events << :repaired
    { fixed: 1, status: :applied }
  end

  def run_observation_stage(files, _target) = @loop_scanner.violations(files)
  def tally_rule_results(results, **) = results.sum { |_rule, result| result[:fixed] }
  def report_skip_breakdown(*, **); end
  def emit_topology(*); end
  def circuit_open? = false
  def llm_stage_resources_ok?(_pass) = true
end
