# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "tmpdir"

class TestSwallow < Minitest::Test
  def unique_context(label) = "test_swallow.#{label}.#{SecureRandom.hex(4)}"

  def test_log_defaults_to_cosmetic_severity_for_existing_call_sites
    ctx = unique_context("default")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "cosmetic", entry["severity"]
  end

  def test_a_code_defect_is_load_bearing_and_printed_once_per_context
    ctx = unique_context("defect")
    lines = []
    Master::Trace::Dmesg.stub(:status, ->(unit, text, **) { lines << "#{unit}: #{text}" }) do
      2.times { Master::Ground::Swallow.log(NoMethodError.new("undefined method 'inner_html'"), context: ctx) }
    end

    assert_equal "load_bearing", Master::Ground::Swallow.recent(limit: 5, context: ctx).last["severity"]
    assert_equal 1, lines.size
    assert_match(/error0: #{Regexp.escape(ctx)} swallowed NoMethodError: undefined method 'inner_html'/, lines.first)
  end

  def test_log_accepts_explicit_load_bearing_severity
    ctx = unique_context("tagged")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :load_bearing)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "load_bearing", entry["severity"]
  end

  def test_log_falls_back_to_cosmetic_for_unrecognized_severity
    ctx = unique_context("bogus")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :not_a_real_severity)

    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "cosmetic", entry["severity"]
  end

  def test_recent_filters_by_severity
    ctx = unique_context("filter")
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx, severity: :load_bearing)
    Master::Ground::Swallow.log(RuntimeError.new("y"), context: ctx, severity: :cosmetic)

    load_bearing_only = Master::Ground::Swallow.recent(limit: 20, context: ctx, severity: :load_bearing)
    assert_equal 1, load_bearing_only.size
    assert_equal "x", load_bearing_only.first["error_message"]
  end

  def test_rotation_compacts_backups_and_preserves_sidecar_lock
    Dir.mktmpdir("swallow-rotation-") do |dir|
      path = File.join(dir, "swallowed_errors.jsonl")
      lock_path = "#{path}.lock"
      File.write(lock_path, "lock")
      File.chmod(0o600, lock_path)

      6.times do |index|
        rows = 20.times.map { |n| JSON.generate("entry" => index * 20 + n) }.join("\n") + "\n"
        File.write(path, rows)
        File.chmod(0o600, path)
        Master::Ground::Swallow.rotate!(path:, max_bytes: 128, keep: 2)
      end

      backups = Dir.glob("#{path}.*").reject { |candidate| candidate == lock_path }
      assert_equal 2, backups.size
      assert backups.all? { |backup| File.size(backup) <= 128 }
      backups.each do |backup|
        lines = File.readlines(backup, chomp: true)
        refute_empty lines
        lines.each { |line| JSON.parse(line) }
      end
      assert File.file?(lock_path), "rotation retention must never remove the active lock inode"
    end
  end

  def test_safe_call_forwards_severity
    ctx = unique_context("safe_call")
    result = Master::Ground::Swallow.safe_call(context: ctx, severity: :load_bearing) { raise "boom" }

    assert_nil result
    entry = Master::Ground::Swallow.recent(limit: 5, context: ctx).last
    assert_equal "load_bearing", entry["severity"]
  end

  def test_the_suite_writes_a_scratch_log_never_the_one_a_fix_run_reads
    ctx = unique_context("scratch")
    real = Master::Ground::Swallow::LOG_PATH
    before = File.file?(real) ? File.size(real) : 0
    Master::Ground::Swallow.log(RuntimeError.new("x"), context: ctx)

    refute_equal real, Master::Ground::Swallow.log_path
    assert_equal ENV.fetch("MASTER_SWALLOW_LOG_PATH"), Master::Ground::Swallow.log_path
    assert_includes File.read(Master::Ground::Swallow.log_path), ctx
    assert_equal before, File.file?(real) ? File.size(real) : 0
  end
end
