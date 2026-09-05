# frozen_string_literal: true

require_relative "test_helper"
require "cli/scan_request"
require "cli/command_registry"

# Three defects, one amplifier, all shipped together on 2026-08-17's slash
# collapse (7c23a5ee5) and caught live on 2026-08-18 when the RAILS pass of a
# four-tree audit scanned MASTER twice and called it RAILS:
#
# - "rails" names both a limits.yml scan profile and pub4/RAILS, and the
#   profile reading won, leaving an empty target.
# - parse_through_flags did not know --no-autofix (bin/gate's scan-only
#   spelling), so the flag polluted the target string.
# - Both fed the same amplifier: a target that resolved nowhere quietly
#   became the scan root, so the wrong tree was measured with a green exit.
class TestScanRequestTargets < Minitest::Test
  class RecordingScanner
    attr_reader :dirs

    def initialize
      @dirs = []
    end

    def scan(path, **) = Master::Result.ok([])

    def scan_dir(dir, **)
      @dirs << dir
      Master::Result.ok([])
    end
  end

  def request(arg)
    Master::CLI::ScanRequest.new(scanner: RecordingScanner.new, root: Master::ROOT, arg:)
  end

  def test_a_word_that_is_both_profile_and_target_is_the_target
    assert_equal Master::RAILS_ROOT, request("rails").send(:target_arg)
  end

  def test_the_profile_still_applies_when_the_word_is_both
    profile, = request("rails").send(:resolve_profile)
    assert_equal "rails", profile
  end

  def test_profile_plus_target_still_splits
    assert_equal Master::RAILS_ROOT, request("aesthetic rails").send(:target_arg)
  end

  def test_a_bare_profile_word_still_scans_the_root
    scanner = RecordingScanner.new
    req = Master::CLI::ScanRequest.new(scanner:, root: Master::ROOT, arg: "aesthetic")
    req.call

    assert_equal [Master::ROOT], scanner.dirs
  end

  def test_a_target_that_resolves_nowhere_fails_loudly_instead_of_scanning_root
    scanner = RecordingScanner.new
    req = Master::CLI::ScanRequest.new(scanner:, root: Master::ROOT, arg: "../NO_SUCH_TREE")
    result = req.call

    assert_kind_of String, result.pairs
    assert_match(/\Ascan failed: no such target:/, result.pairs)
    assert_empty scanner.dirs, "fell back to scanning the root"
  end

  def test_parse_through_flags_reads_no_autofix_as_measure_only
    apply, _critique, _aesthetic, path =
      Master::CLI::CommandRegistry.parse_through_flags("--no-autofix ../RAILS")

    assert_equal false, apply
    assert_equal "../RAILS", path
  end

  def test_aesthetic_profile_walks_only_aesthetic_rules
    scanner = RecordingScanner.new
    def scanner.rules
      [Struct.new(:id).new("CONFIG_HIERARCHY"), Struct.new(:id).new("ANTI_DIVITIS")]
    end
    scanner.instance_variable_set(:@rule_ids, nil)
    def scanner.scan_dir(dir, **opts)
      @dirs << dir
      @rule_ids = Array(opts[:rules]).map { |rule| rule.id.to_s }
      Master::Result.ok([])
    end
    def scanner.rule_ids = @rule_ids

    Master::CLI::ScanRequest.new(scanner:, root: Master::ROOT, arg: "aesthetic").call

    refute_includes scanner.rule_ids, "CONFIG_HIERARCHY"
    assert_includes scanner.rule_ids, "ANTI_DIVITIS"
  end
end
