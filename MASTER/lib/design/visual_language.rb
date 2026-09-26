# frozen_string_literal: true

require_relative "typography"
require_relative "authority"
require_relative "pairing"
require_relative "composition"

module Master
  module Design
    # A compact design-direction and fingerprint layer for rendered /fix work.
    # It separates what a surface is trying to be from whether the current
    # render is good. Fingerprints describe the artifact; directions describe
    # the intended visual language. Neither is a quality score.
    module VisualLanguage
      AXES = %i[
        density warmth formality contrast ornament motion materiality typographic_voice spatial_tension
      ].freeze

      DIRECTIONS = {
        conversational: {
          school: :social,
          composition: :social_feed,
          match: /master\/chat|ai\.brgen/i,
          density: :focused, warmth: :human, formality: :low, contrast: :high,
          ornament: :restrained, motion: :expressive, materiality: :digital,
          typographic_voice: :conversational, spatial_tension: :open,
          memorable: "the response surface and its living face should feel like one instrument"
        },
        utilitarian_terminal: {
          school: :industrial,
          composition: :industrial_system,
          match: /bsdports|ports|openbsd|terminal/i,
          density: :high, warmth: :cool, formality: :high, contrast: :high,
          ornament: :minimal, motion: :quiet, materiality: :functional,
          typographic_voice: :mono_forward, spatial_tension: :tight,
          memorable: "dense information should remain calm, legible, and obviously actionable"
        },
        editorial_wardrobe: {
          school: :luxury,
          composition: :editorial_commerce,
          match: /amber|wardrobe|outfit|garment|fashion/i,
          density: :moderate, warmth: :warm, formality: :editorial, contrast: :controlled,
          ornament: :selective, motion: :subtle, materiality: :tactile,
          typographic_voice: :editorial, spatial_tension: :relaxed,
          memorable: "the clothing and its visual texture should carry the page before chrome does"
        },
        marketplace: {
          school: :commerce_editorial,
          composition: :marketplace_sale,
          references: %i[kaufland bol],
          reference_mission: "Kaufland catalogue breadth and campaign entry points; bol cleanliness, service clarity, recommendation rails, and restrained product chrome",
          match: /markedsplass|market|listing|shop|order/i,
          density: :high, warmth: :local, formality: :practical, contrast: :clear,
          ornament: :low, motion: :functional, materiality: :physical,
          typographic_voice: :plainspoken, spatial_tension: :compact,
          memorable: "real items, prices, places, and trust signals should dominate the hierarchy"
        },
        cute_retail: {
          match: /toy|toys|kids|children|playroom|cute|playful/i,
          school: :cute,
          composition: :cute_retail,
          density: :lively, warmth: :warm, formality: :low, contrast: :clear,
          ornament: :expressive, motion: :playful, materiality: :tactile,
          typographic_voice: :friendly, spatial_tension: :open,
          memorable: "play, product character, and the next action should be obvious together"
        },
        local_social: {
          school: :social,
          composition: :social_feed,
          match: /brgen|community|communities|posts|events|stories|conversations/i,
          density: :lively, warmth: :human, formality: :low, contrast: :clear,
          ornament: :selective, motion: :responsive, materiality: :local,
          typographic_voice: :humanist, spatial_tension: :varied,
          memorable: "place, people, and fresh activity should feel immediate without becoming noisy"
        },
        media_station: {
          school: :editorial,
          composition: :editorial_commerce,
          match: /radio|tv|video|sounds|playlist|sets/i,
          density: :focused, warmth: :immersive, formality: :low, contrast: :dramatic,
          ornament: :deliberate, motion: :rhythmic, materiality: :sonic,
          typographic_voice: :display, spatial_tension: :cinematic,
          memorable: "media should create the focal field; controls should recede until needed"
        },
        intimate_social: {
          school: :social,
          composition: :social_feed,
          match: /dating|likes|users\/new|users\/show/i,
          density: :focused, warmth: :warm, formality: :low, contrast: :gentle,
          ornament: :selective, motion: :responsive, materiality: :human,
          typographic_voice: :friendly, spatial_tension: :intimate,
          memorable: "the person and the decision in front of the user should remain unmistakable"
        },
        transactional_food: {
          school: :commerce_editorial,
          composition: :marketplace_sale,
          match: /takeaway|restaurant|delivery|restaurants/i,
          density: :high, warmth: :warm, formality: :practical, contrast: :clear,
          ornament: :appetizing, motion: :functional, materiality: :physical,
          typographic_voice: :plainspoken, spatial_tension: :compact,
          memorable: "food, availability, price, and next action should read in one glance"
        },
        cartographic: {
          school: :swiss,
          composition: :swiss_poster,
          match: /maps|places/i,
          density: :high, warmth: :neutral, formality: :practical, contrast: :clear,
          ornament: :low, motion: :spatial, materiality: :geographic,
          typographic_voice: :utility, spatial_tension: :layered,
          memorable: "location and relationships should dominate decorative interface chrome"
        },
        content_first: {
          school: :editorial,
          composition: :editorial_commerce,
          match: /.*/,
          density: :moderate, warmth: :neutral, formality: :calm, contrast: :clear,
          ornament: :low, motion: :restrained, materiality: :honest,
          typographic_voice: :readable, spatial_tension: :balanced,
          memorable: "the content's own structure should be the page's strongest visual idea"
        },
      }.freeze

      PURPOSE_HINTS = [
        ["/items/new", "create or upload an item"],
        ["/session/new", "sign in with minimal friction"],
        ["/registration/new", "create an account"],
        ["/search", "find a specific result"],
        ["/feed", "scan a live stream and choose what to open"],
        ["/posts", "read and participate in a post stream"],
        ["/stories", "scan short-lived updates"],
        ["/messages", "read and continue conversations"],
        ["/orders", "understand and manage an order"],
        ["/privacy", "read a legal or trust document"],
        ["/terms", "read a legal or trust document"],
        ["/cookies", "understand data and cookie use"],
        ["/", "understand the product and take its primary action"],
      ].freeze

      AUDIENCES = {
        conversational: "people using an AI conversation surface",
        utilitarian_terminal: "developers and operators who need fast, reliable information",
        editorial_wardrobe: "people browsing, organizing, and expressing personal style",
        marketplace: "local buyers and sellers comparing real things and transactions",
        local_social: "people participating in a local community",
        media_station: "people discovering, listening to, or publishing media",
        intimate_social: "people evaluating people and choices with personal stakes",
        transactional_food: "people deciding what to order and completing a purchase",
        cartographic: "people locating places and understanding spatial relationships",
        content_first: "the people named by the surface's content and task",
      }.freeze

      TYPOGRAPHY_HINTS = {
        conversational: "a clear reading face with a distinct voice; use mono only where it clarifies system behavior",
        utilitarian_terminal: "mono-forward hierarchy with disciplined measure and visible rhythm",
        editorial_wardrobe: "editorial headline contrast with a quiet, highly readable text face",
        marketplace: "plainspoken numerals and labels; type hierarchy should expose price, condition, and action",
        local_social: "humanist, readable type with stronger hierarchy for fresh content and place",
        media_station: "display contrast for the focal media title, restrained utility text around it",
        intimate_social: "friendly, legible type with enough scale to make personal choices feel direct",
        transactional_food: "fast-scanning labels, price, availability, and primary action",
        cartographic: "utility-first labels with disciplined density and predictable hierarchy",
        content_first: "readable hierarchy whose proportions come from content, not component fashion",
      }.freeze

      # Each drift label and the fingerprint path it compares, in report order.
      DRIFT_PATHS = {
        "palette changed" => %i[palette top],
        "type sizes changed" => %i[typography sizes],
        "font families changed" => %i[typography families],
        "shape language changed" => %i[shape rounded],
        "effects changed" => %i[effects],
      }.freeze

      module_function

      def reference_study
        @reference_study ||= Master.load_yaml(File.join(Master::ROOT, "data", "design_reference_study.yml")) || {}
      rescue StandardError
        {}
      end

      def brief(surface:, payload:)
        direction_lines(surface, direction_for(surface)) + evidence_lines(payload)
      end

      # What the surface is for and which school, type, pairing and references
      # that implies: the intent half of the brief.
      def direction_lines(surface, direction)
        purpose = purpose_for(surface)
        school = DIRECTIONS.fetch(direction)[:school]
        <<~TEXT
          surface=#{surface.id}
          purpose=#{purpose}
          audience_hypothesis=#{AUDIENCES.fetch(direction)}
          authoritative_design=true
          authority=#{Master::Design::Authority.brief(path: surface.path, purpose:, school:)}
          aesthetic_direction=#{direction}
          design_school=#{school}
          design_coordinates=#{design_coordinates(direction)}
          memorable_element=#{DIRECTIONS.fetch(direction)[:memorable]}
          typography_direction=#{TYPOGRAPHY_HINTS.fetch(direction)}
          typography_contract=#{Master::Design::Typography.brief(path: surface.path, purpose:)}
          font_pairing=#{Master::Design::Pairing.brief(school:, purpose:)}
          composition=#{Master::Design::Composition.brief(school:, purpose:)}
          reference_lenses=#{Array(DIRECTIONS.fetch(direction)[:references]).join(",")}
          reference_mission=#{DIRECTIONS.fetch(direction)[:reference_mission]}
          external_reference_discipline=#{reference_discipline(direction)}
          surface_anatomy=#{surface_anatomy(surface)}
        TEXT
      end

      # What the render actually shows: the evidence half of the brief.
      def evidence_lines(payload)
        fp = fingerprint(payload)
        primary = Array(payload.dig("visual", "first_screen", "primary_candidates")).first
        genericity = fp[:genericity_signals]
        <<~TEXT
          primary_action_candidate=#{primary_action(primary)}
          current_palette=#{Array(fp.dig(:palette, :top)).first(5).join(", ")}
          current_component_language=#{fp.dig(:components, :language)}
          responsive_strategy=mobile-first composition, then preserve the same hierarchy as width expands
          preserve=#{preserve_signals(fp).join("; ")}
          genericity_signals=#{genericity.empty? ? "none observed" : genericity.join(", ")}
          Direction is an intent hypothesis, not a verdict. The rendered page remains ground truth; change the direction when repository evidence contradicts it.
        TEXT
      end

      def context(captures)
        blocks = Array(captures).map do |capture|
          surface = capture[:surface]
          payload = capture[:payload]
          [brief(surface:, payload:), "fingerprint=#{fingerprint_summary(payload)}"].join("\n")
        end
        return if blocks.empty?

        [
          "ART DIRECTION",
          "Authoritative design is priority 1: establish purpose, agency, clarity, hierarchy, trust, consistency, craft, and delight before selecting a visual school. Protect one memorable element and reject generic defaults only when they conflict with the product's purpose or rendered evidence.",
          blocks.join("\n\n"),
          reference_context,
        ].compact.join("\n")
      rescue StandardError => e
        "ART DIRECTION unavailable: #{e.class}: #{e.message}"
      end

      def reference_discipline(direction)
        study = reference_study
        case direction
        when :conversational
          Array(study.dig("antigravity", "useful_patterns")).first(5).join(",")
        when :local_social
          Array(study.dig("x", "useful_patterns")).first(5).join(",")
        when :marketplace, :transactional_food
          Array(study.dig("hey", "useful_patterns")).first(5).join(",")
        else
          Array(study.dig("shared_principles")).first(5).join(",")
        end
      end

      def surface_anatomy(surface)
        name = surface.app.to_s == "brgen" ? surface.label.to_s : surface.app.to_s
        rows = reference_study.fetch("vertical_anatomy", {})
        key = rows.key?(name) ? name : (surface.label.to_s)
        row = rows[key]
        return "generic task anatomy" unless row.is_a?(Hash)

        structure = Array(row["structure"]).join(" -> ")
        "attention=#{row["attention"]}; structure=#{structure}; lenses=#{Array(row["reference_lenses"]).join(",")}"
      end

        study = reference_study
        blocks = study.filter_map do |name, row|
          next unless row.is_a?(Hash)

          useful = Array(row["useful_patterns"]).first(7)
          avoid = Array(row["avoid"]).first(4)
          next if useful.empty? && avoid.empty?

          "#{name}: use=#{useful.join(",")}; avoid=#{avoid.join(",")}"
        end
        return if blocks.empty?

        "REFERENCE STUDY
