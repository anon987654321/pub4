# frozen_string_literal: true

require_relative "test_helper"

# Declared shell-output filters. The fixtures are real captures from this checkout:
# a passing minitest run, a verbose one, a failing one with a 25-frame backtrace,
# and a 150-line grep. rubocop, bundle, npm, docker and curl are not installed
# here, so their samples are written to the formats those tools document.
class TestRtkFilters < Minitest::Test
  FIXTURES = File.join(__dir__, "fixtures", "rtk")
  Filter = Master::Io::OutputFilter

  def fixture(name) = File.read(File.join(FIXTURES, name))

  def setup = @saved_rtk = ENV.fetch("MASTER_RTK", nil)

  def teardown = ENV["MASTER_RTK"] = @saved_rtk

  def test_failing_minitest_keeps_every_failure_message_and_the_summary
    raw = fixture("minitest_fail.txt")
    out = Filter.compress_failure(command: "rake test", output: raw)

    assert_includes out, "Expected: \"alpha\""
    assert_includes out, "Expected 3 to be nil."
    assert_includes out, "RuntimeError: deep boom"
    assert_includes out, "7 runs, 3 assertions, 2 failures, 1 errors"
    assert_includes out, "25 identical lines elided"
    assert_operator out.bytesize, :<, raw.bytesize / 3
  end

  def test_no_error_line_is_ever_dropped
    {
      "minitest_fail.txt" => "rake test", "minitest_verbose_pass.txt" => "rake test", "grep_many.txt" => "grep -rn module lib"
    }.each do |name, command|
      raw = fixture(name)
      out = Filter.filter(command:, output: raw)
      raw.lines.map(&:chomp).select { |line| Filter::ERROR_RE.match?(line) }.uniq.each do |line|
        assert_includes out, line.strip, "#{name} lost: #{line}"
      end
    end
  end

  def test_verbose_pass_drops_per_test_lines
    raw = fixture("minitest_verbose_pass.txt")
    out = Filter.filter(command: "ruby -Ilib -Itest test/test_x.rb -v", output: raw)

    assert_includes out, "19 runs, 70 assertions, 0 failures"
    assert_includes out, "lines elided"
    assert_operator out.bytesize, :<, raw.bytesize / 4
  end

  def test_grep_truncates_with_a_count
    raw = fixture("grep_many.txt")
    out = Filter.filter(command: "grep -rn module lib", output: raw)

    kept = out.lines.count { |l| !l.start_with?("[...") }
    elided = out.scan(/\[\.\.\. (\d+) lines elided/).flatten.sum(&:to_i)
    assert_operator kept, :<, 150
    assert_equal 150, kept + elided
  end

  def test_rubocop_keeps_offences_and_summary
    raw = "Inspecting 2 files\n.C\n\nOffenses:\n\na.rb:1:1: C: Style/Foo: bad\n  #{"code that is long " * 8}\n  ^^^\n\n2 files inspected, 1 offense detected\n"
    out = Filter.filter(command: "bundle exec rubocop", output: raw)
    refute_includes out, "^^^"
    assert_includes out, "a.rb:1:1: C: Style/Foo: bad"
    assert_includes out, "2 files inspected, 1 offense detected"
  end

  def test_package_and_container_noise_is_dropped_but_results_stay
    bundle = (["Using rake 13.0", "Fetching foo 1.0", "Installing foo 1.0"] * 6).join("\n") << "\nBundle complete! 9 Gemfile dependencies\n"
    out = Filter.filter(command: "bundle install", output: bundle)
    assert_includes out, "Bundle complete!"
    refute_includes out, "Using rake"

    docker = "abc: Pulling fs layer\nabc: Download complete\nabc: Pull complete\nDigest: sha256:1\nStatus: Downloaded newer image\n"
    out = Filter.filter(command: "docker pull x", output: docker)
    assert_includes out, "Status: Downloaded newer image"
    refute_includes out, "Pull complete"

    curl = "  % Total    % Received % Xferd  Average Speed\n                                 Dload  Upload\n100  10  100  10  0  0  50  0 --:--:-- 50\nok body\n"
    assert_equal "[... 3 lines elided ...]\nok body\n", Filter.filter(command: "curl -s x", output: curl)

    npm = "npm http fetch GET 200 https://registry.npmjs.org/some-package-name\nnpm error code E404\nadded 3 packages in 2s\n"
    out = Filter.filter(command: "npm install", output: npm)
    assert_includes out, "npm error code E404"
    refute_includes out, "npm http"
  end

  def test_escape_hatch_returns_raw_and_declines_failure_compression
    raw = fixture("minitest_fail.txt")
    ENV["MASTER_RTK"] = "0"

    assert_equal raw, Filter.filter(command: "rake test", output: raw)
    assert_nil Filter.compress_failure(command: "rake test", output: raw)
  end

  def test_shell_failure_text_carries_failure_messages_the_old_tail_cut
    shell = Master::Io::Shell.allocate
    result = Struct.new(:out, :err).new(fixture("minitest_fail.txt"), "")

    text = shell.send(:failure_text, "rake test", result)
    assert_includes text, "Expected: \"alpha\""
    assert_includes text, "2 failures, 1 errors"

    ENV["MASTER_RTK"] = "0"
    assert_operator shell.send(:failure_text, "rake test", result).length, :<=, 400
  end

  def test_unmatched_failure_keeps_the_plain_tail
    shell = Master::Io::Shell.allocate
    result = Struct.new(:out, :err).new("x" * 900, "")

    assert_equal 400, shell.send(:failure_text, "./mystery", result).length
  end
end
