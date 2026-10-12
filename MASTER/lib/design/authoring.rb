# frozen_string_literal: true

require_relative "visual_language"
require_relative "typeface"

module Master
  module Design
    # The authoring half of the design layer. VisualLanguage briefs the critic
    # who judges a render; this briefs the fixer who writes the source, so a
    # create, edit or complete request on a frontend file starts from the same
    # direction, typeface rule and composition the critic will hold it to.
    module Authoring
      Surface = Struct.new(:app, :label, :host, :path) do
        def id = "#{app}/#{label}/source"
      end

      EXTENSIONS = %w[.css .scss .erb .html .htm .js .ts].freeze
      APPS = %w[brgen amber bsdports master_web __shared].freeze
      GENERATED = /(\.min\.|face\.runtime\.js\z|\/vendor\/|\/node_modules\/|\/public\/assets\/)/

      # The four steps a designer takes before the first line, and the tells
      # that mark a page nobody chose. Both state a present-tense reason.
      PROTOCOL = <<~TEXT.chomp
        DESIGN AUTHORING
        Decide before you write, then return only the file.
        - Plan: name the palette, the type roles, the layout and the one memorable element. Take them from the direction below and the app's own tokens, not from habit.
        - Review: if the plan is what you would write for any similar page, change the part that is generic.
        - Complete: a surface is finished when its empty, loading, error and worst-case states exist, not when its happy path renders.
        - Critique: before returning, remove one decoration that serves nothing.
      TEXT

      # The fold has tools and turns, so it plans in the open and leaves the
      # file edits to the work itself; the file-only fixer cannot.
      MISSION_PROTOCOL = <<~TEXT.chomp
        DESIGN MISSION
        You are creating, editing or completing a frontend surface.
        - Read first: the app's tokens and shared stylesheet, and one finished sibling surface, before writing a new rule.
        - Plan in your first turn: palette, type roles, layout and the one memorable element, taken from the direction below.
        - Review the plan: replace any part you would write for any similar page.
        - Build with the app's existing primitives and partials; add a token only when no existing one fits.
        - Complete: add the missing states and responsive behavior before you call it done.
        - Critique: render it if you can, and remove one decoration that serves nothing.
      TEXT

      TELLS = <<~TEXT.chomp
        AVOID THE DEFAULTS: cream background with a serif and a terracotta accent; near-black with one acid accent; identical rounded cards with the same soft shadow; gradient washes; tracked all-caps labels above every heading; numbered 01/02/03 markers on content that is not a sequence; one word of a headline accented; fade-and-slide entrances on every section.
      TEXT

      COMPLETION = <<~TEXT.chomp
        COMPLETE MEANS: tokens from the app's scale instead of one-off values; visible :focus-visible; prefers-reduced-motion honored; reads at phone width without horizontal scroll; touch targets of at least %<touch>dpx; text through I18n keys with Norwegian as the default locale; line length under %<measure>dch for prose.
      TEXT

      module_function

      def applicable?(path)
        p = path.to_s
        EXTENSIONS.include?(File.extname(p).downcase) && p.include?("/RAILS/") && !p.match?(GENERATED)
      end

      def context(path:, root: Master::ROOT)
        return "" unless applicable?(path)

        surface = surface_for(path)
        direction = VisualLanguage.direction_for(surface)
        [
          PROTOCOL,
          VisualLanguage.direction_lines(surface, direction).strip,
          (Typeface::HOUSE_RULE if house_typeface?(surface)),
          TELLS,
          format(COMPLETION, touch: Thresholds.touch_min_px(root:), measure: Thresholds.measure_ideal_ch(root:)),
        ].compact.join("\n\n")
      end

      # The brief for a whole mission, before any file is chosen. The app is read
      # from the goal; without one, only the app-independent half applies.
      def mission_context(goal:, root: Master::ROOT)
        app = APPS.find { |name| goal.to_s.match?(/\b#{Regexp.escape(name)}\b/i) }
        surface = Surface.new(app.to_s, "mission", nil, "/")
        parts = [MISSION_PROTOCOL]
        parts << VisualLanguage.direction_lines(surface, VisualLanguage.direction_for(surface)).strip if app
        parts << Typeface::HOUSE_RULE if app.nil? || house_typeface?(surface)
        parts << TELLS
        parts << format(COMPLETION, touch: Thresholds.touch_min_px(root:), measure: Thresholds.measure_ideal_ch(root:))
        parts.join("\n\n")
      end

      def surface_for(path)
        parts = path.to_s.split("/RAILS/", 2).last.to_s.split("/")
        Surface.new(parts.first.to_s, File.basename(path.to_s), nil, route_for(parts))
      end

      # app/views/posts/index.html.erb names the route /posts; the route is the
      # only thing PURPOSE_HINTS can read.
      def route_for(parts)
        at = parts.index("views")
        return "/" unless at

        names = parts[(at + 1)..].map { |part| part.sub(/\..*\z/, "").sub(/\A_/, "") }
        names.pop if %w[index show].include?(names.last)
        "/#{names.join("/")}".chomp("/").then { |route| route.empty? ? "/" : route }
      end

      def house_typeface?(surface)
        %w[brgen amber __shared].include?(surface.app)
      end
    end
  end
end
