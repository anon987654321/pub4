# frozen_string_literal: true

require_relative "test_helper"

# DEBT.md, Scanner noise: "38 of rake selfcheck's 76 findings are false positives
# from two rules: COMPLETION_THEATER matches require \"etc\", Etc.nprocessors and
# /etc/* paths; STALE_NAMESPACE flags every legitimate Master::CLI::* reference
# because \b matches before ::."
#
# Both are narrowed now — selfcheck went 71 → 34 on 2026-08-01. Narrowing a rule is
# the change most likely to quietly turn it off, so each of these asserts both
# directions: the false positive is gone AND the real violation still fires.
class TestScanRuleFalsePositives < Minitest::Test
  def scanner
    @scanner ||= Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
  end

  def rule(id)
    scanner.rules.find { |r| r.id.to_s == id.to_s } || raise("rule #{id} is not registered")
  end

  def findings(id, source, path: "lib/example.rb")
    Array(rule(id).check(source, path: File.join(Master::ROOT, path)))
  end

  # --- COMPLETION_THEATER -------------------------------------------------

  def test_completion_theater_ignores_the_etc_stdlib_and_etc_paths
    [
      %(require "etc"),
      %(cores = Etc.nprocessors),
      %(path = "/etc/rc.d/master"),
      %(sh "doas cp etc/doas.conf /etc/doas.conf"),
      %(File.read("/etc/master.env")),
    ].each do |line|
      assert_empty findings(:COMPLETION_THEATER, "#{line}\n"), "#{line.inspect} is not a placeholder"
    end
  end

  def test_completion_theater_still_catches_a_real_placeholder
    [
      %(SUPPORTED = "png, jpg, etc."),
      %(DESCRIPTION = "clusters (marketplace, playlist, etc.)"),
      %(HELP = "flags: --all, --quiet, etcetera"),
    ].each do |line|
      refute_empty findings(:COMPLETION_THEATER, "#{line}\n"), "#{line.inspect} should be flagged"
    end
  end

  def test_completion_theater_still_catches_a_trailing_ellipsis
    refute_empty findings(:COMPLETION_THEATER, "  handle_the_rest ...\n")
  end

  def test_completion_theater_skips_comments
    assert_empty findings(:COMPLETION_THEATER, "# a, b, etc.\n")
  end

  # --- STALE_NAMESPACE ----------------------------------------------------

  def stale_pairs
    config = (Master.load_yaml(Master.data_path("patterns.yml")) || {})["stale_namespaces"] || {}
    Array(config["stale_constants"]).select { |row| row.is_a?(Hash) }
  end

  def test_a_retired_constant_used_as_a_prefix_is_not_a_violation
    refute_empty stale_pairs

    stale_pairs.each do |row|
      old = row["old"]
      # Every replacement contains, or is nested under, some retired prefix — that
      # is exactly the shape that produced 25 false findings.
      assert_empty findings(:STALE_NAMESPACE, "#{row["new"]}.call\n"),
                   "#{row["new"]} is the replacement for #{old} and must not be flagged"
    end
  end

  def test_the_bare_retired_constant_is_still_a_violation
    stale_pairs.each do |row|
      refute_empty findings(:STALE_NAMESPACE, "x = #{row["old"]}\n"),
                   "#{row["old"]} is retired and must still be flagged"
    end
  end

  def test_a_longer_constant_that_merely_starts_with_a_retired_name_is_ignored
    assert_empty findings(:STALE_NAMESPACE, "Master::CLIRunner.new\n")
    assert_empty findings(:STALE_NAMESPACE, "Other::Master::Scanner.new\n")
  end

  def test_the_rules_own_file_is_exempt
    assert_empty findings(:STALE_NAMESPACE, "x = Master::CLI\n", path: "lib/review/scan/rules/naming_rules.rb")
  end
end
