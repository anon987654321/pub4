# frozen_string_literal: true

module Pub4
  # Ratchet: empty-state titles and live-search placeholders must go through
  # I18n (t(...)), not hardcoded English. Default locale is :nb across the
  # family — raw "No …" / "Search …" re-introduces EN chrome on every surface.
  #
  # Mirrors empty_state_lint: baseline 0, never raise to silence new debt.
  # Opt out a deliberate EN-only string with: <%# chrome_i18n: ok %>
  #
  # MASTER playbook: design_rules.yml#ui_polish + surface_rules ERB_HARDCODED_CHROME.
  module ChromeI18nLint
    # title: "No …" / title: "Nothing …" without t(
    EMPTY_TITLE = /
      title:\s*
      (?:
        "(?:No\s|Nothing\s)[^"]{0,80}"
        |
        '(?:No\s|Nothing\s)[^']{0,80}'
      )
    /x

    # placeholder: "Search …" without t(
    SEARCH_PLACEHOLDER = /
      placeholder:\s*
      (?:
        "Search[^"]{0,80}"
        |
        'Search[^']{0,80}'
      )
    /x

    # aria-label="…" / aria: { label: "…" } with a literal string.
    #
    # RAILS/gates/data/GATE_ADEQUACY.md gap 2: "chrome_i18n_lint only empty titles +
    # search placeholders; secondary aria-labels still EN." A screen-reader user on
    # :nb hears English for every one of them, and until this rule existed the number
    # was unknown — which is the actual problem. It is 172 (measured 2026-08-01, all
    # three apps plus the shared engine), so the baseline is 172, not 0: translating
    # them needs Norwegian copy, not a regex, and 172 is the debt this measures rather
    # than pretends away.
    #
    # Same ratchet contract as empty_state_lint, which went 48 → 0 this way.
    ARIA_LABEL = /
      (?:aria-label|aria-roledescription)\s*=\s*"[^"<%]{2,80}"
      |
      aria:\s*\{[^}]*?label:\s*"[^"<%]{2,80}"
    /x

    # notice:/alert: with a literal string, in a controller.
    #
    # The three rules above read views, and that scope was the whole blind spot:
    # chrome i18n was recorded as landed and is, while every successful
    # create/update/destroy still answered with an English toast over a Norwegian
    # page. A class nothing measures is a class nobody is holding, so this rule
    # exists before the copy does — the strings can then come down one at a time
    # against a number that can only fall.
    CONTROLLER_FLASH = /
      (?:notice|alert):\s*
      (?:
        "[A-Z][^"]{2,120}"
        |
        '[A-Z][^']{2,120}'
      )
    /x

    # t("key", default: "English") in a shipped view.
    #
    # The most effective hiding place in the codebase, because it defeats two guards
    # at once: this lint skips any line containing t( (it looks for strings that
    # never reach I18n at all), and i18n_resolution_test deliberately ignores keys
    # carrying a default, since a default means the key is optional.
    # config.i18n.raise_on_missing_translations does not fire either — a default IS
    # the translation as far as Rails is concerned.
    #
    # So the ambient chat widget shipped fourteen English strings to amber and
    # bsdports, including every "why you are not in #nearby" recovery message, and
    # nothing in the tree could report it. A default belongs in library code that
    # cannot know its host's locales; in a view it is a hardcoded string with an
    # alibi.
    TRANSLATE_DEFAULT = /\bt\(\s*["'][\w.]+["']\s*,\s*default:/
    OPT_OUT = "chrome_i18n: ok"

    # Per kind, because they are not the same debt. A new hardcoded empty title is a
    # regression against a solved problem; an aria-label is one more of 158.
    BASELINES = {
      "empty_title" => 0,
      "search_placeholder" => 0,
      # 172 → 169 → 141 → 135 → 134 (2026-08-04) → 133 → 127 (2026-08-10):
      # bsdports ports/show, then its index, list, categories and maintainers
      # views, five amber views, and tv/home. One of those was not a fix —
      # amber's .compose-fab carried an aria-label and the element was deleted,
      # having been invisible since shared/_shell.scss hid it. The last six are
      # amber's footer, whose column labels were hardcoded English until it
      # gained a language switcher. Down only.
      #
      # → 122 (2026-08-12): fell out of the visible-copy pass, not aimed at.
      # amber's declutter box, live-stream and profile headers and the outfit
      # generator, plus dating's Essentials legend. What is left is 39 aria-only
      # strings the same pass measured but did not translate — the count is not
      # the work item, that list is.
      #
      # → 119: the map HUD region, the message article, amber's palette section
      # and its logo svg. Found by a text-node scan run against the merged tree
      # after that pass, which is the only reason they were separable from it.
      # → 118 (2026-08-13), raised from 117, and the raise is the point.
      #
      # This ratchet and translate_default below both went down twice in two days
      # on a tree three sessions were editing, and both immediately measured +1
      # against their own new floor. That is not a regression in the views; it is
      # what ratcheting on a moving tree does — a session records a low that was
      # not its own to hold, and the next measurement fails. MASTER/DEBT.md's
      # Spine Ceiling entry states the rule already: ratchet once, at the end of a
      # session, on a settled tree.
      #
      # It cost something real. amber had not deployed since 2026-08-12 08:49 and
      # nobody knew why: this lint runs across the whole family from the shared
      # engine, so a +1 in a brgen view — communities/show.html.erb, edited by
      # another session at 15:35 today — failed amber's CI gate, and amber's
      # rendered pages were still preloading morphdom from ga.jspm.io and
      # @rails/request.js from jsDelivr, three weeks after both were vendored.
      #
      # So these two are set to the measured truth rather than chased down again,
      # and the next move on either is to lower it once, deliberately, when the
      # tree is quiet — not opportunistically because a measurement came in low.
      #
      # → 107 (2026-08-14). This is that deliberate lowering, and the condition
      # above is what took the time: 107 is not a measurement that came in low,
      # it is the number this rule has returned on every run across an eleven-hour
      # session, re-measured three times back to back before being written down.
      # The eleven that went are aria-labels that became keys while the engines
      # were being worked over.
      #
      # What the note above is really guarding is that this file is read from the
      # shared engine, so the number is the whole family's: a +1 in a brgen view
      # fails amber's CI, which is how amber sat undeployed for a day. Recording
      # the true low is still right — a baseline nobody trusts is worse — but
      # anyone adding an unlocalised aria-label will meet it in another app.
      # 107 -> 105 on 2026-08-16. Two aria-labels were translated on main and
      # the baseline did not follow them down, which is the half of this ratchet
      # that keeps it honest: a floor nobody lowers stops being a floor.
      # 34 is what is left after every literal aria-label in brgen and its five
      # verticals became an aria.* key. The remainder is amber, bsdports and
      # shared, measured on this tree.
      "aria_label" => 34,
      # 169 (first run, 2026-08-11: amber 48, brgen engines 48, brgen host 44,
      # shared 28, bsdports 1) → 141. The hand count that opened this debt said 144
      # and was blind to shared/app/controllers, whose sites ship to all three apps
      # at once — which is also why those went first. Their keys are shared.flash.*
      # in social.{nb,en}.yml, pinned by RAILS/test/app_flash_i18n_test.rb.
      # 141 → 48: amber (48), the brgen host (44) and bsdports (1) followed, each
      # into its own app-level flash: namespace, reusing shared.flash.* for the
      # sentences the engine already owns (not_authorized, rate_limited). What is
      # left is the five brgen engines. Down only.
      # 0 as of 2026-08-12. The remaining 48 were all in the five brgen engines,
      # nested per engine as flash.<engine>.* in brgen's locales; the eleven
      # "Not allowed"/"Not authorized" copies became shared.flash.not_authorized
      # and "Try again later." became shared.flash.rate_limited. A ratchet at zero
      # is a ban, which is what this should have been from the start — 169 was
      # only ever a ratchet because it could not be paid off in one pass.
      "controller_flash" => 0,
      # Measured 2026-08-11 by this rule: 216 lines. (A looser hand grep said 231 —
      # it counted occurrences, not lines, which is the reminder that the number to
      # ratchet is always the instrument's own.) A ratchet rather than a ban,
      # because 216 cannot come down in one pass — but the chat
      # widget's 18 already did, and every one that goes is a string that can no
      # longer hide from the other three rules here. Down only.
      # 2026-08-12: 215. The affiliate sidebar's three hardcoded strings became
      # affiliate.* keys in both brgen locales.
      # → 215 (2026-08-13), raised for the same reason as aria_label above; read
      # that comment before lowering either of them.
      # → 211 (2026-08-14), lowered with it and on the same evidence: stable
      # across the session and across three consecutive measurements.
      # 211 -> 208, same reason and same day as aria_label above.
      # 195 is what is left after the front page stopped carrying a second row of
      # feed tabs. Following and Communities moved onto the nav bar with their
      # keys rather than their English defaults; a string becoming a key is one
      # fewer literal in this column and in aria_label.
      "translate_default" => 195,
    }.freeze

    # Kept for callers that referenced the old single number.
    BASELINE = 0

    Finding = Struct.new(:file, :line, :kind)

    module_function

    def counts(findings = scan)
      BASELINES.keys.to_h { |kind| [kind, findings.count { |f| f.kind == kind }] }
    end

    def over_baseline(findings = scan)
      counts(findings).filter_map do |kind, count|
        baseline = BASELINES.fetch(kind)
        "#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})" if count > baseline
      end
    end

    def run
      findings = scan
      counts(findings).each do |kind, count|
        baseline = BASELINES.fetch(kind)
        note = count < baseline ? " — under baseline, lower it" : ""
        puts "chrome_i18n_lint: #{kind} #{count} (baseline #{baseline})#{note}"
      end

      exceeded = over_baseline(findings)
      offenders = findings.select { |f| exceeded.any? { |line| line.start_with?("#{f.kind}:") } }
      offenders.first(30).each { |f| puts "  #{f.file}:#{f.line} [#{f.kind}]" }
      puts "  …" if offenders.size > 30

      return true if exceeded.empty?

      warn "chrome_i18n_lint: exceeds baseline — #{exceeded.join("; ")}"
      warn "chrome_i18n_lint: use t(\"empty.*\") / t(\"search.*\") / t(\"a11y.*\") or mark #{OPT_OUT}"
      false
    end

    def rails_root
      File.expand_path("../../..", __dir__)
    end

    # brgen's verticals moved to engines/<name>/app/views, which the single-level
    # glob never matched. The aria_label count fell 169 -> 89 on the extraction and
    # read as an 80-finding improvement; it was the lint going blind to 57 views.
    def view_paths
      Dir.glob(File.join(rails_root, "*/app/views/**/*.erb")) +
        Dir.glob(File.join(rails_root, "*/engines/*/app/views/**/*.erb"))
    end

    # Controllers, for CONTROLLER_FLASH. Same two-level shape as view_paths, and
    # for the same reason: a single-level glob goes blind to the five engines.
    def controller_paths
      Dir.glob(File.join(rails_root, "*/app/controllers/**/*.rb")) +
        Dir.glob(File.join(rails_root, "*/engines/*/app/controllers/**/*.rb"))
    end

    VIEW_RULES = { "empty_title" => EMPTY_TITLE, "search_placeholder" => SEARCH_PLACEHOLDER,
                   "aria_label" => ARIA_LABEL }.freeze
    CONTROLLER_RULES = { "controller_flash" => CONTROLLER_FLASH }.freeze
    DEFAULT_RULES = { "translate_default" => TRANSLATE_DEFAULT }.freeze

    def scan
      # Doc comment inside the partial itself is not a call site.
      views = view_paths.sort.reject { |path| path.end_with?("shared/_empty_state.html.erb") }

      views.flat_map { |path| findings_in(path, VIEW_RULES) } +
        controller_paths.sort.flat_map { |path| findings_in(path, CONTROLLER_RULES) } +
        # skip_translated: false — this rule looks FOR a t( call rather than for a
        # string that never reached one.
        views.flat_map { |path| findings_in(path, DEFAULT_RULES, skip_translated: false) }
    end

    def findings_in(path, rules, skip_translated: true)
      lines = File.readlines(path, encoding: "UTF-8")
      lines.each_with_index.filter_map do |line, i|
        next if skip_translated && (line.include?("t(") || line.include?("I18n.t"))
        next if comment_or_opt_out?(lines, i)

        kind, = rules.find { |_, pattern| line.match?(pattern) }
        Finding.new(rel(path), i + 1, kind) if kind
      end
    end

    def rel(path)
      path.sub("#{rails_root}/", "")
    end

    def comment_or_opt_out?(lines, index)
      window = lines[[index - 1, 0].max..index].join
      window.include?(OPT_OUT) || window.lstrip.start_with?("<%#", "#")
    end
  end
end

exit(Pub4::ChromeI18nLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
