# frozen_string_literal: true

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
      adsbygoogle swiper
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
    # (ban-list, mod-queue, member-list, community-rules), dating likes
    # (like-list, like-card, like-comment), marketplace addresses (address-list,
    # cart-address), takeaway (courier), plus feed-action-form and post-quotes.
    #
    # Deliberately not written here. Inventing a visual design for eleven
    # components is not a lint's decision and not a passing agent's; the numbers
    # and the cluster names are what makes it someone's.
    # unused 269 → 272: battery-aware helpers are html classes toggled by JS
    # (listed in EXTERNAL); the remaining +3 are leftover modifiers from the
    # dating overflow/rewind pass whose markup no longer names them.
    BASELINES = { "undefined_class" => 35, "unused_selector" => 272 }.freeze

    Finding = Struct.new(:kind, :name, :count, :example)

    module_function

    def engine_dirs = Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*"))

    def views
      TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/views/**/*.erb")) } +
        engine_dirs.flat_map { |d| Dir.glob(File.join(d, "app/views/**/*.erb")) }
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

    def used_names
      @used_names ||= begin
        @lists = {}
        used = {}
        views.each do |view|
          body = strip_erb(File.read(view, encoding: "UTF-8"))
          next if body.include?(OPT_OUT)

          [/class:\s*["']([^"'<>]+)["']/, /class=["']([^"'<>]*)["']/].each do |pattern|
            body.scan(pattern) do |(list)|
              names = list.to_s.split(/\s+/)
              names.each do |name|
                (used[name] ||= []) << view
                (@lists[name] ||= []) << names
              end
            end
          end
        end
        used
      end
    end

    # Every class list a name appeared in, so a sibling can be consulted.
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

      lists.all? { |list| (list - [name]).any? { |sibling| defined_names.include?(sibling) } }
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

    def unused_selectors
      markup = used_names.keys.to_set
      defined_names.reject do |name|
        markup.include?(name) || EXTERNAL.include?(name) ||
          markup.any? { |used| used.start_with?("#{name}--") || used.start_with?("#{name}__") }
      end
    end

    def scan
      undefined_classes.map { |name| Finding.new("undefined_class", name, used_names[name].size, rel(used_names[name].first)) } +
        unused_selectors.map { |name| Finding.new("unused_selector", name, 0, nil) }
    end

    def rel(path) = path.to_s.sub("#{RAILS_ROOT}/", "")

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
