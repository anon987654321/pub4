# frozen_string_literal: true

require "minitest/autorun"

# The home page's looks alternate: an even look's title moves to the second
# column, so its grid must mirror the odd one. The luxury surface set the
# columns once with a selector that outranks .amber-look:nth-child(even), so
# even titles landed in the narrow column and "Coffee" broke as "Coff / ee".
class LookGridMirrorTest < Minitest::Test
  SCSS = File.read(File.expand_path("../app/assets/stylesheets/application.scss", __dir__))

  def columns_for(selector)
    SCSS.scan(/#{Regexp.escape(selector)}\s*\{[^}]*?grid-template-columns:\s*([^;]+);/).flatten.last
  end

  def test_the_luxury_even_look_mirrors_the_luxury_odd_look
    odd = columns_for('body[data-surface="luxury"] .amber-look')
    even = columns_for('body[data-surface="luxury"] .amber-look:nth-child(even)')

    refute_nil odd, "the luxury look grid is gone"
    refute_nil even, "even looks take the odd grid, and their titles land in the narrow column"
    assert_equal odd.split(/\s+(?=minmax)/).reverse, even.split(/\s+(?=minmax)/)
  end
end
