# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# core-reclaim.sh decides whether the box is too busy to restart brgen by
# comparing two decimals in ksh, which has only integers. The function is read
# out of the script itself and run under ksh, so the verdict is the shell's and
# not a reading of its source.
class TestCoreReclaim < Minitest::Test
  SCRIPT = File.expand_path("../usr/local/bin/core-reclaim.sh", __dir__)
  KSH = %w[/bin/ksh /usr/bin/ksh].find { |path| File.executable?(path) }
  # Both sides of LOAD_MAX, loads over ten, a bare integer, a bare fraction, and
  # the 08 and 09 fractions ksh would read as bad octal without a base.
  LOADS = %w[0.00 0.08 0.09 0.18 1.9 2.08 2.09 2.49 2.50 2.5 2.51 2.500001 2.4999999 3 .5 9.99 10.00 99.99].freeze

  def verdicts(limit)
    skip "no ksh here" unless KSH
    function = File.read(SCRIPT)[/^micro\(\) \{\n.*?^\}\n/m]
    refute_nil function, "core-reclaim.sh no longer defines micro()"

    program = function + LOADS.map { |load| %(if (( $(micro "#{load}") > $(micro "#{limit}") )); then print 1; else print 0; fi\n) }.join
    out, err, status = Open3.capture3(KSH, "-c", program)
    assert status.success?, err
    out.split.map { |bit| bit == "1" }
  end

  def test_the_integer_comparison_agrees_with_float_comparison
    limit = File.read(SCRIPT)[/^LOAD_MAX=(\S+)/, 1]
    expected = LOADS.map { |load| load.to_f > limit.to_f }

    assert_equal LOADS.zip(expected), LOADS.zip(verdicts(limit))
  end
end
