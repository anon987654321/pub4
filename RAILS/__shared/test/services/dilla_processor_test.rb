# frozen_string_literal: true

require "minitest/autorun"
require "rails"
require "logger"
require "tmpdir"

Rails.logger ||= Logger.new(File::NULL)
require "rbconfig"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require_relative "../../app/services/shared/dilla_processor"

# dilla has hung indefinitely in the past, pinning a Solid Queue worker forever.
# run_with_timeout must free the worker and kill the child instead of blocking.
class DillaProcessorTest < Minitest::Test
  def test_on_path_checks_files_not_directories_or_same_named_relative_paths
    Dir.mktmpdir("shared-subprocess-path") do |dir|
      executable = File.join(dir, "yt-dlp")
      plain_file = File.join(dir, "plain")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(0o755, executable)
      File.write(plain_file, "not executable")
      Dir.mkdir(File.join(dir, "folder"))

      assert Shared::Subprocess.on_path?("yt-dlp", path: dir)
      refute Shared::Subprocess.on_path?("plain", path: dir)
      refute Shared::Subprocess.on_path?("folder", path: dir)
      refute Shared::Subprocess.on_path?("", path: dir)
      refute Shared::Subprocess.on_path?("./yt-dlp", path: dir)
    end
  end

  def test_shared_subprocess_merges_output_for_process_suite_runner
    output, status = Shared::Subprocess.capture2e(
      RbConfig.ruby, "-e", "STDOUT.write('out'); STDERR.write('err')", timeout: 2
    )

    assert_includes output, "out"
    assert_includes output, "err"
    assert status.success?
  end

  def test_shared_subprocess_keeps_stdout_and_stderr_separate
    stdout, stderr, status = Shared::Subprocess.capture3(
      RbConfig.ruby, "-e", "STDOUT.write('out'); STDERR.write('err')", timeout: 2
    )

    assert_equal "out", stdout
    assert_equal "err", stderr
    assert status.success?
  end

  def test_successful_command_returns_true
    ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "STDOUT.puts 'done'" ])
    assert_equal true, ok
  end

  def test_failing_command_returns_false
    ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "exit 1" ])
    assert_equal false, ok
  end

  def test_hung_command_times_out_quickly_instead_of_blocking
    with_env("DILLA_SH_TIMEOUT" => "1") do
      started = Time.now
      ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "sleep 30" ])
      elapsed = Time.now - started

      assert_equal false, ok, "a render past the timeout must fail, not succeed"
      assert_operator elapsed, :<, 10, "must return near the 1s timeout, not wait out the 30s sleep"
    end
  end

  private

  def with_env(overrides)
    backup = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    backup.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
