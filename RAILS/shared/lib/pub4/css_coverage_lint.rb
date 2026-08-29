# frozen_string_literal: true

require_relative "baseline_ratchet"

require "set"

module Pub4
  # CSS drift, in both directions.
  #
  # The register has carried `rails_unused_css_selectors` (102 selectors with no
  # markup) since the 2026-08-10 audit, and admitted in its own entry that no
  # committed tool reproduces the number. The opposite direction — a class an ERB
  # template asks for that no stylesheet defines — was never measured at all, and it
  # is the more interesting half: an unused selector is dead weight, while an
  # undefined class is a hook the author expected to do something. Both are the same
  # defect this repo keeps finding, a declaration with no reader, pointing opposite
  # ways.
  #
  # Measured 2026-08-11 against the compiled bundles as well as the sources, because
  # the bundle is what production serves: none of the reported classes has a rule in
  # brgen's, amber's or bsdports' application.css.
  #
  #   undefined_class — used in markup, defined nowhere. Either a missing style or
  #     dead markup; which one is a design decision, so this counts rather than fixes.
  #   unused_selector — defined, and no markup names it. Ratcheted with a wide
  #     tolerance on purpose: class names are also composed at runtime
  #     (`"card card--#{kind}"`), so a literal search cannot prove death, which is
  #     exactly the caveat the register entry records.
  module CssCoverageLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    TREES = (APPS + %w[shared]).freeze
    OPT_OUT = "css_coverage: ok"

    # Applied by JS, by the framework, or by a gate — never written in a stylesheet.
    #
    # The last three are styled by an inline attribute on the element, each for a
    # documented reason: the icon sprite must be width/height 0 rather than
    # display:none or <use> stops resolving in several browsers, the honeypot is
    # positioned off-screen inline so no stylesheet can accidentally reveal it, and the
    # scroll sentinel is a zero-height JS target. `swiper` and `adsbygoogle` belong to
    # Swiper and Google; writing rules for them would be styling someone else's API.
    EXTERNAL = %w[
      hidden turbo-progress-bar translation_missing
      nav-visible active current selected open
      adsbygoogle swiper swiper-wrapper
      icon-sprite hp-field infinite-scroll-sentinel
      battery-low battery-charging page-hidden
      network-slow network-save-data power-constrained decorative-motion
    ].to_set

    # Measured 2026-08-11: undefined_class 128 reported → 96 real → 4 remaining.
    #
    # 128 → 96 was the instrument getting honest. It read only .scss/.css and so
    # reported every mail-* class and every legal-* class as undefined; both were wrong.
    # Email cannot load an asset bundle, so the mailer layout defines its classes in an
    # inline <style>, and brgen's _site_legal_footer carries a <style> block that styles
    # the three legal pages. Inline blocks are read now.
    #
    # 96 → 4 was the work: 63 classes were styled in the *_coverage_fills.scss files and
    # the engines' own stylesheets, token-only, and the rest were classified rather than
    # invented for — a class that always shares its element with a styled sibling
    # inherits from it, and a class that names the Stimulus controller mounted on the
    # same element is that controller's identity.
    #
    # The 4 that remain are single-word legacy names — .inline, .post, .text, .list —
    # each on one surface, each doing nothing. They are markup to delete rather than
    # styles to write, and deleting a class that short wants a human who can grep for it
    # in a template language a regex reads badly.
    #
    # unused_selector 266, recorded rather than chased, per the register's own caveat
    # that a literal search cannot prove a runtime-composed class name is dead.
    # 4 → 35 on 2026-08-16, and this raise is a report rather than a tolerance.
    #
    # The four legacy single-word names above are still four. The other 31 are
    # two whole features that have views and no stylesheet at all:
    #
    #   events   9 classes — event-card, event-card-media, event-card-body,
    #            event-list, event-list--past, event-detail, event-hero,
    #            attendee-list, rsvp-form, rsvp-bar
    #   stories  7 classes — story-rings, story-ring-name, story-ring-count,
    #            story-ring-nav, story-viewer, story-viewer-head, story-media,
    #            story-caption, viewer-list
    #
    # There is no _events.scss and no _stories.scss in brgen, and `event-card`
    # and `story-ring` appear in no stylesheet in the tree. Those pages render
    # with no styling whatsoever — not mis-styled, unstyled.
    #
    # The rest are smaller clusters of the same kind: communities moderation
    # (ban-list, mod-queue, member-list, community-rules), plus feed-action-form,
    # post-quotes and viewer-list.
    #
    # Deliberately not written here. Inventing a visual design for eleven
    # components is not a lint's decision and not a passing agent's; the numbers
    # and the cluster names are what makes it someone's.
    # unused 279: the typography foundation adds opt-in measure classes (prose,
    # reading-column, form-measure, ...) worn by tokens, not yet by every view.
    #
    # undefined 0: _coverage_fills.scss gives Event, Story and the moderation
    # pages a box model. The fill is structural and token-only -- flex, gap,
    # var(--space-*), var(--surface-elevated), var(--radius-*), no colour and no
    # hex -- so an unstyled page gets geometry without anyone deciding what it
    # looks like. Past that the design is still someone's, and this is a floor
    # rather than a licence to style from a lint.
    # Comes down with the code, never up to meet it: this ratchet fails on slack
    # as well as on excess.
    #
    #   278 -> 276  the Live surface went, orphaning the inline compose block in
    #               _nav.scss whose last caller it was
    #   276 -> 275  the presentational class `dim` went from markup and
    #               stylesheets alike, with the seven naming hooks that had been
    #               riding on its styling
    #   243 -> 240  three selectors regained markup in the parallel visual
    #               sessions; the ceiling follows the tree down.
    #   275 -> 243  the instrument learned to read a class attribute that embeds
    #               an ERB conditional — class="unit<%= " unit--wide" if wide %>"
    #               never matched the plain pattern, so the base name and the
    #               literal inside the tag both read as dead. swiper-wrapper
    #               joined its library's other runtime classes in EXTERNAL, and
    #               the two wardrobe-slide fills whose carousel markup had gone
    #               were deleted.
    #
    # undefined back to 0 (2026-08-21): the seven hooks the instrument fix
    # surfaced are designed now — unread/read and message--unread wear weight
    # plus a leading accent dot, story-ring wears the accent ring that fades
    # when seen, and the default address is the accent-bordered card.
    # 240 -> 174 on 2026-08-22: 40 proven-dead rules deleted (the .animate-*
    # utility set the flat contract orphaned, the pre-unification
    # .brand-wordmark, the city-home intro, legacy card/search shells), and
    # the DYNAMIC_SEEDS above stopped the census miscounting runtime-built
    # names. The 174 left are dominated by amber sheets, which belong to
    # amber\x27s active session — recorded in SURFACES.md, not touched here.
    # unused_selector RAISED 174 -> 180 on 2026-08-25, and the six are named
