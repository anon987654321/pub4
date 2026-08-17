# frozen_string_literal: true

# A class should name what a thing is, not what it currently looks like. Words
# like dim, bold, small and red describe one rendering decision, so changing
# that decision means editing every view carrying the word, and the markup ends
# up asserting a colour it cannot guarantee.
#
# In this tree the cost already shows. The word dim sits on 302 elements and two
# stylesheets declare it with different values — _minimal.scss picks
# --dark-grey and --text-base, _shell_widgets.scss picks --text-secondary and
# --text-sm. Import order decides which one an element gets, and nothing in the
# markup tells you which one you asked for.
#
# The fix is often an element, not another class: small for a side comment,
# strong and em for emphasis, time for a timestamp. Those carry meaning to
# assistive technology as well as to the stylesheet, and no second declaration
# can quietly override them.
Law.define(:PRESENTATIONAL_CLASS_NAME) do
  source "CSS naming — classes name meaning, not appearance"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/class=["'][^"']*\b(?:dim|muted|faded|bold|italic|underline|small|big|large|tiny|left|right|center|centre|red|green|blue|grey|gray|white|black)\b/) }
  fix "Name the role, not the rendering — or use the element that already means it (small, strong, em, time)."
  bad  "<span class=\"dim\">posted just now</span>"
  good "<small>posted just now</small>"
end
