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

  # --- DEAD_CODE ----------------------------------------------------------
  # The detector matched a bare \b(return|raise)\b, so every guard clause read as
  # dead code. It must fire only on an unconditional terminator with reachable
  # code after it at the same or deeper indent.

  def test_dead_code_ignores_guard_clauses
    [
      "def a\n  return value if ready?\n  work\nend\n",
      "def a\n  raise Boom unless ok\n  work\nend\n",
      "def a\n  index = return_value\n  index\nend\n",
      "def a\n  cond ? return : work\n  more\nend\n",
      "def a\n  return a\nend\n\ndef b\n  work\nend\n",
    ].each do |source|
      assert_empty findings(:DEAD_CODE, source), "#{source.inspect} is not unreachable code"
    end
  end

  def test_dead_code_still_catches_a_real_unreachable_line
    refute_empty findings(:DEAD_CODE, "def a\n  return\n  work\nend\n")
  end

  # --- MAGIC_COLOR --------------------------------------------------------
  # Token definitions hold raw values; usage cites the token. A documented parody
  # opts a whole file out; one line opts out inline. It must still catch raw usage.

  def test_magic_color_ignores_definitions_and_intentional_markers
    [
      ["  --accent: #7c6fd6;\n", "app/x.scss"],
      ["  $brand: #7c6fd6;\n", "app/x.scss"],
      ["  background: #131921; // scan: intentional\n", "app/x.scss"],
      ["/* scan: intentional-colors */\n  color: #131921;\n", "app/x.scss"],
    ].each do |source, path|
      assert_empty findings(:MAGIC_COLOR, source, path: path), "#{source.inspect} is intentional or a definition"
    end
  end

  def test_magic_color_still_catches_a_raw_usage
    refute_empty findings(:MAGIC_COLOR, "  color: #7c6fd6;\n", path: "app/x.scss")
  end

  def test_magic_color_is_registered_once
    count = scanner.rules.count { |rule| rule.id.to_s == "MAGIC_COLOR" }
    assert_equal 1, count, "MAGIC_COLOR must be one rule, not #{count} (SINGULARITY: unique by id)"
  end

  # --- veto unsafe_calls --------------------------------------------------
  # Interpolation is the arbitrary-code-execution risk. The arg-array form is the
  # prescribed FIX and must not be vetoed; an interpolated shell string must be.

  def test_veto_unsafe_calls_allows_the_prescribed_arg_array_form
    [
      %(ok = system(RbConfig.ruby, script, "--input", input)\n),
      %(out, status = Open3.capture2e("git", "-C", root, "status")\n),
    ].each do |source|
      assert_empty findings(:veto_patterns, source), "#{source.inspect} is the safe arg-array form"
    end
  end

  def test_veto_unsafe_calls_still_catches_interpolated_shell_out
    refute_empty findings(:veto_patterns, %(system("rm -rf \#{directory}")\n))
  end

  # --- CONTROL_CHARS ------------------------------------------------------
  # A concurrent write left SOH bytes wrapping a string literal this session;
  # this rule catches that corruption class. Tab/newline stay legal. The SOH is
  # built with 1.chr so the test source itself carries no control character.

  def test_control_chars_ignores_clean_source_and_tabs
    ["def a\n  work\nend\n", "a\tb\n"].each do |source|
      assert_empty findings(:CONTROL_CHARS, source), "#{source.inspect} has no control characters"
    end
  end

  def test_control_chars_flags_a_stray_soh_byte
    refute_empty findings(:CONTROL_CHARS, "def a\n  x = #{1.chr}y\nend\n")
  end
end
