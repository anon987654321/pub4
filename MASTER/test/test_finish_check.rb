# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"

# tools/finish_check.rb: PostToolUse `record` remembers what the session edited; Stop refuses to finish while
# a line it changed breaks a law. The lint is a stub, so the check is tested without booting the runtime.
module FinishCheckHarness
  CHECK = File.expand_path("../tools/finish_check.rb", __dir__)
  REPO = File.expand_path("../..", __dir__)
  CLEAN = "# frozen_string_literal: true\n\nX = 1\n"
  FINDING = "lint0: MASTER/lib/zz.rb:3, SECRET_PROXIMITY: a secret sits beside code\n"

  def run_check(payload, args: [], env: {})
    out, status = Open3.capture2e(env, RbConfig.ruby, CHECK, *args, stdin_data: JSON.generate(payload))
    [status.exitstatus, out]
  end

  def record(session, path)
    edit = { "session_id" => session, "tool_name" => "Write", "tool_input" => { "file_path" => path } }
    run_check(edit, args: ["record"])
  end

  # A stand-in operator that answers `lint` with `output` and `exit_code`.
  def finish(session, output:, exit_code:, extra: {})
    Dir.mktmpdir do |dir|
      operator = File.join(dir, "operator")
      File.write(operator, "#!/bin/sh\ncat <<'EOF'\n#{output}EOF\nexit #{exit_code}\n")
      File.chmod(0o755, operator)
      run_check({ "session_id" => session }.merge(extra), env: { "PUB4_FINISH_CHECK_OPERATOR" => operator })
    end
  end

  def edits_file(session) = File.join(Dir.tmpdir, "pub4-edits-#{session}")

  def with_probe(content)
    session = "test#{Process.pid}#{rand(10_000)}"
    path = File.join(REPO, "MASTER", "lib", "zz_finish_probe_#{session}.rb")

    File.write(path, content)
    yield session, path
  ensure
    File.delete(path) if path && File.exist?(path)
    File.delete(edits_file(session)) if session && File.exist?(edits_file(session))
  end
end

class TestFinishCheckRecording < Minitest::Test
  include FinishCheckHarness

  def test_an_edit_is_remembered_once_per_path_and_never_blocks
    with_probe(CLEAN) do |session, path|
      assert_equal 0, record(session, path).first
      assert_equal 0, record(session, path).first

      assert_equal [path], File.readlines(edits_file(session), chomp: true).uniq
    end
  end

  def test_empty_or_unreadable_input_never_blocks
    out, status = Open3.capture2e(RbConfig.ruby, CHECK, stdin_data: "not json")

    assert_equal 0, status.exitstatus, out
    assert_equal 0, run_check({ "session_id" => "never-edited-#{Process.pid}" }).first
  end

  def lint_calls(session)
    Dir.mktmpdir do |dir|
      log = File.join(dir, "args")
      operator = File.join(dir, "operator")
      File.write(operator, "#!/bin/sh\necho \"$@\" >> #{log}\nexit 0\n")
      File.chmod(0o755, operator)

      run_check({ "session_id" => session }, env: { "PUB4_FINISH_CHECK_OPERATOR" => operator })
      File.readlines(log, chomp: true)
    end
  end

  def test_a_new_file_is_linted_whole_and_a_tracked_one_by_changed_lines
    with_probe(CLEAN) do |session, fresh|
      record(session, fresh)
      record(session, File.join(REPO, "MASTER", "tools", "law_check_edit.rb"))
      calls = lint_calls(session)

      assert(calls.any? { |call| call.start_with?("lint --changed-lines") && call.include?("law_check_edit.rb") })
      assert(calls.any? { |call| !call.include?("--changed-lines") && call.include?("zz_finish_probe") })
    end
  end
end

class TestFinishCheckVerdict < Minitest::Test
  include FinishCheckHarness

  def test_a_changed_line_that_breaks_a_law_blocks_the_finish_with_the_reason
    with_probe(CLEAN) do |session, path|
      record(session, path)
      code, out = finish(session, output: "lint0 at master0: 1 finding(s) across 1 files\n#{FINDING}", exit_code: 1)

      assert_equal 2, code, out
      assert_includes out, "SECRET_PROXIMITY"
      refute_includes out, "finding(s) across", "the summary line is noise to the agent"
    end
  end

  def test_a_clean_lint_lets_the_finish_through
    with_probe(CLEAN) do |session, path|
      record(session, path)

      assert_equal 0, finish(session, output: "lint0: clean, 1 files, no law broken\n", exit_code: 0).first
    end
  end

  def test_a_lint_that_cannot_run_never_traps_the_session
    with_probe(CLEAN) do |session, path|
      record(session, path)

      assert_equal 0, finish(session, output: "", exit_code: 1).first
    end
  end

  def test_a_second_stop_in_a_row_always_passes
    with_probe(CLEAN) do |session, path|
      record(session, path)
      code, = finish(session, output: FINDING, exit_code: 1, extra: { "stop_hook_active" => true })

      assert_equal 0, code
    end
  end
end
