# frozen_string_literal: true

# law/html.rb — every html law, one Law.define per law.
#
# IMG_ALT and LAZY_IMAGES live once, in the registry (web_laws.rb): both
# judge attributes of a tag, and a tag is not a line — the attribute-per-line
# spelling put alt= and loading= one line below the detector, so every
# multi-line <img> was a finding. The registry versions flatten tags first.

Law.define(:ARIA_INTERACTIVE) do
  source "WAI-ARIA (W3C) - roles for interactive elements"
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
  source "HTML5 semantics / WCAG 1.3.1 - an element with no meaning carries none"
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
  path "/app/views/"
  source "style.yml bare_tag_targeting - no BEM in ERB"
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
  source "Strunk & White I.1 - vigorous writing is concise, and so is its spacing"
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
  source "WAI-ARIA Authoring Practices - button vs link (W3C)"
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
  source "style.yml bare_tag_targeting - the tag is already the name"
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
  path "/app/views/"
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
  source "HTML Living Standard - meta charset utf-8 (WHATWG)"
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
  source "CSP script-src / separation of concerns - assets are files"
  detect { |line| line.match?(/<script(?![^>]*\bsrc=)|<style\b(?![^>]*\bhref=)/) }
  fix "Move it to an asset file and reference it with javascript_include_tag or stylesheet_link_tag."
  bad  "<div><script>boot()</script></div>"
  good "<div></div>"
end

