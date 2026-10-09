# frozen_string_literal: true

require "minitest/autorun"
require "ripper"

# A `test "..." do` call that ends up outside its test class resolves to
# Kernel#test, which takes two arguments, so the file raises ArgumentError when
# the suite loads and every test after it never runs. A bad merge closed
# RAILS/brgen's snapshot job test early and the deploy's whole test step died on
# that one load. Ripper reads the structure without booting Rails or any gem.
class NoTopLevelTestCallsTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)

  def top_level_test_calls(source)
    sexp = Ripper.sexp(source)
    return [:syntax_error] unless sexp

    sexp[1].select { |node| node.is_a?(Array) && kernel_test_call?(node) }
  end

  def kernel_test_call?(node)
    case node[0]
    when :command then node[1][0] == :@ident && node[1][1] == "test"
    when :method_add_block then node[1].is_a?(Array) && node[1][0] == :command && kernel_test_call?(node[1])
    else false
    end
  end

  def test_the_detector_flags_a_test_call_outside_a_class
    broken = %(class T < Minitest::Test\nend\n\ntest "x" do\nend\n)

    refute_empty top_level_test_calls(broken)
    assert_empty top_level_test_calls(%(class T < Minitest::Test\n  test "x" do\n  end\nend\n))
  end

  def test_no_test_file_calls_test_outside_its_class
    files = Dir[File.join(RAILS, "**", "test", "**", "*_test.rb")].reject { |f| f.include?("/node_modules/") }
    refute_empty files

    offenders = files.select { |f| !top_level_test_calls(File.read(f, encoding: "UTF-8")).empty? }

    assert_empty offenders.map { |f| f.delete_prefix("#{RAILS}/") }
  end
end
