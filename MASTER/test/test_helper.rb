# frozen_string_literal: true

ENV["MT_NO_PLUGINS"] = "1"
ENV["MASTER_TTS_MODE"] = "classic"
# The pool's live probes sign-in-check CLIs, ask OpenRouter for a balance and
# knock on local server ports; a suite that did so would grade this machine.
ENV["MASTER_NO_POOL_PROBES"] = "1"
# The suite is the proof: a test that drives a writing /fix pass must not start
# the whole suite again from inside it.
ENV["MASTER_IN_PROOF"] = "1"
# A proof baseline kept on disk by a test would be reused by a real run on the same tree.
ENV["MASTER_PROOF_STORE"] = "0"
# A test run must not leave the next real /fix a residual to resume from.
require "tmpdir"
ENV["MASTER_FIX_RESIDUAL"] = File.join(Dir.tmpdir, "master-test-residual-#{Process.pid}.json")
# Scripted CDP doubles answer only the verbs a test names; stress states and
# extra engines are exercised by their own tests, which switch them on.
ENV["MASTER_VISUAL_STRESS"] = "0"
ENV["MASTER_VISUAL_ENGINES"] = "chrome"
# /fix tries its own instruments (disk, git, patch, linters) before the first file. Tests of the loop run on
# scratch directories and stubbed models; the instrument check has its own test, which switches it back on.
ENV["MASTER_FIX_INSTRUMENT_CHECK"] = "0"
# A test that counts a law's calls must see the law run; the finding cache has its own test.
ENV["MASTER_SCAN_CACHE"] = "0"
# A test whose narrator speaks started the bard's music bed through the speakers, mid-suite.
ENV["MASTER_BED"] = "0"
# The machine's own lane state graded routing tests: a real agy quota, a key in
# ~/.config/master/env and the live health log each changed which lane a test
# saw first. The suite routes against empty state of its own.
ENV["MASTER_NO_ENV_FILES"] = "1"
# `bin/fix-here --model` exports the operator's pin, and the proof inherits it: four routing tests
# graded that pin instead of the choice they set up, so every pinned /fix proved red against itself.
ENV.delete("MASTER_MODEL")
ENV.delete("MASTER_MODEL_STRICT")

LIVE_STATE_DIR = Dir.mktmpdir("master-test-lanes-")
ENV["MASTER_LANE_QUOTA_PATH"] = File.join(LIVE_STATE_DIR, "lane_quota.yml")
ENV["MASTER_MODEL_QUOTA_PATH"] = File.join(LIVE_STATE_DIR, "model_quota.json")
ENV["MASTER_PROVIDER_HEALTH_PATH"] = File.join(LIVE_STATE_DIR, "provider_health.ndjson")
# A crashed /fix on this machine left its loop claim behind and every
# dispatch_fix test failed with "loop slot held by fix pid 26971".
ENV["MASTER_ACTIVE_LOOP_DIR"] = File.join(LIVE_STATE_DIR, "active_loop")
# The suite runner a test drives keeps its logs and its one-suite lock apart from the
# rake test that is running this file and holds .master/check/suite.lock.
ENV["MASTER_CHECK_LOG_DIR"] = File.join(LIVE_STATE_DIR, "check")
# A test that refuses a repair must not add a row to the run's own refusal log.
ENV["MASTER_FIX_REFUSALS_PATH"] = File.join(LIVE_STATE_DIR, "fix_refusals.jsonl")
# Nor a test's deliberate swallow a row in the error log the run summary reads.
ENV["MASTER_SWALLOW_LOG_PATH"] = File.join(LIVE_STATE_DIR, "swallowed_errors.jsonl")

# Direct test entrypoints must use the same pinned, private bundle as bin/master.
# Otherwise RubyGems can select a host-installed Minitest (or a native gem
# built against another Ruby) before the suite has a chance to activate MASTER.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require_relative "../lib/boot/dependency_manager"
test_root = File.expand_path("..", __dir__)
test_boot = Master::Boot::DependencyManager.new(root: test_root, env: ENV, out: $stderr)
test_result = test_boot.ensure!
unless test_result.ok
  abort("deps0: #{test_result.message}\n#{test_result.output}".strip)
end
test_boot.activate_environment!
require "bundler/setup"

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    # The groups name directories that exist. They read lib/master/scan,
    # lib/master/stages and lib/master/council, a path shape from before the lib
    # rename, so three panes of this report were empty for as long as anyone ran
    # it with COVERAGE=1. Groups shape the report rather than the threshold, so
    # the 85% minimum was never wrong; the reading of it was.
    add_group "Scan", "lib/review/scan"
    add_group "Stages", "lib/cli/stages"
    add_group "Council", "lib/review/council"
    minimum_coverage 85
  end