Law.define(:NO_INLINE_STYLES) do
  source "CSP / separation of concerns - no inline styles"
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
      findings << finding(line:, message: "affiliate link without rel=\"sponsored\" - mark it as paid")
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
  source "CSS naming - classes name meaning, not appearance"
  # The marker convention applies: a class whose word is a domain term rather
  # than a rendering decision ("seller center", the management area) states so
  # at the element instead of being renamed away from its own meaning.
  detect { |line| line.match?(/class=["'][^"']*\b(?:dim|muted|faded|bold|italic|underline|small|big|large|tiny|left|right|center|centre|red|green|blue|grey|gray|white|black)\b/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Name the role, not the rendering - or use the element that already means it (small, strong, em, time)."
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
  path "/app/views/layouts/"
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
  path "/app/views/"
  source "style.yml html.forbidden.framework_class_explosion"
  detect { |line| line.match?(/class=["'][^"']*(?:\b(?:mt|mb|ml|mr|px|py|col|row|d-flex|flex|grid|w-|h-)\b[^"']*){3,}[^"']*["']/i) }
  fix "Move layout to SCSS with bare tag targeting."
  bad  "<div class=\"row col mt mb\">"
  good "<div class=\"toolbar\">"
end

# The design-book Laws over markup (Butterick, Krug, Norman, WCAG 2.x). Their rendered halves
# are adapters over a design_laws snapshot (Deploy::RenderedDesign), proved the same way.
require_relative "../checks/support/rendered_design"

module Law
  module Markup
    SNAP = Deploy::RenderedDesign
    VIEWS = Regexp.union(/\.(?:html\.)?erb\z|\.html\z/, SNAP::SNAPSHOT)
    TEMPLATES = %r{\.(?:html\.)?erb\z|\.html\z}
    PERSONAL = /e?mail|phone|\btel|telefon|mobil|name|navn|given|family|address|adresse|street|postal|
               postnummer|zip|city|country|username|brukernavn|password|passord|otp|one_time|cc_|card|
               (?:\A|_)(?:kode|land|sted|gate)(?:\z|_)/xi
    FIELD = /\b(?:text|email|telephone|phone|password|number|search|url)_field(?:_tag)?\b|<input\b/

    NUMERIC = /postnummer|postal|zip|otp|one_time|(?:\A|_)kode(?:\z|_)/i
    LABEL = /\A\s*(?:E-?post|Telefon|Tlf|Pris|Dato|Email|Phone|Price|Date)\s*:?\s*\z/i
    SELF_EVIDENT = /<%=\s*(?:mail_to|phone_to|number_to_currency|time_tag|l)\b/
    ACTION = /(?:button_to|\.submit|button_tag)\s*\(?\s*((?:t\(\s*)?["'][^"']+["']\)?)|
              link_to\s*\(?\s*((?:t\(\s*)?["'][^"']+["']\)?)(?=.*class:\s*["'][^"']*\bbutton)/x
    ICONS = %r{<svg\b.*?</svg>|<img\b[^>]*>|<i\b[^>]*></i>|<%=\s*(?:icon|inline_svg\w*|svg_tag|image_tag)\b.*?%>}m

    module_function

    def set_to(attribute, value) = /#{attribute}(?::|=)\s*["']#{value}/

    def continues?(text) = text.rstrip.end_with?(",", "(") || (text.include?("<input") && !text.include?(">"))

    # A helper call or tag that continues over the next lines, joined into one statement.
    def statements(src, opener)
      lines = src.lines
      lines.each_index.select { |index| lines[index].match?(opener) }.map do |index|
        text = lines[index].dup
        lines[index + 1, 6].to_a.each do |more|
          break unless continues?(text)

          text << more
        end
        [text.gsub(/\s+/, " "), index + 1]
      end
    end

    def field_name(text)
      text[/_field(?:_tag)?\s*\(?\s*:?["']?(\w+)/, 1] || text[/\bname=["']([^"']+)/, 1] || text[/\bid=["']([^"']+)/, 1]
    end

    def purpose(text)
      return if text.match?(/type=["']?(?:hidden|submit|button|checkbox|radio)/)

      name = field_name(text).to_s
      return unless name.match?(PERSONAL)
      return "#{name} turns autocomplete off - name its purpose (error)" if text.match?(set_to("autocomplete", "off"))
      return "#{name} asks for personal data with no autocomplete token" unless text.include?("autocomplete")

      "#{name} wants inputmode numeric (info)" if name.match?(NUMERIC) && !text.match?(set_to("inputmode", "numeric"))
    end

    def words(label) = label.to_s.gsub(/%\{\w+\}|<[^>]+>/, " ").split.size

    def locale_file(file)
      YAML.safe_load_file(file, aliases: true) || {}
    rescue Psych::Exception # scan: intentional - an unreadable locale resolves no label; YAML_SYNTAX reports it
      {}
    end

    # t("absolute.key") read from the app's nb locale; a literal is its own label.
    def label(raw, path)
      key = raw[/\At\(\s*["']([\w.]+)["']/, 1] or return raw[/\A["']([^"']+)["']/, 1]
      root = path.to_s[%r{\A.*?/(?:RAILS/[^/]+|MASTER/web)(?=/)}] or return
      Dir[File.join(root, "config/locales/nb*.yml")].each do |file|
        found = locale_file(file).dig("nb", *key.split("."))
        return found if found.is_a?(String)
      end
      nil
    end

    def action_label(line)
      button = line[%r{<button\b[^>]*>([^<]{2,})</button>}, 1]&.then { |text| "\"#{text.strip}\"" }
      line.match(ACTION)&.captures&.compact&.first || button
    end

    def icon_only?(inner)
      rest = inner.gsub(ICONS, "").gsub(/<[^>]+>/, "")
      rest.strip.empty? && rest != inner
    end

    def icon_named?(tag)
      SNAP::AccessLaws.icon_words.include?(SNAP::AccessLaws.normal(tag[/aria-label=["']([^"']+)/, 1]))
    end

    def rendered(id) = ->(text, file) { SNAP.findings(id, text, file).map { |hit| finding(**hit) } }

    def page(*elements) = SNAP.fixture(elements:)

    # One ERB output tag around a Ruby expression, for the fixtures.
    ERB_TAG = [
      "<%= ",
      " %>",
    ].freeze

    def erb(code) = "#{ERB_TAG.first}#{code}#{ERB_TAG.last}\n"

    def control(key, **fields) = SNAP.element(key, interactive: true, **fields)

    def named(name, visible) = control("button", visible_text: visible, name:, attrs: { "aria-label" => name })

    def paste_blocker(line, auth)
      return "paste is blocked on a sign-in field" if line.match?(/\bonpaste\s*=|paste->/)
      off = line.match?(/password/i) && line.match?(set_to("autocomplete", "off"))
      return "password field turns autofill off" if off

      "a CAPTCHA on sign-in with no alternative (warning)" if auth && line.match?(/g-recaptcha|h-captcha|captcha/i)
    end

    def name_mismatch(line)
      norm = SNAP::AccessLaws.method(:normal)
      tag = line.match(%r{<(button|a)\b[^>]*aria-label=["']([^"']+)["'][^>]*>([^<]+)</\1>})
      keys = line.match(/\bt\(\s*["']([\w.]+)["']\).*aria:\s*\{\s*label:\s*t\(\s*["']([\w.]+)["']/)
      hidden = tag && !norm.(tag[2]).include?(norm.(tag[3]))
      return "aria-label #{tag[2].inspect} hides the visible #{tag[3].strip.inspect}" if hidden

      "visible text #{keys[1]} and name #{keys[2]} are different keys" if keys && keys[1] != keys[2]
    end

    def unneeded_label(lines, index)
      tag = lines[index].match(%r{<(dt|th|span|strong|b|label)\b([^>]*)>([^<]*)</\1>}) or return
      return if tag[2].match?(/visually-hidden|sr-only/) || !tag[3].match?(LABEL)

      follows = lines[index][tag.end(0)..].to_s + lines[index + 1].to_s
      "#{tag[3].strip.inspect} labels data that says what it is" if follows.match?(SELF_EVIDENT)
    end
  end

  M = Markup

  ::Law.define(:FIELD_PURPOSE_DECLARED) do
    source "WCAG 1.3.5 Identify Input Purpose, AA; Wroblewski, Web Form Design (2008); Baymard checkout research"
    tags %i[ACCESSIBILITY]
    path M::TEMPLATES
    fix "Give each personal-data field its autofill token (autocomplete: \"postal-code\") and inputmode for digits."
    bad "<%= f.text_field :postnummer %>\n"
    good "<%= f.text_field :postnummer, autocomplete: \"postal-code\", inputmode: \"numeric\" %>\n"
    check do |src, _path|
      M.statements(src, M::FIELD).filter_map { |text, line| (message = M.purpose(text)) && finding(line:, message:) }
    end
  end

  ::Law.define(:AUTH_ALLOWS_PASTE) do
    source "WCAG 2.2 SC 3.3.8 Accessible Authentication (Minimum), AA"
    tags %i[ACCESSIBILITY SECURITY]
    path Regexp.union(M::TEMPLATES, /\.js\z/)
    fix "Let password and one-time-code fields take paste and autofill (current-password, one-time-code); " \
        "no puzzle without an alternative."
    bad "<input type=\"password\" onpaste=\"return false\">\n"
    good "<input type=\"password\" autocomplete=\"current-password\">\n"
    check do |src, path|
      auth = path.to_s.match?(/session|registration|password|login|signup|sign_in|sign_up/)
      src.each_line.with_index(1).filter_map do |line, n|
        (message = M.paste_blocker(line, auth)) && finding(line: n, message:)
      end
    end
    adapter(:whole_file, languages: %i[javascript], bad: "el.addEventListener(\"paste\", (e) => e.preventDefault())\n",
                         good: "el.addEventListener(\"input\", (e) => this.check(e))\n") do |src, _file|
      blocks = src.match?(/addEventListener\(\s*["']paste["']|\.onpaste\s*=/) && src.include?("preventDefault")
      at = src.lines.index { |line| line.include?("paste") }.to_i + 1
      blocks ? [finding(line: at, message: "paste is prevented")] : []
    end
  end

  ::Law.define(:ACTION_LABEL_BRIEF) do
    source "Krug, Don't Make Me Think: omit half the words, then half again; minimalism.yml microcopy.label_max_words"
    tags %i[BE_CONCISE]
    path %r{\.(?:html\.)?erb\z}
    reads_beyond_file true
    ask "Does each button or action label lead with its verb? Rank the labels that do not and explain why; " \
        "the model may rank and explain but a person decides."
    practice "A model's verdict on verb-first labels is a ranked suggestion with its reason; the operator decides."
    fix "Cut the label to three words or fewer, verb first: \"Legg i kurv\"."
    bad "<%= button_to \"Trykk her hvis du vil legge varen i kurven\", cart_path %>\n"
    good "<%= button_to \"Legg i kurv\", cart_path %>\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        count = M.words(M.label(M.action_label(line).to_s, path))
        level = count > 5 ? "warning" : "info"
        finding(line: n, message: "action label of #{count} words - #{level}: three, verb first") if count > 3
      end
    end
  end

  ::Law.define(:SELF_EVIDENT_DATA_UNLABELLED) do
    source "Refactoring UI, labels are a last resort"
    tags %i[DESIGN UX]
    path %r{/app/views/(?!.*_form).*\.erb\z}
    ask "Does this display view label data whose form already says what it is (an email, a phone number, a price, " \
        "a date)? Rank and explain; a person decides."
    practice "A model may rank unneeded labels and explain them; the operator decides which stay."
    fix "Drop the visible label and keep it for assistive tech (a visually-hidden dt, or one label for the list)."
    bad "<dt>E-post:</dt>\n<dd><%= mail_to user.email %></dd>\n"
    good "<dd><%= mail_to user.email %></dd>\n"
    check do |src, _path|
      lines = src.lines
      lines.each_index.filter_map do |index|
        (message = M.unneeded_label(lines, index)) && finding(line: index + 1, message:)
      end
    end
  end

  ::Law.define(:EMPHASIS_ONE_DEVICE) do
    source "Butterick, bold or italic sparingly, never both; underline only for links"
    tags %i[TYPOGRAPHY]
    path Regexp.union(M::VIEWS, /\.s?css\z/)
    fix "Emphasise with one device: <strong> or <em>, never both; keep underline for links."
    bad "<p><strong><em>Gratis levering</em></strong></p>\n"
    good "<p><strong>Gratis levering</strong></p>\n"
    nested = %r{<(?:strong|b)>\s*<(?:em|i)>|<(?:em|i)>\s*<(?:strong|b)>}
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        finding(line: n, message: "bold and italic at once") if line.match?(nested)
      end
    end
    adapter(:whole_file, languages: %i[css scss], bad: ".deal { font-weight: 700; font-style: italic; }\n",
                         good: ".deal { font-weight: 700; }\n") do |src, _file|
      src.scan(/[^{}]*\{([^{}]*)\}/).filter_map do |(body)|
        next unless body.match?(/font-weight:\s*(?:bold|[6-9]00)/) && body.match?(/font-style:\s*italic/)

        finding(line: src[0, src.index(body)].count("\n") + 1, message: "a rule sets bold and italic at once")
      end
    end
    underlined = M::SNAP.element("span.deal", decoration: "underline")
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE, bad: M.page(underlined),
                          good: M.page(M::SNAP.element("span.deal")), &M.rendered(:EMPHASIS_ONE_DEVICE))
  end

  ::Law.define(:ONE_PRIMARY_ACTION) do
    source "Refactoring UI, button hierarchy; Von Restorff (Yablonski, Laws of UX); visual_identity.composition"
    tags %i[DESIGN UX]
    path M::VIEWS
    fix "Fill one action per view (button-primary); give the rest button-ghost or button-link."
    publish = M.erb("button_to \"Publiser\", posts_path, class: \"button-primary\"")
    bad publish + M.erb("link_to \"Del\", share_path, class: \"button-primary\"")
    good publish + M.erb("link_to \"Del\", share_path, class: \"button-ghost\"")
    check do |src, _path|
      hits = src.each_line.with_index(1).select { |line, _n| line.match?(/\bbutton-primary\b/) }
      message = "#{hits.size} primary actions in one view - one is primary"
      hits.drop(1).map { |_line, n| finding(line: n, message:) }
    end
    fill = [0, 80, 200, 1]
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.control("button.a", bg: fill), M.control("button.b", bg: fill)),
                          good: M.page(M.control("button.a", bg: fill), M.control("button.b")),
                          &M.rendered(:ONE_PRIMARY_ACTION))
  end

  ::Law.define(:LABEL_IN_NAME) do
    source "WCAG 2.5.3 Label in Name, A"
    tags %i[ACCESSIBILITY]
    path M::VIEWS
    fix "Make the accessible name contain the visible text: drop the aria-label, or extend the words shown."
    bad "<button aria-label=\"Send inn\">Lagre</button>\n"
    good "<button aria-label=\"Lagre annonse\">Lagre</button>\n"
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        (message = M.name_mismatch(line)) && finding(line: n, message:)
      end
    end
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.named("Send inn", "Lagre")), good: M.page(M.named("Lagre annonse", "Lagre")),
                          &M.rendered(:LABEL_IN_NAME))
  end

  ::Law.define(:ICON_CARRIES_WORD) do
    source "Norman, signifiers; Krug; minimalism.yml law.icon_policy, words before icons"
    tags %i[ACCESSIBILITY DESIGN]
    path M::VIEWS
    fix "Give the icon its word (\"Fremhev\") or use the word alone; minimalism.yml icon_words_optional may go bare."
    bad "<button class=\"boost\"><svg viewBox=\"0 0 9 9\"><path d=\"M0 0h9\"/></svg></button>\n"
    good "<button class=\"boost\"><svg viewBox=\"0 0 9 9\"><path d=\"M0 0h9\"/></svg> Fremhev</button>\n"
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        tag = line.match(%r{<(button|a)\b([^>]*)>(.*?)</\1>}) or next
        finding(line: n, message: "icon-only #{tag[1]} with no word") if M.icon_only?(tag[3]) && !M.icon_named?(tag[2])
      end
    end
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.control("button.boost", icon: true, visible_text: "", name: "Boost")),
                          good: M.page(M.control("button.boost", icon: true, visible_text: "Fremhev", name: "Fremhev")),
                          &M.rendered(:ICON_CARRIES_WORD))
  end
end
