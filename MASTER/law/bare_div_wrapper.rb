# frozen_string_literal: true

# SEMANTIC_ELEMENTS catches a div whose class is exactly a landmark name. This is
# the other half of divitis and the more common one: a div carrying nothing at
# all. It has no class, no id, no role and no data attribute, so it contributes
# no meaning to the document, no hook to the stylesheet and no target to a
# script. It exists because someone needed somewhere to hang a flex container
# and reached for the generic element.
#
# The fix is an element that says what the group is (section, article, header,
# ul) — or nothing. A wrapper whose only job was layout disappears once the
# parent becomes a grid, or once the stylesheet selects its children by
# structure.
Law.define(:BARE_DIV_WRAPPER) do
  source "HTML5 semantics / WCAG 1.3.1 — an element with no meaning carries none"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<div\s*>/) }
  fix "Name the group with a semantic element, or drop the wrapper and select its children by structure."
  bad  "<div>"
  good "<section>"
end