#{blocks.join("
")}"
      end

      def fingerprint(payload)
        elements = Array(payload["elements"])
        visual = payload["visual"] || {}
        {
          palette: { top: Hash(payload["colors"] || {}).sort_by { |_, count| -count.to_i }.map(&:first).first(8) },
          typography: typography_fingerprint(elements, visual),
          spacing: spacing_fingerprint(payload),
          shape: shape_fingerprint(elements),
          effects: effects_fingerprint(elements),
          composition: composition_fingerprint(visual["first_screen"] || {}, elements),
          components: component_language(elements),
          genericity_signals: genericity_signals(elements, visual),
        }
      end

      def typography_fingerprint(elements, visual)
        {
          families: counts(elements.filter_map { |e| font_family(e["font_family"]) }).first(6),
          sizes: Array(visual.dig("typography", "distinct_font_sizes")).map(&:to_f).uniq.sort,
          body_median: visual.dig("typography", "body_median_px").to_f,
          heading_sizes: Array(visual.dig("typography", "heading_sizes")).map { |h| h["px"].to_f }.uniq.sort,
        }
      end

      # Gap sizes by frequency, and each group's outer gap over its inner padding.
      def spacing_fingerprint(payload)
        proximity = Array(payload["proximity"]).filter_map do |row|
          inner = row["pad"].to_f
          outer = row["gap"].to_f
          next if inner <= 0 || outer < 0

          (outer / inner).round(2)
        end
        { gaps: counts(Array(payload["gaps"]).filter_map { |row| row["gap"].to_i if row["gap"].to_i > 0 }).first(8),
          proximity: proximity.first(8) }
      end

      def effects_fingerprint(elements)
        {
          shadows: elements.count { |e| e["box_shadow"] == true },
          gradients: elements.count { |e| e["background_gradient"] == true },
          filters: elements.count { |e| e["visual_filter"] == true },
        }
      end

      def composition_fingerprint(first, elements)
        {
          first_screen_text: first["text_blocks"].to_i,
          first_screen_interactive: first["interactive"].to_i,
          largest_area_ratio: first["largest_element_area_ratio"].to_f,
          painted_area_ratio: first["painted_area_ratio_approx"].to_f,
          centered_long_text: first["centered_long_text"].to_i,
          small_text: first["small_text"].to_i,
          dominant_alignment: dominant_alignment(elements),
        }
      end

      def design_drift(before_payload, after_payload)
        before = before_payload["design_fingerprint"] || fingerprint(before_payload)
        after = after_payload["design_fingerprint"] || fingerprint(after_payload)
        changes = DRIFT_PATHS.filter_map do |label, path|
          from = normalize_hash(dig_any(before, *path))
          to = normalize_hash(dig_any(after, *path))
          "#{label}: #{from.inspect} -> #{to.inspect}" unless from == to
        end
        before_count = dig_any(before, :composition, :first_screen_interactive).to_f
        after_count = dig_any(after, :composition, :first_screen_interactive).to_f
        changes << "first-screen interactive count #{before_count.round} -> #{after_count.round}" if (before_count - after_count).abs >= 2
        changes
      rescue StandardError
        []
      end

      def fingerprint_summary(payload)
        fp = payload["design_fingerprint"] || fingerprint(payload)
        [
          "type=#{Array(fp.dig(:typography, :families)).map(&:first).join(",")}",
          "sizes=#{Array(fp.dig(:typography, :sizes)).join(",")}",
          "palette=#{Array(fp.dig(:palette, :top)).first(4).join(",")}",
          "rounded=#{fp.dig(:shape, :rounded).to_i}",
          "shadows=#{fp.dig(:effects, :shadows).to_i}",
          "gradients=#{fp.dig(:effects, :gradients).to_i}",
          "alignment=#{fp.dig(:composition, :dominant_alignment)}",
          "density=#{fp.dig(:composition, :first_screen_interactive).to_i} interactive / #{fp.dig(:composition, :first_screen_text).to_i} text",
        ].join(" ")
      end

      def direction_for(surface)
        haystack = [surface.app, surface.label, surface.host, surface.path].compact.join("/").downcase
        DIRECTIONS.each { |name, spec| return name if spec[:match].match?(haystack) }
        :content_first
      end

      def design_coordinates(direction)
        spec = DIRECTIONS.fetch(direction)
        AXES.map { |axis| "#{axis}=#{spec.fetch(axis)}" }.join(" ")
      end

      def purpose_for(surface)
        path = surface.path.to_s
        PURPOSE_HINTS.find { |needle, _| path == needle || path.include?(needle) }&.last ||
          "serve the task named by #{surface.label}"
      end

      def primary_action(candidate)
        return "none detected" unless candidate.is_a?(Hash)

        text = candidate["text"].to_s.strip
        aria = candidate["aria"].to_s.strip
        [text, aria].reject(&:empty?).first || candidate["tag"].to_s
      end

      def preserve_signals(fp)
        first = fp[:composition]
        values = []
        values << "existing visual mass" if first[:largest_area_ratio].positive?
        values << "existing content density" if first[:first_screen_text].positive?
        values << "existing palette" if fp.dig(:palette, :top).any?
        values << "existing component vocabulary" if fp.dig(:components, :language).to_s != "none"
        values
      end

      def font_family(value)
        raw = value.to_s
        return if raw.empty?

        raw.split(",").first.to_s.gsub(/["']/, "").strip.downcase
      end

      def counts(values)
        values.compact.tally.sort_by { |_, count| -count }.first(8)
      end

      def shape_fingerprint(elements)
        radii = elements.map { |e| radius_value(e["border_radius"]) }.compact
        rounded = radii.count { |value| value >= 8 }
        pills = radii.count { |value| value >= 999 }
        cards = elements.count { |e| card_like?(e) }
        buttons = elements.count { |e| %w[button submit].include?(e["tag"].to_s) }
        { rounded:, pills:, cards:, buttons:, max_radius: radii.max }
      end

      def radius_value(value)
        raw = value.to_s
        return if raw.empty? || raw == "0px" || raw == "none"

        raw.split("/").first.scan(/\d+(?:\.\d+)?/).map(&:to_f).max
      end

      def card_like?(element)
        key = element["key"].to_s
        tag = element["tag"].to_s
        tag == "article" || key.match?(/(^|[>._-])card(?:[._\[\]>-]|$)/i)
      end

      def component_language(elements)
        tags = elements.map { |e| e["tag"].to_s }.reject(&:empty?).tally
        cards = elements.count { |e| card_like?(e) }
        rounded = elements.count { |e| radius_value(e["border_radius"]).to_f >= 8 }
        language = [
          ("cards=#{cards}" if cards.positive?),
          ("rounded=#{rounded}" if rounded.positive?),
          ("buttons=#{tags["button"]}" if tags["button"].to_i.positive?),
          ("inputs=#{tags["input"]}" if tags["input"].to_i.positive?),
        ].compact.join(" ")
        { tags: tags.sort_by { |_, count| -count }.first(6), language: language.empty? ? "none" : language }
      end

      def dominant_alignment(elements)
        elements.map { |e| e["text_align"].to_s }.reject(&:empty?).tally.max_by { |_, count| count }&.first || "unknown"
      end

      def genericity_signals(elements, visual)
        shape = shape_fingerprint(elements)
        shadows = elements.count { |e| e["box_shadow"] == true }
        gradients = elements.count { |e| e["background_gradient"] == true }
        first = visual["first_screen"] || {}
        signals = []
        signals << "gradient_focal_area" if gradients.positive? && first["centered_long_text"].to_i.positive?
        signals << "rounded_card_system" if shape[:cards] >= 6 && shape[:rounded] >= 6
        signals << "shadow_card_system" if shape[:cards] >= 6 && shadows >= 6
        signals << "pill_overload" if shape[:pills] >= 6
        signals << "centered_hero_pattern" if first["centered_long_text"].to_i.positive? && first["largest_element_area_ratio"].to_f > 0.2
        signals
      end

      def dig_any(hash, *keys)
        keys.reduce(hash) do |value, key|
          break unless value.is_a?(Hash)

          value[key] || value[key.to_s] || value[key.to_sym]
        end
      end

      def normalize_hash(value)
        value.is_a?(Hash) ? value.transform_keys(&:to_s) : value
      end
    end
  end
end
