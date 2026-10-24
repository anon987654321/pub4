# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/fix_loop"
require "fix/scanner"

# What the pass runner lends the stream, cut down: a repair that records the file it was handed.
module SemanticBudgetHarness
  def repair_file(path, *handed)
    @repairs << path
    StreamStage::STREAMED_LOCK.synchronize { handed.last.streamed << [handed[-2], "CHEAP"] }
    1
  end

  def resolve_violations(raw) = raw.map(&:to_h)
  def reload_due? = false
  def report_skip_breakdown(*, **); end
  def emit_topology(*); end
  def circuit_open? = false
  def llm_stage_resources_ok?(_pass) = true

  # Inside Master::ROOT, so the semantic answers are kept (FindingCache records repo-relative paths);
  # never written, since the processor is handed the text.
  def files(count = 6) = Array.new(count) { |n| File.join(Master::ROOT, "lib", "semantic_budget_probe_#{n}.rb") }

  def repaired = Array.new(@repairs.size) { @repairs.pop }.uniq

  def pass_semantic_budget = @budget.dup

  def from_now(seconds) = Time.at(Process.clock_gettime(Process::CLOCK_REALTIME) + seconds)

  StreamStage = Master::Fix::FixLoop::PassRunner::StreamStage
end

# A requested /fix shares one model lane between the semantic reads and the repairs. Read inline,
# a minute and a half a file, the reads filled the pass and no file was ever repaired. The stream
# now reads the corpus mechanically, queues every cheap finding for repair, and then makes a
# budget's worth of the reads it put off; later passes read the rest.
class TestSemanticBudget < Minitest::Test
  include Master::Fix::FixLoop::PassRunner::StreamStage
  include SemanticBudgetHarness

  Finding = Master::Review::Scan::Finding
  Budget = Master::Fix::FixLoop::PassRunner::StreamStage::SemanticBudget
  Rule = Struct.new(:id)
  CODE = "x = 1\n"

  # A cheap finding on every file, so every file is due a semantic read and a repair.
  class CheapLaw
    def self.reads_beyond_file? = false
    def id = "CHEAP"
    def check(_code, path:) = [Finding.build(law: "CHEAP", message: "cheap #{File.basename(path)}", line: 1)]
  end

  # The model tier, slow as a lane is.
  class SlowModel
    attr_reader :calls

    def self.reads_beyond_file? = true

    def initialize(delay)
      @delay = delay
      @calls = []
    end

    def id = "MODEL"
    def set_agent(_agent) = nil

    def check(_code, path:)
      sleep @delay
      @calls << path
      [Finding.build(law: "MODEL", message: "drift in #{File.basename(path)}", line: 2)]
    end
  end

  class NullCommitter
    def commit_if_dirty(*, **) = nil
  end

  LawOrder = Struct.new(:rules) do
    def ordered(violation_counts:) = rules
  end

  def setup
    @root = Dir.mktmpdir("semantic-budget")
    @cache_was = ENV.fetch("MASTER_SCAN_CACHE", nil)
    ENV["MASTER_SCAN_CACHE"] = "1"
    @model = SlowModel.new(0.4)
    @processor = Master::Fix::Scan::FileProcessor.new(cache_root: @root)
    @scan_phase = Master::Fix::ScanPhase.new(scanner: @processor, root: @root)

    @committer = NullCommitter.new
    @law_order = LawOrder.new([Rule.new("CHEAP")])
    @violation_counts = Hash.new(0)
    @repairs = Queue.new
    @budget = Budget.new(2, 60, 0, 0.0)
  end

  def teardown
    @cache_was.nil? ? ENV.delete("MASTER_SCAN_CACHE") : ENV["MASTER_SCAN_CACHE"] = @cache_was
    FileUtils.remove_entry(@root)
  end

  def test_every_cheap_finding_is_repaired_before_the_deadline_however_slow_the_model
    corpus = files
    found, = streaming_observation(corpus, @root, 1, from_now(1.5))

    assert_equal corpus.sort, repaired.sort, "the model reads must not hold the repairs past the deadline"
    assert_equal 2, @model.calls.size, "the pass reads only its budget's worth"
    assert_equal 2, found.count { |row| row[:law] == "MODEL" }
  end

  def test_the_seconds_budget_stops_the_reads_too
    @budget = Budget.new(10, 0.5, 0, 0.0)
    streaming_observation(files, @root, 1, from_now(30))

    assert_equal 2, @model.calls.size
  end

  def test_preview_reads_only_its_semantic_budget_and_does_not_advance_the_cursor
    corpus = files

    found = preview_violations(corpus)

    assert_equal 2, @model.calls.size, "preview must obey the same bounded read allowance"
    assert_equal 4, semantic_pending.size, "unread semantic files must be visible as pending"
    assert_equal 2, found.count { |row| row[:law] == "MODEL" }
    refute File.exist?(Master::Fix::FixLoop::StreamCursor.file(@root)),
           "a read-only preview must not advance the persistent semantic cursor"
  end

  def test_later_passes_read_what_earlier_ones_left_and_every_file_is_read_once
    corpus = files
    streaming_observation(corpus, @root, 1, from_now(30))
    assert_equal 4, semantic_pending.size

    2.times { |n| streaming_observation(corpus, @root, n + 2, from_now(30)) }

    assert_equal corpus.sort, @model.calls.sort
    assert_empty semantic_pending
  end

  def test_the_order_resumes_past_the_last_file_read_and_wraps
    paths = %w[a.rb b.rb c.rb d.rb].map { |name| File.join(@root, name) }
    Master::Fix::FixLoop::StreamCursor.mark_semantic(@root, paths[2])

    order = Master::Fix::FixLoop::StreamCursor.semantic_order(@root, paths.reverse)

    assert_equal [paths[3], paths[0], paths[1], paths[2]], order
  end

  def test_another_thread_still_reads_inline_while_the_scan_defers
    put_off = []
    other = nil
    @processor.deferring_semantic(put_off) do
      other = Thread.new { scan(files(1).first) }.value
    end

    assert_empty put_off
    assert_includes other.map { |finding| finding[:law] }, "MODEL"
  end

  private

  def scan(path) = @processor.apply_laws(code: CODE, ast: nil, path:, law_set: [CheapLaw.new, @model])

  def violations_for(path)
    scan(path).map do |finding|
      { law: finding[:law], line: finding[:line], message: finding[:message], severity: :warning, file: path }
    end
  end
end
