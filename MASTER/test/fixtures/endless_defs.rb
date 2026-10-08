# frozen_string_literal: true
# instrument: code_lines=8 longest_method=1 public_methods=4

# The case a hand-rolled counter gets wrong.
#
# `def a = 1` is a complete method on one line. A regex counter that finds `def`
# and then scans forward to the next `end` reads all three endless defs plus
# `d` as one method running to the end of the class, and reports a tightly
# factored file as sprawling. That number is plausible enough to reason from,
# which is what makes it expensive: a 2026-08-12 reconnaissance pass concluded
# MASTER's longest method was 60 lines when it was 34, and nearly acted on it.
#
# Prism gets this right because an endless def has start_line == end_line.
class EndlessDefs
  def a = 1
  def b = 2
  def c = 3

  def d
    a + b
  end
end
