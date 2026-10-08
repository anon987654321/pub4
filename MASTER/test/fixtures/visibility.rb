# frozen_string_literal: true
# instrument: code_lines=12 longest_method=1 public_methods=2

# Public means before `private`.
#
# ABSTRACTION counts public methods, and the 2026-08-12 finding that
# Constitution has 16 and Memory 17 turns entirely on where the counter stops.
# A counter that ignores visibility reports every class in the fold as a god
# class; one that stops at the wrong node reports none.
class Visibility
  def one
    1
  end

  def two
    2
  end

  private

  def hidden
    3
  end
end
