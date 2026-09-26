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

    def scan(path, index)
      @repaired.pop(timeout: 5) || raise("no repair started while the scan ran") if index == 2
      [
        { rule: "LONG_METHOD", file: File.basename(path), line: 1, message: "long" },
        { rule: "DRY", file: File.basename(path), line: 2, message: "dry" }
      ]
    end
  end

  class RepairAwareScanner
    def initialize(repaired) = @repaired = repaired

    def scan(path)
      return [] if @repaired[path]

      [{ rule: "LONG_METHOD", file: File.basename(path), line: 1, message: "long" }]
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

  # No origin to ask in a unit test.
  def reload_due? = false

  def setup
    @root = "/repo"
    @events = Queue.new
    @log = []
    @loop_scanner = GatedScanner.new(@events)
    @repair_state = nil
    @scan_index = 0
    @committer = NullCommitter.new
    @rule_order = RuleOrder.new([Rule.new("LONG_METHOD"), Rule.new("DRY")])
    @violation_counts = Hash.new(0)
  end

  def test_repairs_start_before_the_scan_finishes
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    assert_equal 6, found.size, "the pass still sees every finding"
    # Three workers finish in any order; what matters is that all three ran.
    assert_equal %w[/repo/a.rb /repo/b.rb /repo/c.rb], @log.sort
    assert_includes streamed, ["a.rb", "LONG_METHOD"]
    assert_equal ["fix_loop: stream-fix [pass 1]"], @committer.commits
  end

  def test_duplication_waits_for_the_whole_scan
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    refute(streamed.any? { |_file, rule| rule == "DRY" })
    assert_equal 3, unstreamed(found, streamed).size
    assert(unstreamed(found, streamed).all? { |row| row[:rule] == "DRY" })
  end

  def test_findings_are_refreshed_after_a_stream_repair
    @repair_state = {}
    @loop_scanner = RepairAwareScanner.new(@repair_state)
    found, streamed = streaming_observation(%w[/repo/a.rb], "/repo", 1, Time.now + 60)

    assert_empty found
    assert_includes streamed, ["a.rb", "LONG_METHOD"]
    assert_equal ["fix_loop: stream-fix [pass 1]"], @committer.commits
  end

  def test_no_repair_after_the_deadline
    @events << :go
    @events << :go
    streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now - 1)

    assert_empty @log
    assert_empty @committer.commits
  end

  # The next run starts at the first file this one's budget left unrepaired.
  def test_the_stream_marks_where_its_budget_ran_out
    Dir.mktmpdir do |root|
      @root = root
      @events << :go
      @events << :go
      files = %w[a.rb b.rb c.rb].map { |name| File.join(root, name) }
      streaming_observation(files, root, 1, Time.now - 1)

      assert_equal files, Master::Fix::FixLoop::StreamCursor.order(root, root, files.rotate(1))
    end
  end

  private

  def run_rule_once(rule, files, _pass)
    @log.concat(files) if rule.id == "LONG_METHOD"
    @repair_state[files.first] = true if @repair_state
    @events << :repaired
    { fixed: 1, status: :applied }
  end

  def violations_for(path)
    index = @scan_index
    @scan_index += 1
    rows = @loop_scanner.is_a?(GatedScanner) ? @loop_scanner.scan(path, index) : @loop_scanner.scan(path)
    rows.map { |row| row.merge(severity: :warning) }
  end

  def run_observation_stage(files, _target) = files.flat_map { |path| violations_for(path) }
  # These tests pin when repairs start, not how a file is repaired.
  def repair_file(path, _rows, runnable, rel, stream) = run_streamed_rules(runnable, path, rel, stream)
  def tally_rule_results(results, **) = results.sum { |_rule, result| result[:fixed] }
  def report_skip_breakdown(*, **); end
  def emit_topology(*); end
  def circuit_open? = false
  def llm_stage_resources_ok?(_pass) = true
end
