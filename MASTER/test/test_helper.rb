# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_group "Scan", "lib/master/scan"
    add_group "Stages", "lib/master/stages"
    add_group "Council", "lib/master/council"
    minimum_coverage 85
  end
end

ENV["MT_NO_PLUGINS"] = "1"
ENV["MASTER_TTS_MODE"] = "classic"
gem "minitest", "~> 5.25"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "timeout"

# Load MASTER without booting the CLI
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
# Not inlined here. dilla/lib/music_gems.rb requires this same file by absolute
# path right after `require "coltrane"`, and inlining it broke that require —
# see the file's own header.
require_relative "../lib/boot/hash_dig_compat"
Master.install_hash_dig_compat!

# Bound individual tests to prevent hangs, while leaving integration fixtures
# enough room on slower local runs.
#
# A test that needs longer says so by overriding `test_timeout`, rather than the
# global number rising to fit its worst case. One test needs it: TestRatchets
# measures every ratchet across the whole 2871-file corpus, which is a minute of
# honest work and not a hang. Raising the default to cover that would stop the
# other 1593 tests from catching a real one.
MASTER_TEST_TIMEOUT = Integer(ENV.fetch("MASTER_TEST_TIMEOUT", "30"))
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run

  def test_timeout = MASTER_TEST_TIMEOUT

  def run(*args)
    Timeout.timeout(test_timeout) { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("timed out after #{test_timeout}s"))
    self
  end

  def before_setup
    Master.install_hash_dig_compat!
    super
  end

  # Shared by every scan-rule test (test_cosmetic_rules, test_web_rules,
  # test_web_scan_fixtures, test_scan_rule_contracts) -- was copy-pasted
  # byte-identical in all four before this hoist.
  # A rule that lives in law/ has the bridge as its scanner surface, so its
  # contract test asserts through it (BUTTON_OVER_ANCHOR set the precedent).
  def law_findings(id, code, path:)
    Master::Review::Scan::Rules::LawBridgeRule.new.check(code, path:).select { |f| f[:rule] == id }
  end

  def rule(id, path: nil)
    candidates = Master::Review::Scan::Rule.registry.filter_map do |klass|
      instance = klass.new
      instance if instance.id == id
    rescue ArgumentError
      nil
    end
    candidates.first || flunk("missing rule #{id}")
  end

  def assert_finding(rule, code, path, message)
    findings = rule.check(code, path:)

    refute_empty findings
    assert findings.any? { |finding| finding[:message].include?(message) },
      "expected #{rule.id} finding containing #{message.inspect}, got #{findings.inspect}"
  end
end
