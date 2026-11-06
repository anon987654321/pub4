# frozen_string_literal: true

module Deploy
  module RenderedDesign
    # Type on the rendered page: Bringhurst, Butterick and Vignelli, measured.
    module TypeLaws
      PROSE = %w[p li dd].freeze
      ROLES = %w[meta body title display].freeze
      WEIGHT_NAMES = {
        /thin|hairline/i => 100, /extralight|ultralight/i => 200, /light/i => 300, /medium/i => 500,
        /semibold|demibold/i => 600, /extrabold|ultrabold/i => 800, /black|heavy/i => 900, /bold/i => 700
      }.freeze

      module_function

      def size_economy(view)
        texts = RenderedDesign.texts(view)
        sizes = texts.map { |element| (element["font_size"].to_f * 2).round / 2.0 }.uniq.sort
        weights = texts.map { |element| element["font_weight"].to_i }.uniq.sort
        [count_finding(view, sizes), weight_finding(weights), off_token(view, sizes)]
      end

      def count_finding(view, sizes)
        return if sizes.size <= 4

        level = sizes.size > 5 ? "error" : "warning"
        "#{level}: #{sizes.size} sizes at #{view["width"]} (#{sizes.join(", ")}px); four is the economy"
      end

      def weight_finding(weights)
        "warning: #{weights.size} weights (#{weights.join(", ")}); two is the economy" if weights.size > 2
      end

      def off_token(view, sizes)
        root = view.dig("page", "root_font").to_f.nonzero? || 16.0
        allowed = size_tokens.map { |rem| rem * root } + display_sizes
        off = sizes.reject { |px| allowed.any? { |token| (token - px).abs <= 0.5 } }
        "error: #{off.join(", ")}px is no type token at #{view["width"]}" if off.any?
      end

      # The four shared_chrome sizes (meta, body, title, display), in rem.
      def size_tokens
        chrome = RenderedDesign.tokens.dig("tokens", "shared_chrome") || {}
        ROLES.filter_map { |role| chrome["font_size_#{role}"].to_s[/\A(\d*\.?\d+)rem\z/, 1]&.to_f }
      end

      def display_sizes
        display = RenderedDesign.tokens.dig("tokens", "visual_identity", "display_size").to_s
        display.scan(/(\d+(?:\.\d+)?)px/).flatten.map(&:to_f)
      end

      Type = Struct.new(:key, :size, :lead, :track, :multi, :prose, keyword_init: true)

      def type_of(element)
        size = element["font_size"].to_f
        Type.new(key: element["key"], size:, lead: (element["line_height"].to_f / size).round(2),
                 track: (element["letter_spacing"].to_f / size).round(3), multi: element["lines"].to_i >= 2,
                 prose: PROSE.include?(element["tag"]))
      end

      def spacing(element)
        type = type_of(element)
        return display_spacing(type) if type.size >= 28
        return prose_spacing(type) if type.size >= 15

        small_spacing(type) if type.size < 14
      end

      def display_spacing(type)
        return unless type.lead > 1.25 || type.track.positive?

        "warning: #{type.key} #{type.size.round}px leads #{type.lead} and tracks #{type.track}em; display type tightens"
      end

      def prose_spacing(type)
        return unless type.prose && type.multi && !type.lead.between?(1.4, 1.6)

        "warning: #{type.key} prose at #{type.size.round}px leads #{type.lead}, outside 1.4-1.6"
      end

      def small_spacing(type)
        at = "#{type.key} #{type.size.round}px"
        return "error: #{at} is tracked tight (#{type.track}em); small type opens" if type.track.negative?

        "warning: #{at} leads #{type.lead}; small type needs 1.4" if type.multi && type.lead < 1.4
      end

      def face_name(face) = "#{face["postScriptName"]} #{face["familyName"]}"

      def painted_weight(face)
        name = face_name(face)
        WEIGHT_NAMES.find { |pattern, _weight| name.match?(pattern) }&.last || 400
      end

      def faux(row)
        face = Array(row["platform"]).max_by { |painted| painted["glyphCount"].to_i } or return []
        family = row["family"]
        asked = row["weight"].to_i
        painted = painted_weight(face)
        [(asked - painted).abs >= 100 && "warning: #{family} #{asked} paints as #{face["postScriptName"]} (#{painted})",
         synthesized(row, face:, asked:, painted:),
         row["caps"].to_s.include?("small-caps") && !face["isCustomFont"] && "error: #{family} has no true small caps"]
      end

      def synthesized(row, face:, asked:, painted:)
        synthesis = row["synthesis"].to_s
        bold = asked >= 600 && painted < 600 && synthesis.include?("weight")
        return "error: #{row["family"]} #{asked} is synthesized bold" if bold

        italic = row["style"] == "italic" && !face_name(face).match?(/italic|oblique/i)
        "error: #{row["family"]} italic is synthesized" if italic && synthesis.include?("style")
      end

      def capitals?(element)
        text = element["text"].to_s
        element["text_transform"] == "uppercase" || (text.match?(/\A[^\p{Ll}]{4,}\z/) && text.match?(/\p{L}/))
      end

      def caps(element)
        return unless capitals?(element)

        text = element["text"].to_s
        lines = element["lines"].to_i
        key = element["key"]
        long = text.length > 24 || lines > 1
        return "warning: #{key} sets #{text.length} characters in capitals over #{lines} line(s)" if long

        size = element["font_size"].to_f
        track = (element["letter_spacing"].to_f / size).round(3)
        loose = size >= 20 && !track.between?(0.05, 0.15)
        "info: #{key} display capitals tracked #{track}em, outside 0.05-0.15" if loose
      end

      def emphasis(element)
        key = element["key"]
        underlined = element["decoration"].to_s.include?("underline") && element["tag"] != "a" && !element["in_link"]
        return "warning: #{key} is underlined and is no link" if underlined

        both = element["font_weight"].to_i >= 600 && element["font_style"] == "italic"
        "warning: #{key} is bold and italic at once" if both
      end

      def paragraphs(view)
        paras = RenderedDesign.elements(view).select { |element| element["tag"] == "p" }
        both = paras.each_cons(2).filter_map { |prev, cur| both_devices(prev, cur) }
        both + paras.filter_map { |element| indented_opening(element) }
      end

      def both_devices(prev, cur)
        return unless prev["pid"] == cur["pid"] && cur["text_indent"].to_f.positive?

        gap = [prev.dig("margin_block", 1).to_f, cur.dig("margin_block", 0).to_f].max
        "warning: #{cur["key"]} is indented and spaced #{gap.round}px; one device" if gap > cur["font_size"].to_f / 2
      end

      def indented_opening(element)
        after = element["prev_tag"].to_s
        first = after.empty? || after.match?(/\Ah[1-6]\z/)
        "info: #{element["key"]} opens a run indented" if first && element["text_indent"].to_f.positive?
      end

      def numbers(view)
        Array(view["numbers"]).filter_map do |row|
          next unless row["tops"].to_i > 1

          "error: #{row["text"].inspect} in #{row["key"]} breaks over #{row["tops"]} lines at #{view["width"]}"
        end
      end
    end

    register(:NUMBER_UNIT_UNBROKEN) { |snap| each_view(snap) { |view| TypeLaws.numbers(view) } }
    register(:TYPE_SIZE_ECONOMY) { |snap| each_view(snap, [390]) { |view| TypeLaws.size_economy(view) } }

    register(:SIZE_COMPENSATED_SPACING) { |snap| each_text(snap) { |element| TypeLaws.spacing(element) } }
    register(:NO_FAUX_TYPE) { |snap| Array(snap["fonts"]).flat_map { |row| TypeLaws.faux(row) } }
    register(:CAPS_RUN_SHORT) { |snap| each_text(snap) { |element| TypeLaws.caps(element) } }
    register(:EMPHASIS_ONE_DEVICE) { |snap| each_text(snap) { |element| TypeLaws.emphasis(element) } }
    register(:PARAGRAPH_SEPARATION_ONE_DEVICE) { |snap| each_view(snap) { |view| TypeLaws.paragraphs(view) } }
  end
end
