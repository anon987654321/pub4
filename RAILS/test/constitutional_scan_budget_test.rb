# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../gates/lib/meta/constitutional_scan"

# The gate ran four full MASTER scans — twenty-one minutes — and routed every
# finding to result.warn, failing only when the output matched a crash marker. It
# could not go red on the findings it existed to measure. It now compares each
# target against a recorded ceiling that only ratchets down.
#
# These tests never run a scan. That is the point: the ceiling and the parse have
# to be assertable in milliseconds, or nobody will touch them.
class ConstitutionalScanBudgetTest < Minitest::Test
  def gate = Deploy::ConstitutionalScanGate.new(targets: [])

  def test_budget_covers_every_default_target
    targets = Deploy::ConstitutionalScanGate.new.targets.map { |path| File.basename(path) }

    assert_equal targets.sort, gate.budget.keys.sort
    gate.budget.each_value { |ceiling| assert_kind_of Integer, ceiling }
  end

  # The marker grep used to run before the count was read, over the whole output,
  # so a finding that quoted one of the markers made a completed scan report as a
  # crash. amber failed this gate that way on 2026-08-03 having scanned to 79-plus
  # findings. A run that printed its count did not crash, whatever it found.
  def test_a_finding_that_quotes_a_crash_marker_is_not_a_crash
    output = <<~OUT
      lib/thing.rb:4 [DEAD_CODE] rescue swallows uninitialized constant Foo
      No such file or directory is the message this branch builds
      scan: done [profile: full] 207 violations | top DEAD_CODE=48
      79 more violation(s) omitted
    OUT

    assert_equal "207", output[Deploy::ConstitutionalScanGate::VIOLATION_LINE, 1]
  end

# The other spelling of the same number. A count regex that only knows digits
# skipped the clean line and matched the NEXT `scan: done`, which is the deep
# pass — so a target whose aesthetic pass is clean was judged on a different
# profile than one whose aesthetic pass found something. STUDIO read 317 and
# OPENBSD 72 against ceilings measured at 0 in the same run that printed
# "clean".
def test_a_clean_first_pass_counts_as_zero_not_as_the_next_pass
  gate = Deploy::ConstitutionalScanGate.allocate
  output = <<~OUT
    scan: done dry-run: [profile: aesthetic] clean -- no violations (no changes made)
    scan: done dry-run: [profile: full] 317 violations | top FEATURE_ENVY=70
  OUT

  assert_equal 0, gate.send(:first_pass_count, output)
end

def test_the_first_pass_is_the_one_judged
  gate = Deploy::ConstitutionalScanGate.allocate
  output = <<~OUT
    scan: done dry-run: [profile: aesthetic] 6 violations | top EIGHT_PX_RHYTHM=4
    scan: done dry-run: [profile: full] 60 violations | top FILE_SPRAWL=12
  OUT

  assert_equal 6, gate.send(:first_pass_count, output)
end

# No count at all is the third state, and it must stay distinguishable from
# zero: one is a clean scan, the other is a scan that did not run.
def test_no_scan_line_is_nil_rather_than_zero
  gate = Deploy::ConstitutionalScanGate.allocate

  assert_nil gate.send(:first_pass_count, "boom: LoadError\n")
end

  # The rewrite matched the entries as a block directly under `targets:`, which
  # every comment in that file breaks. It wrote nothing and announced the new
  # numbers anyway. Assert against the real file's shape, comments included.
  def test_ratchet_rewrites_a_commented_budget_file
    original = File.read(Deploy::ConstitutionalScanGate::BUDGET_PATH)
    scan = Deploy::ConstitutionalScanGate.new(targets: [])
    lowered = scan.budget.transform_values { |ceiling| ceiling - 1 }
    scan.instance_variable_set(:@measured, lowered)

    with_env("GATE_SCAN_RATCHET", "1") { scan.send(:maybe_ratchet) }
    written = YAML.safe_load_file(Deploy::ConstitutionalScanGate::BUDGET_PATH).fetch("targets")

    assert_equal lowered, written, "the ratchet reported a write it did not make"

    # The comments are the whole reason this file cannot be rewritten as a
    # block, so what to assert is that they survived. The line here looked for
    # "# RATCHETED", which nothing in the tree writes — a marker invented by the
    # assertion, failing against a rewrite that is doing its job.
    after = File.read(Deploy::ConstitutionalScanGate::BUDGET_PATH)
    comments = original.lines.grep(/\A\s*#/).map(&:strip).reject(&:empty?)

    refute_empty comments, "the fixture stopped being a commented file"
    comments.each { |line| assert_includes after, line, "the rewrite ate a comment: #{line}" }
  ensure
    File.write(Deploy::ConstitutionalScanGate::BUDGET_PATH, original)
  end

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end

  def test_counts_come_out_of_the_scan_line
    line = "scan: done [profile: full] 410 violations | top DEAD_CODE=99 CONFIG_HIERARCHY=70"

    assert_equal "410", line[Deploy::ConstitutionalScanGate::VIOLATION_LINE, 1]
  end

  # pass1 prints the same count on its own line; only `done` is authoritative.
  def test_the_pass1_line_is_not_mistaken_for_the_result
    assert_nil "scan: pass1 [profile: full] 999 violations"[Deploy::ConstitutionalScanGate::VIOLATION_LINE, 1]
  end

  def test_over_ceiling_fails
    g = gate
    g.judge_count("brgen", g.budget.fetch("brgen") + 1)

    assert_equal 1, g.instance_variable_get(:@result).failures.size
    assert_includes g.instance_variable_get(:@result).failures.first, "exceeds ceiling"
  end

  def test_at_ceiling_passes
    g = gate
    g.judge_count("brgen", g.budget.fetch("brgen"))

    assert_empty g.instance_variable_get(:@result).failures
  end

  def test_under_ceiling_passes_and_says_so
    g = gate
    g.judge_count("brgen", g.budget.fetch("brgen") - 7)
    result = g.instance_variable_get(:@result)

    assert_empty result.failures
    assert(result.warnings.any? { |w| w.include?("GATE_SCAN_RATCHET") })
  end

  def test_an_unbudgeted_target_warns_rather_than_failing_silently
    g = gate
    g.judge_count("newapp", 12)
    result = g.instance_variable_get(:@result)

    assert_empty result.failures
    assert(result.warnings.any? { |w| w.include?("no ceiling") })
  end

  def test_the_gate_is_wired_into_check_rails
    source = File.read(File.expand_path("../../OPENBSD/bin/check-rails", __dir__))

    assert_includes source, "constitutional_scan"
    assert_includes source, "DEPLOY_DEEP_CHECK_TIMEOUT"
  end
end
