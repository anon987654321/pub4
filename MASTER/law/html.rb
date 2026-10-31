# frozen_string_literal: true

# law/html.rb — every html law, one Law.define per law.
#
# IMG_ALT and LAZY_IMAGES live once, in the registry (web_laws.rb): both
# judge attributes of a tag, and a tag is not a line — the attribute-per-line
# spelling put alt= and loading= one line below the detector, so every
# multi-line <img> was a finding. The registry versions flatten tags first.

Law.define(:ARIA_INTERACTIVE) do
  source "WAI-ARIA (W3C) — roles for interactive elements"
  detect { |line| line.match?(/<(div|span)\s+[^>]*onclick/) }
  fix "Add role= and tabindex= for accessibility."
  bad  "<div onclick=\"go()\">"
  good "<button onclick=\"go()\">"
end

# ARIA_LABELS lives once, in the registry (web_laws.rb): its detector
# flattens multi-line tags and honours label-wrapping before judging, and the
# per-line duplicate here flagged every attribute-per-line control as nameless
# — the playlist transport bar carried six labels and six findings at once.

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
  # A div grouping a dt/dd pair inside a <dl> is the HTML 5.2 idiom, not a
  # styling wrapper — the spec added it precisely so the pair could share a
  # layout box.
  #
  # The marker convention applies here as well: a bare div whose line carries
  # `scan: intentional` states its reason where the element lives — the grid
  # column wrapper is the layout, and the text it holds is anonymous (a
  # nickname row, a cart line) — so no semantic element would carry meaning
  # the div does not.
  detect { |line| line.match?(/<div\s*>/) && !line.match?(/<div>\s*(?:<%=\s*tag\.dt|<dt)/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Name the group with a semantic element, or drop the wrapper and select its children by structure."
  bad  "<div>"
  good "<section>"
end

Law.define(:BEM_IN_VIEWS) do
  source "style.yml bare_tag_targeting — no BEM in ERB"
  detect { |line| line.match?(/class=["'][^"']*__[^"']*["']/) }
  fix "Target bare tags in SCSS; remove __block__element classes from ERB."
  bad  "<div class=\"card__title\">"
  good "<h2>"
end

# One blank line separates two things. Two blank lines separate them by an
# amount nobody agreed on, and the amount is invisible — a reader cannot tell a
# deliberate double gap from a merged patch that left one behind, so the spacing
# stops carrying information the moment it varies.
#
# File-scoped because the defect is a relationship between lines: a single blank
# line is correct, and only its neighbour makes it wrong.
Law.define(:BLANK_LINE_RUN) do
  source "Strunk & White I.1 — vigorous writing is concise, and so is its spacing"
  scope :file
  # Whitespace-only lines count as blank: a line holding two spaces looks
  # identical to an empty one and is the usual way a run of them survives.
  #
  # It reads comments because it measures whitespace, and the engine blanks a
  # comment to a bare newline to keep line numbers. That turns any two-line
  # comment into a run this law then reports: a four-line `<%# … %>` block
  # explaining an opt-out, with one ordinary blank line above it, was five blank
  # lines by the time the detector saw it. A spacing law that cannot see the
  # comments is measuring a file nobody wrote.
  reads_comments true
  detect { |text| text.match?(/\n[ \t]*\n[ \t]*\n/) }
  fix "Collapse consecutive blank lines to one."
  bad  "<p>first</p>\n\n\n<p>second</p>\n"
  good "<p>first</p>\n\n<p>second</p>\n"
end

Law.define(:BUTTON_OVER_ANCHOR) do
  source "WAI-ARIA Authoring Practices — button vs link (W3C)"
  detect { |line| line.match?(/<a\s+href=["']#["']/) }
  fix "Use <button>. Accessible by default."
  bad  "<a href=\"#\">Open</a>"
  good "<button type=\"button\">Open</button>"
end

# A class that restates its own tag adds a second name that only the
# stylesheet reads — and the second name is the one that rots.
#
# The first version of this law believed context could always carry the
# distinction ("main > header"), and named page-header as its bad fixture.
# The rendered DOM refuted that on 2026-08-21: probed over CDP with all four
# surfaces booted, .page-header's parent varies by page (main#main-content on
# search, section.channels-index on channels), and the marketplace front page
# lays out FOUR header species at once — page-header, composer-header,
# marketplace-top-offers-header and the market-hero that sits as main's
# direct child and must NOT share their styling. No context selector
# discriminates what those prefixes discriminate; the prefix is the honest
# name for WHICH header this is, exactly the live-feed case the paragraph
# below always allowed.
#
# So the law now claims only what it can defend: a class whose distinguishing
# half is pure filler (content-, inner-, wrapper-, -area, -block…) restates
# the tag and goes. A class whose prefix names one of several coexisting
# species stays — that discrimination is its job.
#
# A section classed live-feed describes itself and stays; a section classed
# content-section restates itself and goes.
Law.define(:CLASS_RESTATES_TAG) do
  source "style.yml bare_tag_targeting — the tag is already the name"
  detect { |line| line.match?(/<(header|footer|nav|main|section|article|aside|form|figure|dialog|details|summary|table)\b[^>]*class=["'](?:[^"']*\s)?(?:(?:content|inner|outer|wrapper|container|box|main|site|app)-)?\1(?:-(?:content|inner|outer|wrapper|container|box|area|block))?(?:\s[^"']*)?["']/) }
  fix "Drop the filler class and select the bare tag; a prefix that names which of several coexisting elements this is may stay."
  bad  "<header class=\"content-header\">"
  good "<header class=\"page-header\">"
end

# HTML_LANG lives once, in the registry (web_laws.rb): it reads through
# tag_source, so an `<html` inside a comment, a string or an ERB expression
# is prose about the tag, not the tag. This bare line regex had no such
# filter — the tag_source family is why ARIA_LABELS and IMG_ALT retired the
# same way.

Law.define(:I18N_COVERAGE) do
  source "Rails i18n best practice (no hardcoded strings)"
  scope :file
  # Element content, not attribute text. Three shapes were being read as prose
  # and none of them renders as any:
  #
  # A `>` inside a quoted attribute closes nothing — `data-action="click->
  # media-picker#trigger"` made the Stimulus arrow look like a tag end, so the
  # attribute name after it counted as content and a fully translated button
  # was a finding. Quoted spans blank first.
  #
  # An ERB tag is blanked whole rather than left to look like a tag boundary.
  # `<%= @summary[:active_items] %> active</span>` is a real finding — "active"
  # is English on a Norwegian page — so the `%>` cannot simply be excluded; what
  # has to go is the expression inside it, which is Ruby and not prose.
  #
  # And an ERB comment renders nothing at all — including its continuation
  # lines, which a per-line detector cannot see past the line that opens the
  # comment. The comments are blanked before the lines are read.
  detect do |text|
    # The marker usually lives inside the ERB comment being blanked, so it is
    # consulted on the original line, which survives line-for-line.
    original = text.lines
    text.gsub(/<%#.*?%>/m) { |c| c.gsub(/[^\n]/, " ") }
        .each_line.with_index.any? do |line, i|
      next false if original[i].to_s.match?(/scan:\s*intentional\b/)

      line.gsub(/<%.*?%>/, " ")
          .gsub(/"[^"\n]*"|'[^'\n]*'/) { |m| "\0" * m.length }
          .match?(/>\s*[A-Za-z][^<]{3,}</)
    end
  end
  fix "Replace literal with t('.key')."
  bad  "<p>Welcome back</p>"
  good "<p><%= t('.welcome') %></p>"
end

# A document that declares no encoding leaves the browser to guess, and the
# guess is wrong often enough that WHATWG requires the declaration.
#
# Only a document can carry one. A partial has no head to put it in, so the
# earlier detector — anything lacking the meta tag — fired on all 423 partials
# in RAILS and on 5 layouts, and the 423 could not have complied if they tried.
# The guard asks whether this file is a document before asking whether it
# declares its encoding.
Law.define(:META_CHARSET) do
  source "HTML Living Standard — meta charset utf-8 (WHATWG)"
  scope :file
  # Both spellings count. The http-equiv form is the older one, and mail clients
  # honour it more reliably than the HTML5 short form — so shared/layouts/mailer
  # declares its encoding that way on purpose, and a detector accepting only the
  # short form called the one correct file in the tree an error.
  detect { |text| text.match?(/<html\b|<body\b/) && !text.match?(/<meta\s+charset=|charset=["']?utf-8/i) }
  fix "Add a UTF-8 charset declaration as the first element in head."
  bad  "<html><head><title>x</title></head></html>"
  good "<html><head><meta charset=\"UTF-8\"></head></html>"
end

# A script or style block written into a template is the html half of
# NO_MULTIPLE_LANGUAGES, split out so its detector can say what it means. The
# parent rule caught it by matching a language marker, which also matched every
# ERB tag in every view.
#
# A strict Content-Security-Policy cannot fingerprint an inline block without a
# nonce, the cache cannot hold it apart from the page carrying it, and every
# tool that reads stylesheets and scripts as files walks straight past it. A tag
# with src or href suffers none of that, so this ignores them.
Law.define(:NO_INLINE_SCRIPT_BLOCK) do
  source "CSP script-src / separation of concerns — assets are files"
  detect { |line| line.match?(/<script(?![^>]*\bsrc=)|<style\b(?![^>]*\bhref=)/) }
  fix "Move it to an asset file and reference it with javascript_include_tag or stylesheet_link_tag."
  bad  "<div><script>boot()</script></div>"
  good "<div></div>"
end

Law.define(:NO_INLINE_STYLES) do
  source "CSP / separation of concerns — no inline styles"
  # A style attribute carrying only custom properties is a data channel to
  # the stylesheet — style="--swatch: teal" hands a value to a rule that
  # lives in CSS (color: var(--swatch)), which is the separation this law
  # wants. A real property inline still fires.
  #
  # The marker convention the other laws honour applies here too: a line that
  # says `scan: intentional` carries its reason beside it — the mailer
  # preheader (mail clients load no bundle), AdSense's required inline
  # display on <ins>, a honeypot no stylesheet may reveal, and helpers whose
  # whole emission is one custom property the detector cannot see through
  # ERB. The marker is read on the line, so an intentional style cannot
  # silently cover its neighbours.
  detect { |line| (value = line[/\bstyle="([^"]*)"/, 1]) && !value.match?(/\A\s*(?:--[\w-]+:\s*[^;"]*;?\s*)*\z/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Extract to CSS class; pass dynamic values as custom properties."
  bad  "<p style=\"color:red\">"
  good "<p class=\"warn\" style=\"--share: 40%\">"
end

Law.define(:NO_JQUERY) do
  source "RAILS/__shared frontend convention"
  detect { |line| line.match?(/jQuery\(|\$\((?=\s*["\x27#.])/) }
  fix "Replace the selector call with a Stimulus target or querySelector."
  bad  "$('#menu').show()"
  good "document.querySelector('#menu').hidden = false"
end

# A link someone is paid for says so to the machine as well as to the reader:
# rel="sponsored" is how Google asks paid and affiliate links to be marked, and
# a commission link without it reads as an editorial recommendation. The
# commercial ones are the links that carry an affiliate URL or the
# outbound-click controller, which is how the apps attribute a click to a
# merchant. The visible label beside the link is VISUAL_DISCLOSURE_PROMINENCE's.
Law.define(:SPONSORED_LINK_REL) do
  source "Google Search Central, qualifying outbound links (rel=sponsored); markedsføringsloven § 3"
  tags %i[COMPLIANCE]
  fix "add rel=\"sponsored\" (with noopener) to the affiliate link"
  bad "<a href=\"<%= deal.affiliate_url %>\" target=\"_blank\">Buy</a>\n"
  good "<a href=\"<%= deal.affiliate_url %>\" target=\"_blank\" rel=\"sponsored noopener\">Buy</a>\n"
  check do |src, _path|
    # An <a> tag, stepping over ERB inside its attributes, or one link_to call.
    links = /<a\b(?:<%.*?%>|[^>])*>|<%=\s*link_to\b.*?%>/m
    findings = []
    src.scan(links) do
      link = Regexp.last_match(0)
      next unless link.match?(/outbound[_-]click|affiliate/i) && !link.match?(/\bsponsored\b/)

      line = src[0...Regexp.last_match.begin(0)].count("\n") + 1
      findings << finding(line:, message: "affiliate link without rel=\"sponsored\" — mark it as paid")
    end
    findings
  end
end

# A class should name what a thing is, not what it currently looks like. Words
# like dim, bold, small and red describe one rendering decision, so changing
# that decision means editing every view carrying the word, and the markup ends
# up asserting a colour it cannot guarantee.
#
# In this tree the cost already shows. The word dim sits on 301 elements across
# three apps and resolves to a different colour in each: --text-secondary in
# brgen, --color-grey-text in amber, --text-secondary in bsdports. The built
# stylesheets carry seven, six and four rules matching it. Two of amber's three
# bare declarations never take effect, and two of bsdports' do not either — they
# lose to a later rule of equal specificity, so the earlier ones are dead weight
# that would come alive if anyone reordered an @use.
#
# Nothing in the markup says which of those a given element asked for, because
# the markup asked only for "dim".
#
# The fix is often an element, not another class: small for a side comment,
# strong and em for emphasis, time for a timestamp. Those carry meaning to
# assistive technology as well as to the stylesheet, and no second declaration
# can quietly override them.
Law.define(:PRESENTATIONAL_CLASS_NAME) do
  source "CSS naming — classes name meaning, not appearance"
  # The marker convention applies: a class whose word is a domain term rather
  # than a rendering decision ("seller center", the management area) states so
  # at the element instead of being renamed away from its own meaning.
  detect { |line| line.match?(/class=["'][^"']*\b(?:dim|muted|faded|bold|italic|underline|small|big|large|tiny|left|right|center|centre|red|green|blue|grey|gray|white|black)\b/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Name the role, not the rendering — or use the element that already means it (small, strong, em, time)."
  bad  "<span class=\"dim\">posted just now</span>"
  good "<small>posted just now</small>"
end

Law.define(:SEMANTIC_ELEMENTS) do
  source "HTML5 semantics / WCAG 1.3.1 (W3C)"
  detect { |line| line.match?(/<div\s+class="(header|footer|nav|main|sidebar|article|section)"/) }
  fix "Use <header>, <footer>, <nav>, <main>, <aside>, <article>, <section>."
  bad  "<div class=\"header\">"
  good "<header>"
end

# A keyboard reader lands on the first focusable thing on the page and tabs
# through the whole navigation before reaching the content, on every page. The
# skip link is the bypass WCAG 2.4.1 asks for.
#
# It belongs to the layout, which is the only file that owns the first focusable
# element. The earlier detector — anything not mentioning a skip target — fired
# on all 423 partials in RAILS, none of which can hold one, and buried the 5
# layouts where the question is real.
# The registry twin knew two more things, ported with its retirement: only
# layouts own the first focusable element, and a mailer layout is not a page
# — no viewport to skip past, no #main-content to land on; both findings
# this rule ever produced in RAILS were mailer layouts.
Law.define(:SKIP_TO_MAIN) do
  source "WCAG 2.4.1 Bypass Blocks / style.yml accessibility"
  scope :file
  detect { |text| text.match?(/<body\b/) && !text.match?(/skip|#main-content/) }
  fix "Add a skip link to #main-content in the layout."
  bad  "<body><nav></nav><main></main></body>"
  good "<body><a href=\"#main-content\">skip</a><main id=\"main-content\"></main></body>"
end

# TAG_HELPER_OVER_MARKUP is retired, not moved. Its detector matched
# `<p><%= ... %></p>` and its siblings; PREFER_TAG_HELPERS in the registry
# (law/web.rb, SIMPLE_WRAPPER_TAG_RE) is a strict
# superset — the same shape plus div, span, li and label, and tolerant of
# attributes. Measured over 536 RAILS views: every one of this rule's 292
# findings was also one of the registry's, so it only ever double-reported.
#
# The reasoning it carried is kept, because it is the argument for the rule
# that survives: a tag around one expression leaves for Ruby, returns, and
# closes in HTML -- four context switches to emit one line. The tag builder
# writes the same thing as one expression, a third shorter, impossible to
# leave unclosed, escaping its attributes by construction rather than by the
# author remembering to.

Law.define(:UTILITY_CLASS_SOUP) do
  source "style.yml html.forbidden.framework_class_explosion"
  detect { |line| line.match?(/class=["'][^"']*(?:\b(?:mt|mb|ml|mr|px|py|col|row|d-flex|flex|grid|w-|h-)\b[^"']*){3,}[^"']*["']/i) }
  fix "Move layout to SCSS with bare tag targeting."
  bad  "<div class=\"row col mt mb\">"
  good "<div class=\"toolbar\">"
end
