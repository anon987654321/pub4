# frozen_string_literal: true

# A header carrying class="page-header" names the element twice: once in the
# tag, where the browser and every assistive technology already read it, and
# once in a class that only the stylesheet reads. The second name is the one
# that rots. It survives when the element changes, and someone must keep it in
# step by hand.
#
# The stylesheet does not need it. `header` selects a header. Where two headers
# on one page need different treatment, the discriminator is their context
# (main > header) or their accessible name, and both of those already have to be
# correct for the page to work — so styling cannot drift away from semantics the
# way a class can.
#
# BEM_IN_VIEWS covers the block__element spelling of this mistake. This covers
# the plain one, which is far more common in this tree.
#
# The backreference carries the whole rule: it fires only when the class repeats
# this element's own tag name. A section classed live-feed describes itself and
# stays; a section classed content-section restates itself and goes.
Law.define(:CLASS_RESTATES_TAG) do
  source "style.yml bare_tag_targeting — the tag is already the name"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<(header|footer|nav|main|section|article|aside|form|figure|dialog|details|summary|table)\b[^>]*class=["'][^"']*\1/) }
  fix "Select the bare tag in SCSS; discriminate by context or by accessible name, not by a class repeating the tag."
  bad  "<header class=\"page-header\">"
  good "<header>"
end