# because a raised baseline without a list is a number nobody can act on.
#
# Nine unrendered partials were deleted and took their markup with them, so
# the CSS only they used went unreferenced: jox-logo and logo and frames from
# _jox_logo, marketplace-subnav from _subnav, feed-tab and type from
# _city_switcher. The two dedicated stylesheets went with their partials —
# shared/_device_showcase.scss whole, and its two @forwards — but these six
# live inside _root.scss, _nav.scss, _marketplace.scss and
# _jsfiddle_chrome.scss alongside rules that are still used.
#
# Left for the owner deliberately: visual work in this tree is not something
# to do on a tool's judgement, and dead CSS costs bytes where dead markup
# cost a reader's time.
# unused_selector 180 -> 153 and undefined_class 0 -> 9 in one change, both from
# teaching used_names about classList. The JS was already in the scanned set and
# every pattern looked for a `class=` attribute, which is the one way a Stimulus
# controller never applies a class.
#
# The 28 that stopped being reported were rules styling a state only JS produces —
# real CSS, called dead by a detector that could not see its trigger.
#
# The 9 that appeared are the opposite and are named here because this file's own
# rule is that a raised baseline without a list is a number nobody can act on:
#   canvas-inverted  lazy-fade-in  lazy-loaded  luxury-product-ready
#   queued  show  start-ack  tap-ripple  ui-inverted
# Eight of the nine have no rule in any stylesheet and are never read back by
# `classList.contains` or a selector, so applying them does nothing at all —
# neither paint nor state another reader can see. That is a finding per site, not
# a sweep: a missing rule and a leftover toggle look identical from here, and
# deleting the call is wrong if the CSS was lost rather than never written.
# undefined_class 9 -> 4 and unused_selector 153 -> 156, both 2026-08-27, when
# brgen lost its left rail, its right rail and the city-today strip.
#
# The fall is the real half: five classes that markup named and no stylesheet
# defined left with the markup that named them.
#
# The rise is honest debt. Removing that much markup orphans selectors, and I
# removed the ones I could attribute -- the whole .city-today block,
# .sidebar-dropdown, .sidebar-dropdown-menu and .sidebar-card__head. Three more
# are unattributed: the shared .sidebar, .widgets and .widget-search rules all
# stayed live because amber still renders them, so the remainder is not there.
# Ceilings, and they only fall.
#
# undefined_class holds at zero: every class markup names has a reader, so the
# next one that does not is a real finding on the day it lands rather than a
# number someone argues about later.
#
# unused_selector is not zero because visualizers_2d_reference.js is preserved
# source that nothing loads, imports or compiles -- its own header says so --
# and it carries this file's sanctioned opt-out marker. Its class names are out
# of the used set, so rules elsewhere that only it referenced read as orphans.
# Recorded rather than chased, and recorded rather than hidden.
BASELINES = { "undefined_class" => 0, "unused_selector" => 154 }.freeze

    Finding = Struct.new(:kind, :name, :count, :example)

    extend Pub4::BaselineRatchet

    module_function

    def engine_dirs = Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*"))

    def views
      TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/views/**/*.erb")) } +
        engine_dirs.flat_map { |d| Dir.glob(File.join(d, "app/views/**/*.erb")) } +
        rendered_by_javascript
    end

    # Not every element is rendered by a template. optimistic_send_controller
    # builds the pending message it later marks failed, so the class naming that
    # status appears only in JavaScript — and a scan of the views alone called
    # the rule styling it unused, which is the opposite of true.
    #
    # Read as views because that is what they are: the markup exists, it is
    # assembled at runtime. Both frontend homes are covered, so a controller
    # promoted from an app into shared/frontend does not change the count.
    def rendered_by_javascript
      TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/javascript/**/*.js")) } +
        Dir.glob(File.join(RAILS_ROOT, "shared", "frontend", "**", "*.js"))
    end

    def stylesheets
      (TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/assets/stylesheets/**/*.{scss,css}")) } +
       engine_dirs.flat_map { |d| Dir.glob(File.join(d, "app/assets/stylesheets/**/*.{scss,css}")) })
        .reject { |path| path.include?("/builds/") || path.include?("/public/assets/") }
    end

    def strip_css(body)
      body.gsub(%r{/\*.*?\*/}m) { |block| block.gsub(/[^\n]/, " ") }
          .gsub(%r{//[^\n]*}) { |line| " " * line.length }
    end

    # Comments blanked. A stylesheet that explains why a class was removed would
    # otherwise count as defining it, and a view that explains why one was dropped
    # would count as using it.
    def strip_erb(body)
      body.gsub(/<%#.*?%>/m) { |block| block.gsub(/[^\n]/, " ") }
    end

    def defined_names
      @defined_names ||= begin
        names = Set.new
        # Email cannot load a bundle, so the mailer layout defines its classes in an
        # inline <style>. Reading only .scss/.css reported every mail-* as missing.
        views.each do |view|
          File.read(view, encoding: "UTF-8").scan(/<style[^>]*>(.*?)<\/style>/m) do |(css)|
            strip_css(css).scan(/\.([a-zA-Z_][\w-]*)/) { |(name)| names << name }
          end
        end
        stylesheets.each do |sheet|
          body = strip_css(File.read(sheet, encoding: "UTF-8"))
          body.scan(/\.([a-zA-Z_][\w-]*)/) { |(name)| names << name }
          # SCSS builds &__child / &--modifier names no literal scan can see.
          body.scan(/&(?:__|--)([\w-]+)/) { |(fragment)| names << fragment }
        end
        names
      end
    end

    # Five extractors and one recorder. This was a single 48-line method holding
    # five copies of the same three lines, which is how it grew past the ratchet
    # every time somebody found another way to apply a class. Each extractor now
    # keeps its reason next to its pattern, and a sixth way is a new method
    # rather than another paragraph in this one.
    def used_names
      @used_names ||= begin
        @lists = {}
        used = {}
        views.each do |view|
          body = strip_erb(File.read(view, encoding: "UTF-8"))
          next if body.include?(OPT_OUT)

          class_lists_in(body).each { |names| record_names(used, view, names) }
        end
        used
      end
    end

    # A name is recorded together with the list it appeared in, so a sibling can
    # be consulted later: `unit unit--wide` is what proves the modifier belongs
    # to a class that is styled.
    def class_lists_in(body)
      attribute_lists(body) + helper_array_lists(body) +
        javascript_lists(body) + interpolated_attribute_lists(body)
    end

    def record_names(used, view, names)
      names.each do |name|
        (used[name] ||= []) << view
        (@lists[name] ||= []) << names
      end
    end

    def attribute_lists(body)
      [ /class:\s*["']([^"'<>]+)["']/, /class=["']([^"'<>]*)["']/ ].flat_map do |pattern|
        body.scan(pattern).map { |(list)| list.to_s.split(/\s+/) }
      end
    end

    # The tag-helper array form — class: ["card", ("wide" if wide)] — holds its
    # names as Ruby string literals, invisible to the two attribute patterns.
    def helper_array_lists(body)
      body.scan(/class:\s*\[([^\]]*)\]/m).map do |(list)|
        list.scan(/["']([\w\s-]+)["']/).flatten.flat_map(&:split)
      end
    end

    # The JavaScript files are read as views for exactly one reason — the markup
    # exists, it is just assembled at runtime — and then every pattern above
    # looked for a `class=` attribute, which is the one way a Stimulus
    # controller does NOT apply a class. `classList.toggle("x")`, `.add`,
    # `.remove`, `.replace` and a `className =` assignment were all invisible,
    # so a rule styling a state only JS can produce read as dead while the JS
    # that produces it sat in the scanned set.
    #
    # Found when `drawer-open` — added to the root by edge_swiper so chrome that
    # cannot be a CSS sibling of a drawer can respond to one — pushed
    # unused_selector to 181 against a ceiling of 180.
    def javascript_lists(body)
      toggled = body.scan(/classList\s*\.\s*(?:add|remove|toggle|replace|contains)\s*\(([^)]*)\)/m)
                    .map { |(args)| args.scan(/["']([\w\s-]+)["']/).flatten.flat_map(&:split) }
      assigned = body.scan(/className\s*=\s*["']([\w\s-]+)["']/)
                     .map { |(list)| list.to_s.split(/\s+/) }
      toggled + assigned
    end

    # A class attribute that embeds an ERB conditional —
    # class="unit<%= " unit--wide" if wide %>" — never matches the plain
    # attribute pattern (the `<` ends the value), so both the base name and the
    # literal inside the tag read as unused. The browser sees every quoted
    # fragment; count them.
    def interpolated_attribute_lists(body)
      body.scan(/class=["']((?:[^"'<>]|<%=(?:(?!%>).)*?%>)*)["']/m).filter_map do |(list)|
        next unless list.include?("<%=")

        list.gsub(/<%=(?:(?!%>).)*?%>/m) { |tag| tag.scan(/["']([^"']*)["']/).flatten.join(" ") }
            .split(/\s+/)
      end
    end

    def class_lists
      used_names
      @lists
    end

    # A class that ALWAYS shares its element with a class that IS styled inherits from
    # it — `.channel-guest-hint dim`, `.conversation-log channel-log`, `.comment-time
    # dim`. That is a naming hook, not a missing style, and reporting it asks the next
    # author to invent a rule for something already styled.
    #
    # "Always", not "ever": a class that appears alone on any surface is doing its own
    # work there and stays in the count.
    def inherits_everywhere?(name)
      lists = class_lists[name] || []
      return false if lists.empty?

      lists.all? { |list| (list - [ name ]).any? { |sibling| defined_names.include?(sibling) } }
    end

    # A class that names a Stimulus controller mounted on the same element is that
    # controller's identity, not a style — `class="nested-form"
    # data-controller="nested-form"`. Writing a rule for it would be styling an API.
    def controller_identity?(name)
      @controller_identities ||= views.flat_map do |view|
        strip_erb(File.read(view, encoding: "UTF-8"))
          .scan(/data-controller=["']([^"'<>]+)["']/).flatten
          .flat_map { |list| list.split(/\s+/) }
      end.to_set
      @controller_identities.include?(name)
    end

    # A modifier or element whose base is defined is a real BEM pair the literal scan
    # cannot see, not a missing style.
    def base_defined?(name)
      defined_names.include?(name.sub(/--.*\z/, "")) || defined_names.include?(name.sub(/__.*\z/, ""))
    end

    def interpolated?(name)
      name.empty? || name.include?("\#{") || name.start_with?("<%")
    end

    def undefined_classes
      used_names.keys.reject do |name|
        interpolated?(name) || EXTERNAL.include?(name) || defined_names.include?(name) ||
          base_defined?(name) || inherits_everywhere?(name) || controller_identity?(name)
      end
    end

    # Names no template spells whole. Each seed is verified against a real
    # producer (2026-08-22): vertical-<name> from the shell class map,
    # monogram--<n> in _feed_card, map-marker--<kind> in map_controller.js,
    # capsule-row--/occasion-card-- verdicts in amber ai views, chip--<state>
    # in events, <theme>-tokens in the layouts, match-overlay subtree from the
    # layout. maplibregl-/ProseMirror-/trix- are vendor-runtime: the library
    # builds the node, our sheet styles it.
    DYNAMIC_SEEDS = %w[vertical- monogram-- map-marker-- capsule-row--
                       occasion-card-- chip-- match-overlay maplibregl-
                       ProseMirror- trix-].freeze
    DYNAMIC_SUFFIXES = %w[-tokens].freeze

    def dynamic?(name)
      DYNAMIC_SEEDS.any? { |seed| name.start_with?(seed) } ||
        DYNAMIC_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
    end

    def unused_selectors
      markup = used_names.keys.to_set
      defined_names.reject do |name|
        markup.include?(name) || EXTERNAL.include?(name) || dynamic?(name) ||
          markup.any? { |used| used.start_with?("#{name}--") || used.start_with?("#{name}__") }
      end
    end

    def scan
      undefined_classes.map { |name|
 Finding.new("undefined_class", name, used_names[name].size, rel(used_names[name].first)) } +
        unused_selectors.map { |name| Finding.new("unused_selector", name, 0, nil) }
    end

    def rel(path) = path.to_s.sub("#{RAILS_ROOT}/", "")

    def run
      findings = scan
      counts(findings).each do |kind, count|
        baseline = BASELINES.fetch(kind)
        note = count < baseline ? " — under baseline, lower it" : ""
        puts "css_coverage_lint: #{kind} #{count} (baseline #{baseline})#{note}"
      end
      findings.select { |f| f.kind == "undefined_class" }
              .sort_by { |f| -f.count }
              .first(20)
              .each { |f| puts format("  .%-32s %2d use(s)  e.g. %s", f.name, f.count, f.example) }

      exceeded = over_baseline(findings)
      return true if exceeded.empty?

      warn "css_coverage_lint: exceeds baseline — #{exceeded.join("; ")}"
      false
    end
  end
end

exit(Pub4::CssCoverageLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
