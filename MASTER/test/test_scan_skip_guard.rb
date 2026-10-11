# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/scan_skip_guard"

# A scan that could not measure its files must not report them clean.
class TestScanSkipGuard < Minitest::Test
  Guard = Master::Fix::ScanSkipGuard
  Failure = Struct.new(:category, :message)

  NAME_ERROR = "scan failed: NameError: uninitialized constant Master::Fix::Scan::FileProcessor::Operator at lib/x.rb:1"

  def failure(message = NAME_ERROR, category: :infrastructure) = Failure.new(category, message)

  def test_one_exception_class_across_many_files_aborts
    guard = Guard.new
    21.times { |i| guard.record("f#{i}.rb", failure) }

    error = assert_raises(Master::Fix::MassSkipError) { guard.check!(total: 100_000) }
    assert_equal "NameError", error.signature
    assert_equal 21, error.count
  end

  def test_two_percent_of_files_aborts_even_when_the_causes_differ
    guard = Guard.new
    5.times { |i| guard.record("f#{i}.rb", failure("scan failed: Errno::EIO: x#{i}")) }

    assert_raises(Master::Fix::MassSkipError) { guard.check!(total: 100) }
  end

  def test_a_few_skips_in_a_large_run_pass
    guard = Guard.new
    3.times { |i| guard.record("f#{i}.rb", failure) }

    guard.check!(total: 1000)
  end

  def test_refusals_of_single_files_are_not_counted
    guard = Guard.new
    50.times { |i| guard.record("f#{i}.rb", failure("file too long: f", category: :validation)) }

    assert_equal 0, guard.size
    guard.check!(total: 50)
  end

  def test_signature_without_a_class_groups_by_message_not_path
    a = Guard.signature("scan failed: boom at /a/b.rb:3")
    b = Guard.signature("scan failed: boom at /c/d.rb:9")
    assert_equal a, b
  end

  def test_pass_runner_aborts_instead_of_counting_the_scan_clean
    runner = Master::Fix::FixLoop::PassRunner.allocate
    scan_phase = Object.new
    scan_phase.define_singleton_method(:call) { |_path| Master::Result.err(NAME_ERROR, category: :infrastructure) }
    preflight = Object.new
    preflight.define_singleton_method(:findings) { |_paths| [] }
    runner.instance_variable_set(:@root, Dir.pwd)
    runner.instance_variable_set(:@scan_phase, scan_phase)
    runner.instance_variable_set(:@preflight, preflight)
    runner.instance_variable_set(:@skip_guard, Guard.new)
    runner.instance_variable_set(:@scan_total, 200)
    paths = Array.new(30) { |i| "tmp-skip-#{i}" }
    File.stub(:exist?, true) do
      assert_raises(Master::Fix::MassSkipError) { runner.violations(paths) }
    end
  end
end
