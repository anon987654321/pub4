# frozen_string_literal: true

require "test_helper"
require "open3"

# bin/doctor had no test. It is the tool an operator runs first on a host that
# is behaving oddly, and the thing it reports is a verdict per check — so the
# verdict vocabulary is the part worth pinning.
#
# Driven as a subprocess rather than by loading the file: doctor is a script
# with top-level execution, and requiring it runs every probe against this
# machine. That is also the honest test of an entry point, which the tree has
# already been bitten by twice (test_entrypoint_requires).
class TestDoctor < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCTOR = File.join(ROOT, "bin", "doctor")

  def run_doctor(env = {})
    Open3.capture2e(env, RbConfig.ruby, DOCTOR, chdir: ROOT)
  end

  def test_doctor_runs_and_reports_every_check
    out, = run_doctor
    assert_match(/\AMASTER doctor/, out)
    %w[content-dedup api-keys tts-socket web-token key-rotator
       model-quota cache-efficiency provider-catalog].each do |name|
      assert_match(/^(OK|FAIL|SKIP) #{Regexp.escape(name)}:/, out, "doctor did not report #{name}")
    end
  end

  # The verdict is three-valued, and the third one is the reason this test
  # exists. model-quota and cache-efficiency used to answer `ok: true, detail:
  # "module not loaded"` — OK for a check nobody ran — and content-dedup raised
  # into `ok: false`, so a broken instrument read as a real finding.
  def test_a_check_that_measured_nothing_says_so
    source = File.read(DOCTOR)
    assert_match(/state: :unmeasured/, source, "no check can report that it measured nothing")
    refute_match(/state: :pass, detail: "module not loaded"/, source,
                 "a check that did not load is reporting OK")
  end

  def test_unmeasured_is_printed_and_counted_but_does_not_fail_the_host
    source = File.read(DOCTOR)
    assert_match(/check\(s\) measured nothing, and why/, source,
                 "unmeasured checks are not named in the output")
    assert_match(/def ok = state != :fail/, source,
                 "unmeasured must not count as a failure for the exit code")
  end

  # Every construction goes through the three-state struct. A stray `ok:` is an
  # ArgumentError at runtime, which is how this was found: doctor crashed on
  # its first check after the struct changed.
  def test_no_check_is_constructed_with_a_boolean
    code = File.read(DOCTOR).lines.reject { |line| line.strip.start_with?("#") }.join
    refute_match(/Check\.new\([^)]*\bok:/, code, "a Check is still built with ok:")
  end
end
