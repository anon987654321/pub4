# frozen_string_literal: true

require_relative "../../test_helper"
require "tmpdir"
require "fileutils"

# The order is the tree-wide trend line: total tagged violations across lib/,
# and the delta since the last run. It answered Err("undefined local variable
# or method 'report'") on every call it had ever been given, so what these pin
# is that it runs at all, and that the second run can read what the first wrote.
class ConstitutionDriftTest < Minitest::Test
  FakeScanner = Struct.new(:findings) do
    def scan(_path, depth: :deep) = Master::Result.ok(findings)
  end

  def setup
    @tmp = Dir.mktmpdir("constitution_drift_test")
    FileUtils.mkdir_p(File.join(@tmp, "lib"))
    File.write(File.join(@tmp, "lib", "example.rb"), "x = 1\n")
  end

  def teardown = FileUtils.remove_entry(@tmp)

  def order(findings)
    Master::Ground::Orders::ConstitutionDrift.new(
      container: { scanner: FakeScanner.new(findings), root: @tmp },
    )
  end

  def finding(tags) = { tags: tags }

  def test_it_reports_a_total_and_a_first_run_delta
    result = order([finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_predicate result, :ok?
    assert_equal 2, result.value![:total]
    assert_equal 2, result.value![:delta]
  end

  def test_the_second_run_reads_what_the_first_persisted
    findings = [finding(%i[READABILITY])]
    order(findings).call

    assert_equal 0, order(findings).call.value![:delta]
  end

  def test_a_fall_reports_as_a_negative_delta
    order([finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_equal(-1, order([finding(%i[READABILITY])]).call.value![:delta])
  end

  def test_it_names_the_worst_axiom
    result = order([finding(%i[READABILITY]), finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_equal "READABILITY", result.value![:worst]
  end

  def test_no_scanner_is_an_error_not_a_crash
    without = Master::Ground::Orders::ConstitutionDrift.new(container: { root: @tmp })

    assert_predicate without.call, :err?
  end
end
