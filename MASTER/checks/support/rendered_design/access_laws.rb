# frozen_string_literal: true

module Deploy
  module RenderedDesign
    # Reach on the rendered page: state beyond colour, links and controls that read,
    # names that say what the eye sees, gestures with a tap, motion with a pause, no strobe,
    # and a first load that only ratchets down.
    module AccessLaws
      STATE = { "aria-current" => nil, "aria-selected" => "true", "aria-pressed" => "true", "data-state" => nil }.freeze
      CUE = %w[font_weight font_style decoration border_width box_shadow text name visible_text text_transform
               outline_width icon].freeze
      CHANGES = %w[decoration border_width font_weight box_shadow outline_width].freeze

      PROSE_PARENTS = %w[p li dd td blockquote].freeze
      CONTROL_TYPES = /\A(?:text|email|tel|url|search|password|number|date|)\z/
      GESTURE = /\b(?:touch(?:start|move|end)|pointer(?:down|move|up)|swipe\w*)->([\w-]+)#(\w+)/
      TAP = /\b(?:click|submit|keydown[\w.]*)->([\w-]+#\w+)/
      MINIMALISM = File.join(ROOT, "data/minimalism.yml")

      module_function

      def stateful?(element)
        STATE.any? { |name, value| (seen = element.dig("attrs", name)) && (value.nil? || seen == value) }
      end

      def state_of(element) = STATE.keys.to_h { |name| [name, element.dig("attrs", name)] }

      def twin(element, elements)
        elements.find do |other|
          !other.equal?(element) && other["pid"] == element["pid"] && other["tag"] == element["tag"] &&
            state_of(other) != state_of(element)
        end
      end

      def colour_only(view)
        elements = RenderedDesign.elements(view)
        elements.filter_map do |element|
          key = element["key"]
          invalid = element.dig("attrs", "aria-invalid") == "true" && element["described"].to_s.strip.empty?
          next "error: #{key} is invalid with no visible message (aria-describedby)" if invalid
          next unless stateful?(element)

          other = twin(element, elements)
          "error: #{key} shows its state by colour alone" if other && CUE.all? { |prop| element[prop] == other[prop] }
        end
      end

      def changed?(base, forced) = forced && CHANGES.any? { |prop| forced[prop] != base[prop] }

      def running_link?(element)
        element["tag"] == "a" && element["in_text"] && PROSE_PARENTS.include?(element["parent"]) &&
          !element.dig("attrs", "class").to_s.include?("button") && !element["decoration"].to_s.include?("underline")
      end

      def links(view)
        RenderedDesign.elements(view).select { |element| running_link?(element) }.filter_map do |element|
          ratio = RenderedDesign.contrast(element["color"], element["parent_color"])
          next "error: #{element["key"]} in running text is #{ratio}:1 from its text and not underlined" if ratio < 3

          forced = view.dig("forced", element["index"].to_s) || {}
          cue = changed?(element, forced["hover"]) || changed?(element, forced["focus-visible"])
          "warning: #{element["key"]} gains no non-colour cue on hover or focus" unless cue
        end
      end

      def control?(element)
        tag = element["tag"]
        %w[select textarea].include?(tag) || (tag == "input" && element.dig("attrs", "type").to_s.match?(CONTROL_TYPES))
      end

      def icon_only?(element)
        %w[button a].include?(element["tag"]) && element["icon"] && !element["visible_text"].to_s.match?(/[\p{L}\p{N}]/)
      end

      def boundary(element)
        ground = element["ground"]
        edge = element["border_width"].to_f.positive? ? RenderedDesign.contrast(element["border_color"], ground) : 0
        fill = RenderedDesign.contrast(RenderedDesign.blend(element["bg"], ground), ground)
        best = [edge, fill].max
        "error: #{element["key"]} boundary reaches #{best}:1; a control needs 3:1" if best < 3
      end

      def icon_contrast(element)
        ratio = RenderedDesign.contrast(element["color"], element["own_ground"])
        "error: icon #{element["key"]} reaches #{ratio}:1; an icon that acts needs 3:1" if ratio < 3
      end

      def non_text(view)
        RenderedDesign.elements(view).flat_map do |element|
          ring = view.dig("forced", element["index"].to_s, "focus-visible")
          [control?(element) && boundary(element), icon_only?(element) && icon_contrast(element),
           ring && (control?(element) || element["interactive"]) && ring_finding(element, ring)]
        end
      end

      def ring_finding(element, ring)
        shadow = ring["box_shadow"].to_s
        return if shadow != "" && shadow != element["box_shadow"]

        ratio = RenderedDesign.contrast(ring["outline_color"], element["ground"])
        width = ring["outline_width"].to_f
        "warning: #{element["key"]} focus ring is #{width}px at #{ratio}:1; 2px at 3:1" if width < 2 || ratio < 3
      end

      def normal(text) = text.to_s.downcase.gsub(/[^\p{L}\p{N}\s]/, "").split.join(" ")

      def label_in_name(view)
        RenderedDesign.elements(view).filter_map do |element|
          named = element.dig("attrs", "aria-label") || element.dig("attrs", "aria-labelledby")
          seen = normal(element["visible_text"])
          next unless element["interactive"] && named && !seen.empty? && !normal(element["name"]).include?(seen)

          "error: #{element["key"]} is named #{element["name"].inspect}, " \
            "not containing its visible #{element["visible_text"].inspect}"
        end
      end

      def actions(element, pattern) = element.dig("attrs", "data-action").to_s.scan(pattern)

      def gestures(view)
        elements = RenderedDesign.elements(view)
        taps = elements.flat_map { |element| actions(element, TAP).flatten }
        swipes = elements.flat_map do |element|
          actions(element, GESTURE).map { |ctrl, act| [element["key"], "#{ctrl}##{act}"] }
        end
        swipes.uniq.reject { |_key, action| taps.include?(action) }
              .map { |key, action| "warning: #{key} answers #{action} by gesture only; give it a button" }
      end

      def icon_words
        @icon_words ||= Array(YAML.safe_load_file(MINIMALISM).dig("law", "icon_words_optional")).map(&:downcase)
      rescue Errno::ENOENT # scan: intentional - no allow-list: every icon carries a word, the stricter reading
        []
      end

      def icons(view)
        RenderedDesign.elements(view).filter_map do |element|
          next unless icon_only?(element) && element["interactive"]

          name = normal(element["name"])
          "warning: #{element["key"]} (#{name.inspect}) is an icon with no word" unless icon_words.include?(name)
        end
      end

      def motion(snap)
        move = snap["motion"] or return []
        return [] unless move["changes"].to_i.positive? && move["last_change"].to_f > 5000 && !move["pause"]

        ["warning: content keeps changing after 5s (#{move["changes"]} changes) and offers no pause control"]
      end

      # The times a luminance series turns: a swing of 10% or more with the darker side under 0.8.
      def turns(samples)
        low = high = direction = nil
        samples.each_with_object([]) do |(at, lum), found|
          low = [low || lum, lum].min
          high = [high || lum, lum].max
          next unless high - low >= 0.1 && low < 0.8

          now = lum >= high ? :up : :down
          found << at if now != direction
          direction = now
          low = high = lum
        end
      end

      # A flash is a pair of opposing turns; the most within any one second.
      def flashes(surface)
        times = turns(Array(surface["samples"]))
        within = times.each_index.map { |index| times[index..].take_while { |time| time - times[index] < 1000 }.size }
        within.max.to_i / 2
      end

      def flash(snap)
        Array(snap.dig("motion", "surfaces")).filter_map do |surface|
          count = flashes(surface)
          "error: #{surface["key"]} flashes #{count} times in one second; three is the threshold" if count > 3
        end
      end

      def weight(snap)
        load = snap["weight"] or return []
        route = load["route"]
        budget = load["budget"]
        return ["warning: #{route} has no row in checks/data/page_weight.yml"] unless budget.is_a?(Hash)

        load.fetch("bytes", {}).filter_map do |type, bytes|
          cap = budget[type] or next "warning: #{route} #{type} has no budget"
          "error: #{route} #{type} #{bytes} bytes over its #{cap} budget" if bytes.to_i > cap.to_i
        end
      end

      def chart?(element) = %w[svg canvas].include?(element["tag"]) || classes(element).match?(/chart/)

      def classes(element) = element.dig("attrs", "class").to_s

      def ink(element) = element["stroke_width"].to_f * element["stroke_opacity"].to_f

      def heaviest(elements, pattern)
        elements.select { |element| classes(element).match?(pattern) }.map { |line| ink(line) }.max
      end

      def chart(view)
        elements = RenderedDesign.elements(view)
        deep = elements.select { |element| chart?(element) }.filter_map do |element|
          flat = ["", "none"].include?(element["perspective"].to_s)
          tilted = element["transform"].to_s.start_with?("matrix3d") || !flat
          "error: #{element["key"]} draws its chart in perspective" if tilted
        end
        grid = heaviest(elements, /\bgrid/)
        data = heaviest(elements, /\b(?:series|data|bar|line)\b/)
        deep + [grid && data && grid >= data && "warning: gridlines (#{grid}) ink as heavily as the data (#{data})"]
      end
    end

    register(:COLOR_NOT_SOLE_SIGNAL) { |snap| each_view(snap) { |view| AccessLaws.colour_only(view) } }
    register(:LINK_DISTINGUISHABLE) { |snap| each_view(snap) { |view| AccessLaws.links(view) } }
    register(:NON_TEXT_CONTRAST) { |snap| each_view(snap) { |view| AccessLaws.non_text(view) } }
    register(:LABEL_IN_NAME) { |snap| each_view(snap) { |view| AccessLaws.label_in_name(view) } }
    register(:GESTURE_HAS_TAP_EQUIVALENT) { |snap| each_view(snap) { |view| AccessLaws.gestures(view) } }

    register(:ICON_CARRIES_WORD) { |snap| each_view(snap, [390]) { |view| AccessLaws.icons(view) } }
    register(:AUTO_MOTION_PAUSABLE) { |snap| AccessLaws.motion(snap) }
    register(:FLASH_THRESHOLD) { |snap| AccessLaws.flash(snap) }
    register(:PAGE_WEIGHT_RATCHET) { |snap| AccessLaws.weight(snap) }
    register(:CHART_DATA_INK) { |snap| each_view(snap) { |view| AccessLaws.chart(view) } }
  end
end
