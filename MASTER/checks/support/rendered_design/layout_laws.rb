# frozen_string_literal: true

module Deploy
  module RenderedDesign
    # Layout, chrome and hierarchy on the rendered page: grids, the chrome a phone pays for,
    # where the thumb and the eye land, and how quiet the frame stays.
    module LayoutLaws
      BLOCK = /\A(?:block|flex|grid|list-item|table|flow-root)\z/
      MEDIA = %w[img video picture canvas svg].freeze
      FILL_TAGS = %w[button a].freeze

      CUE = %w[font_weight decoration border_width box_shadow font_style text_transform outline_width].freeze
      CONTROLS = %w[input select textarea button].freeze
      MARKS = %w[aria-current aria-selected data-state].freeze
      HIDDEN = { "display" => "none", "visibility" => "hidden" }.freeze

      module_function

      def edges(view)
        RenderedDesign.elements(view).select do |element|
          element["in_main"] && element["display"].to_s.match?(BLOCK) &&
            (!element["text"].to_s.empty? || MEDIA.include?(element["tag"]))
        end
      end

      def near_miss(lefts, pair)
        one, two = pair
        gap = (two - one).round(1)
        return unless gap.between?(1, 4)

        "error: #{lefts[one].first["key"]} at #{one} and #{lefts[two].first["key"]} at #{two} miss by #{gap}px"
      end

      # Two left edges 1-4px apart are one edge missed; more than three on a phone is a warning.
      def alignment(view)
        lefts = edges(view).group_by { |element| (element["content_x"].to_f * 2).round / 2.0 }
        sorted = lefts.keys.sort
        clusters = sorted.chunk_while { |one, two| two - one < 1 }.count
        sorted.each_cons(2).map { |pair| near_miss(lefts, pair) } +
          [clusters > 3 && "warning: #{clusters} left edges at #{view["width"]}; three is the grid"]
      end

      def share(rows, area) = rows.sum { |row| row["area"].to_f } / area

      def shown(rows) = Array(rows).select { |row| row["on_screen"] }

      def area(view) = view["width"].to_f * view["height"].to_f

      def top_budget(view)
        top = share(shown(view.dig("chrome", "top")), area(view))
        return if top <= 0.16

        level = top > 0.25 ? "error" : "warning"
        "#{level}: chrome covers #{(top * 100).round}% of the first screen at #{view["width"]}"
      end

      def chrome_budget(view)
        deep = shown(view.dig("chrome", "deep"))
        reading = deep.any? && scrolls?(view) ? reading_budget(deep, area(view)) : []
        [top_budget(view)] + reading
      end

      def reading_budget(deep, area)
        primary, rest = deep.partition { |row| row["primary"] }.map { |rows| share(rows, area) }
        [rest > 0.02 && "warning: chrome keeps #{(rest * 100).round}% while reading",
         primary > 0.08 && "warning: the primary action keeps #{(primary * 100).round}% while reading"]
      end

      def scrolls?(view) = view.dig("page", "scroll_height").to_f > view.dig("page", "inner_height").to_f + 1

      def by_key(rows) = Array(rows).to_h { |row| [row["key"], row] }

      # One chrome root across the three scroll states the capture took.
      Bar = Struct.new(:top, :down, :up, :scrolls, keyword_init: true) do
        def key = top["key"]
        def hidden? = down.any? && !down["on_screen"]
        def gone? = HIDDEN.any? { |prop, value| down[prop] == value }
        def stays? = scrolls && down["on_screen"] && !top["primary"]
        def stuck? = scrolls && hidden? && up && !up["on_screen"]

        def findings
          [!top["on_screen"] && "error: #{key} is not shown at the top of the page",
           stays? && "warning: #{key} stays while the reader reads",
           gone? && "error: #{key} leaves the accessibility tree when hidden",
           top["primary"] && hidden? && "error: #{key} hides the primary action",
           stuck? && "error: #{key} does not return on scroll-up"]
        end
      end

      def chrome_yields(view)
        states = view["chrome"] || {}
        down = by_key(states["down"])
        up = by_key(states["up"])
        Array(states["top"]).flat_map do |row|
          Bar.new(top: row, down: down[row["key"]] || {}, up: up[row["key"]], scrolls: scrolls?(view)).findings
        end
      end

      def focus(view)
        Array(view["focus"]).compact.flat_map do |stop|
          Array(stop["covers"]).map do |cover|
            level = cover["share"].to_f >= 0.99 ? "error: fully" : "warning: partly"
            "#{level} hidden: #{stop["key"]} under #{cover["key"]} at #{view["width"]}"
          end
        end
      end

      def primary_actions(view)
        elements = RenderedDesign.elements(view)
        primary = elements.select { |element| element["primary"] }
        primary.empty? ? elements.select { |element| element["submit"] } : primary
      end

      def reach(element, view)
        x, y = RenderedDesign.center(element["rect"])
        width = view["width"].to_f
        height = view["height"].to_f
        sticky = %w[sticky fixed].include?(element["position"])
        return "warning: sticky #{element["key"]} sits in the top half at #{view["width"]}" if sticky && y < height / 2

        corner = y < height / 4 && (x < width / 4 || x > width * 0.75)
        "warning: #{element["key"]} sits in a top corner at #{view["width"]}, out of thumb reach" if corner
      end

      def thumb(view) = primary_actions(view).map { |element| reach(element, view) }

      def filled?(element, height)
        acts = FILL_TAGS.include?(element["tag"]) || element.dig("attrs", "role") == "button"
        acts && element["interactive"] && element["rect"]["y"].to_f < height && Array(element["bg"])[3].to_f > 0.5 &&
          RenderedDesign.contrast(element["bg"], element["ground"]) >= 3
      end

      def primary_count(view)
        filled = RenderedDesign.elements(view).select { |element| filled?(element, view["height"].to_f) }
        return [] if filled.size <= 1

        ["warning: #{filled.size} filled actions on the first screen at #{view["width"]} " \
         "(#{filled.first(3).map { |element| element["key"] }.join(", ")}); one is primary"]
      end

      # One primary action per card or form (MAEDA_THE_ONE): the surface answers
      # through its primary action and a second dilutes both, while cards each
      # carrying their own stay right. The walker names every element's nearest
      # card-or-form ancestor in host; a primary with no host belongs to the
      # page shell, which ONE_PRIMARY_ACTION judges.
      def maeda(view)
        elements = RenderedDesign.elements(view)
        primaries = elements.select { |element| element["primary"] || element["submit"] }
        primaries.group_by { |element| element["host"].to_s }.filter_map do |host, rows|
          surface = elements.find { |element| element["index"].to_s == host }
          next unless surface && rows.size > 1

          "error: #{rows.size} primary actions on one #{surface["tag"] == "form" ? "form" : "card"} " \
            "(#{rows.first(3).map { |row| row["key"] }.join(", ")}); one is primary"
        end
      end

      def nav_link?(element) = element["in_nav"] && element["tag"] == "a" && !element["path"].to_s.empty?

      def leads_here?(path, here) = path == here || (path != "/" && here.start_with?("#{path.chomp("/")}/"))

      def current(view)
        links = RenderedDesign.elements(view).select { |element| nav_link?(element) }
        here = view.dig("page", "path").to_s
        leading = links.select { |element| leads_here?(element["path"], here) }
        best = leading.group_by { |element| element["path"].size }.max&.last
        Array(best).filter_map { |element| current_finding(element, links) }
      end

      def current_finding(element, links)
        key = element["key"]
        return "error: #{key} leads here and carries no aria-current" unless element.dig("attrs", "aria-current")

        other = links.find { |link| !link.equal?(element) && !link.dig("attrs", "aria-current") } or return
        "error: #{key} marks the current page by colour alone" if CUE.all? { |prop| element[prop] == other[prop] }
      end

      def framed?(element)
        bare = element["border_width"].to_f.zero?
        return false if bare || CONTROLS.include?(element["tag"]) || element["interactive"]

        element["attrs"].to_h.keys.none? { |name| name.start_with?(*MARKS) }
      end

      def ink_contrast(element) = RenderedDesign.contrast(element["color"], element["own_ground"])

      def quiet_frame(view)
        quietest = RenderedDesign.texts(view).map { |element| ink_contrast(element) }.min || 21
        frames = RenderedDesign.elements(view).select { |element| framed?(element) }
        frames.filter_map { |element| frame_finding(element, quietest) }
      end

      def frame_finding(element, quietest)
        key = element["key"]
        width = element["border_width"].to_f
        return "warning: #{key} draws a #{width}px rule; structure takes the hairline" if width > 1

        loud = RenderedDesign.contrast(element["border_color"], element["ground"])
        "warning: #{key} rule (#{loud}:1) is louder than the quietest text (#{quietest}:1)" if loud > quietest
      end

      def grey_on_colour?(element)
        sat, light = RenderedDesign.hsl(element["color"])
        sat < 0.08 && light.between?(0.25, 0.85) && RenderedDesign.hsl(element["own_ground"]).first >= 0.25
      end

      def muted_ink(view)
        RenderedDesign.texts(view).select { |element| grey_on_colour?(element) }.map do |element|
          "warning: #{element["key"]} sets grey ink on a coloured ground; mute the ink or take the ground's hue"
        end
      end

      def spacing(view)
        width = view["width"]
        clipped = Array(view.dig("spacing", "clipped"))
        found = clipped.map { |key| "error: #{key} clips its text under WCAG 1.4.12 spacing at #{width}" }
        found << "error: the page scrolls sideways under 1.4.12 spacing at #{width}" if view.dig("spacing", "sideways")
        found
      end
    end

    register(:ALIGNMENT_NEAR_MISS) { |snap| each_view(snap) { |view| LayoutLaws.alignment(view) } }
    register(:CHROME_AREA_BUDGET) { |snap| each_view(snap) { |view| LayoutLaws.chrome_budget(view) } }
    register(:CHROME_YIELDS_ON_READ) { |snap| each_view(snap, [390]) { |view| LayoutLaws.chrome_yields(view) } }
    register(:FOCUS_NOT_OBSCURED) { |snap| each_view(snap, [390, 1280]) { |view| LayoutLaws.focus(view) } }
    register(:PRIMARY_ACTION_IN_THUMB_REACH) { |snap| each_view(snap, [390, 360]) { |view| LayoutLaws.thumb(view) } }

    register(:ONE_PRIMARY_ACTION) { |snap| each_view(snap) { |view| LayoutLaws.primary_count(view) } }
    register(:MAEDA_THE_ONE) { |snap| each_view(snap) { |view| LayoutLaws.maeda(view) } }
    register(:CURRENT_LOCATION_MARKED) { |snap| each_view(snap) { |view| LayoutLaws.current(view) } }
    register(:SMALLEST_EFFECTIVE_DIFFERENCE) { |snap| each_view(snap) { |view| LayoutLaws.quiet_frame(view) } }
    register(:MUTED_INK_FROM_GROUND) { |snap| each_view(snap) { |view| LayoutLaws.muted_ink(view) } }
    register(:TEXT_SPACING_RESILIENCE) { |snap| each_view(snap, [320, 390]) { |view| LayoutLaws.spacing(view) } }
  end
end
