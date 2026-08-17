# frozen_string_literal: true

# A paragraph tag wrapped around a single template expression opens in HTML,
# leaves for Ruby, returns, and closes in HTML — four context switches to emit
# one line of text. Rails' tag builder writes the same thing as one expression:
# a third shorter, impossible to leave unclosed, and escaping its attributes by
# construction instead of by the author remembering to.
#
# Scoped to elements whose entire body is a single template expression. Markup
# with real structure inside it reads better as markup; a tag around one value
# is a method call written the long way.
Law.define(:TAG_HELPER_OVER_MARKUP) do
  source "Rails ActionView::Helpers::TagHelper — one expression, not four context switches"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(%r{<(p|small|strong|em|h[1-6]|figcaption|legend|caption|dt|dd)>\s*<%=[^%]*%>\s*</\1>}) }
  fix "Use the tag builder, as in tag.p of a translated string."
  bad  "<p><%= t(\"greeting\") %></p>"
  good "<%= tag.p t(\"greeting\") %>"
end
