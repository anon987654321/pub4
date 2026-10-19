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
        { law: "LONG_METHOD", file: File.basename(path), line: 1, message: "long" },
        { law: "DRY", file: File.basename(path), line: 2, message: "dry" },
      ]
    end
  end

  class RepairAwareScanner
    def initialize(repaired) = @repaired = repaired

    def scan(path)
      return [] if @repaired[path]

      [{ law: "LONG_METHOD", file: File.basename(path), line: 1, message: "long" }]
    end
  end

  class NullCommitter
    attr_reader :commits

    def initialize = @commits = []
    def commit_if_dirty(message, **) = @commits << message
  end

  LawOrder = Struct.new(:rules) do
    def ordered(violation_counts:) = rules
  end

  # No origin to ask in a unit test.
  def reload_due? = false

  # The conflict resolver is not under test; rows pass through as hashes.
  def resolve_violations(raw) = raw.map(&:to_h)

  # An unbounded run ranks its worklist after the whole scan by default (MASTER_FIX_RANK). Overlapping the
  # scan with repairs is the mode MASTER_FIX_RANK=0 selects, and these two tests describe that mode.
  OVERLAPPING = /start_before|duplication_waits/

  def setup
    @root = "/repo"
    @events = Queue.new
    @log = []
    @loop_scanner = GatedScanner.new(@events)
    @repair_state = nil
    @scan_index = 0
    @committer = NullCommitter.new
    @law_order = LawOrder.new([Rule.new("LONG_METHOD"), Rule.new("DRY")])
    @violation_counts = Hash.new(0)
    @rank_before = ENV["MASTER_FIX_RANK"]
    ENV["MASTER_FIX_RANK"] = "0" if name.match?(OVERLAPPING)
  end

  def teardown
    ENV.delete("MASTER_FIX_RANK")
    ENV["MASTER_FIX_RANK"] = @rank_before if @rank_before
    FileUtils.remove_entry(@temporary_path) if @temporary_path
  end

  def test_repairs_start_before_the_scan_finishes
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    assert_equal 6, found.size, "the pass still sees every finding"
    # Three workers finish in any order; what matters is that all three ran.
    assert_equal %w[/repo/a.rb /repo/b.rb /repo/c.rb], @log.sort
    assert_includes streamed, ["a.rb", "LONG_METHOD"]
    assert_equal ["fix_loop: stream-fix [pass 1]"], @committer.commits
    assert_equal true, @pass_progress
  end

  def test_duplication_waits_for_the_whole_scan
    found, streamed = streaming_observation(%w[/repo/a.rb /repo/b.rb /repo/c.rb], "/repo", 1, Time.now + 60)

    refute(streamed.any? { |_file, rule| rule == "DRY" })
    assert_equal 3, unstreamed(found, streamed).size
    assert(unstreamed(found, streamed).all? { |row| row[:law] == "DRY" })
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

  def test_a_repair_context_is_complete_when_the_graph_knows_the_target
    Dir.mktmpdir do |root|
      path = File.join(root, "target.rb")
      File.write(path, "x = 1\n")
      @reference_graph = FakeGraph.new(root)

      context = repair_context(path)

      assert context[:complete], context[:reason]
      assert_equal root, context[:context_root]
      assert_equal Digest::SHA256.hexdigest("x = 1\n"), context[:target_sha256]
    end
  end

  def test_callers_the_graph_cannot_see_lock_the_interface_without_refusing_the_repair
    graph = graph_with(inbound: ["caller.rb"], dynamic: { "caller.rb" => "public_send" })

    context = repair_context_for(graph)

    assert context[:complete], context[:reason]
    assert context[:interface_locked]
    assert_match(/dynamic public_send at caller.rb:1/, context[:lock_reasons].first)
  end

  def test_define_method_in_a_caller_and_a_dynamic_call_in_a_dependency_do_not_lock
    graph = graph_with(inbound: ["caller.rb"], outbound: ["dependency.rb"],
                       dynamic: { "caller.rb" => "define_method", "dependency.rb" => "send" })

    context = repair_context_for(graph)

    assert context[:complete], context[:reason]
    refute context[:interface_locked], context[:lock_reasons].inspect
  end

  private

  def run_law_once(rule, files, _pass)
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

  def temporary_path = @temporary_path ||= Dir.mktmpdir

  # A FakeGraph over real files: the target, its callers and its dependencies, and the dynamic call
  # (file => method name) each reports.
  def graph_with(inbound: [], outbound: [], dynamic: {})
    (["target.rb"] + inbound + outbound).each { |name| File.write(File.join(temporary_path, name), "x = 1\n") }
    sites = dynamic.to_h { |file, name| [file, [{ file:, line: 1, name: }]] }

    FakeGraph.new(temporary_path).tap do |graph|
      graph.define_singleton_method(:blast_radius) { |_path| { inbound:, outbound: } }
      graph.define_singleton_method(:dynamic_for) { |file| sites.fetch(File.basename(file), []) }
    end
  end

  def repair_context_for(graph)
    @reference_graph = graph
    repair_context(File.join(temporary_path, "target.rb"))
  end

  # A requested /fix gives every repair a complete context from the dependency graph; an
  # undefined name inside it was rescued into "context incomplete" and sent each file to
  # HUMAN_DECISION, so nothing was ever repaired.
  FakeGraph = Struct.new(:root) do
    def includes_path?(_path) = true
    def source_digest(path) = Digest::SHA256.hexdigest(File.read(path, encoding: "UTF-8"))
    def relative(path) = path.delete_prefix("#{root}/")
    def blast_radius(_path) = { inbound: [], outbound: [] }
    def dynamic_for(_path) = []
    def unresolved_for(_path) = []
  end
end
