# frozen_string_literal: true

# Minimal stub used by the test suite to verify that user‑defined code can be
# loaded without side effects or external dependencies.
#
# @api private
class Meme
  # Returns a cheesy greeting.
  #
  # @return [String] the literal `"OHAI!"`
  def i_can_has_cheezburger?
    "OHAI!"
  end

  # Returns an enthusiastic affirmation.
  #
  # @return [String] the literal `"YES!"`
  def will_it_blend?
    "YES!"
  end
end