end

gem "minitest", "~> 5.25"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "timeout"

# Load MASTER without booting the CLI
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"

# Bound individual tests to prevent hangs, while leaving integration fixtures
# enough room on slower local runs.
#
# A test that needs longer says so by overriding `test_timeout`, rather than the
# global number rising to fit its worst case. One test needs it: TestRatchets
# measures every ratchet across the whole 2871-file corpus, which is a minute of
# honest work and not a hang. Raising the default to cover that would stop the
# other 1593 tests from catching a real one.
MASTER_TEST_TIMEOUT = Integer(ENV.fetch("MASTER_TEST_TIMEOUT", "30"))
MASTER_TEST_PID = Process.pid
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run

  def test_timeout = MASTER_TEST_TIMEOUT

  def run(*args)
    if ENV["MASTER_TEST_START_MARKERS"] == "1"
      STDERR.puts "test-start0: #{self.class}##{name}"
      STDERR.flush
    end
    watchdog = overrun_watchdog(Thread.current)
    Timeout.timeout(test_timeout) { run_without_timeout(*args) }
  rescue Timeout::Error
    failed_with(Timeout::Error.new("timed out after #{test_timeout}s"))
  # Minitest passes SystemExit through, so a test that reached exit or abort ended the whole run
  # with no report: on 2026-10-22 rake test stopped after 3,632 tests and named no failure.
  rescue SystemExit => e
    # A forked child's exit ends that child: caught there, the child ran the rest of the suite too.
    raise unless Process.pid == MASTER_TEST_PID

    origin = e.backtrace&.find { |line| !line.include?("/gems/") }
    failed_with(RuntimeError.new("called exit(#{e.status}) at #{origin}"))
  ensure
    watchdog&.kill
  end

  # A timeout that cannot land (an ensure joining worker threads) let TestRatchets run thirty
  # minutes past its five, in silence. Past its limit, the test says where it is stuck. It writes to
  # STDERR, the process's own: a test that captures $stderr and does not restore it would take the
  # watchdog's words with it.
  def overrun_watchdog(test_thread)
    Thread.new do
      sleep test_timeout + 30
      STDERR.puts "test0: #{self.class}##{name} still running #{test_timeout + 30}s in, past its #{test_timeout}s"
      test_thread.backtrace.to_a.first(12).each { |line| STDERR.puts "test0:   #{line}" }
    end
  end

  # Minitest 5.27 requires run to return a Result; handing back the test itself raised
  # "must return a Result" and ended the run at the first timed-out test.
  def failed_with(error)
    failures << Minitest::UnexpectedError.new(error)
    Minitest::Result.from(self)
  end

  # The canonical registry fills only when something loads law/. A test that
  # reads it must load it itself: under some seeds no earlier test had, and
  # ::Law raised NameError.
  def law_definitions
    require_relative "../law/definition"
    ::Law.load_all(File.expand_path("../law", __dir__)) if ::Law.definitions.empty?
    ::Law.definitions
  end

  # Run the canonical Law definition or its single registered detector
  # directly. Tests must not depend on a parallel bridge class to make a Law
  # visible to the scanner.
  def law_findings(id, code, path:)
    require_relative "../lib/review/scan/law_dsl"
    key = id.to_s.upcase
    definition = law_definitions.values.find { |law| law.id.to_s.upcase == key }
    if definition
      return Master::Review::Scan::CanonicalLawAdapter.new(definition).check(code, path:)
    end

    klass = Master::Review::Scan::Law.registry.find do |candidate|
      instance = Master::Review::Scan::LawFactory.build(candidate, root: Master::ROOT)
      instance.id.to_s.upcase == key
    end
    raise KeyError, "no Ruby detector registered for Law #{key}" unless klass

    Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT).check(code, path:)
      .select { |finding| finding[:law].to_s.upcase == key }
  end

  def rule(id, path: nil)
    candidates = Master::Review::Scan::Law.registry.filter_map do |klass|
      instance = klass.new
      instance if instance.id == id
    rescue ArgumentError
      nil
    end
    candidates.first || flunk("missing law #{id}")
  end

  def assert_finding(law, code, path, message)
    findings = law.check(code, path:)

    refute_empty findings
    assert findings.any? { |finding| finding[:message].include?(message) },
      "expected #{law.id} finding containing #{message.inspect}, got #{findings.inspect}"
  end
end
