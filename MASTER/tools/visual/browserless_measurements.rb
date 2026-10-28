# frozen_string_literal: true

require "base64"
require "cgi"
require "uri"

module Master
  module Visual
    # Deterministic, offline measurements for fixed-viewport ad creatives.
    # It never executes scripts or fetches URLs. Exact box geometry is reported
    # only for explicitly positioned/sized roles; heuristic geometry is marked
    # estimated and does not satisfy the high-confidence safe-zone gate.
    module BrowserlessMeasurements
      VERSION = 1
      VOID_TAGS = %w[area base br col embed hr img input link meta param source track wbr].freeze
      BLOCK_TAGS = %w[address article aside blockquote body div dl fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p section table ul video].freeze
      INHERITED = %w[color font-family font-size font-style font-weight letter-spacing line-height text-align].freeze
      Node = Struct.new(:tag, :attributes, :parent, :children, :geometry_confidence, keyword_init: true)
      Rule = Struct.new(:selector, :declarations, :specificity, :order, keyword_init: true)
      module_function

      def static_render_integrity_status(rendered)
        return :not_static unless rendered.is_a?(Hash) &&
          (rendered[:measurement_mode] || rendered["measurement_mode"]) == "browserless_static"
        evidence = rendered[:integrity] || rendered["integrity"]
        return :invalid unless evidence.is_a?(Hash) &&
          (evidence[:source_analyzed] || evidence["source_analyzed"]) == true &&
          (evidence[:static_layout_complete] || evidence["static_layout_complete"]) == true &&
          !evidence.key?(:cumulative_layout_shift) && !evidence.key?("cumulative_layout_shift")
        stability = evidence[:layout_stability] || evidence["layout_stability"]
        return :invalid unless stability.is_a?(Hash) &&
          (stability[:basis] || stability["basis"]) == "browserless_structural_proxy_not_measured_cls" &&
          (stability[:pass] || stability["pass"]) == true
        :valid
      end

      def measure(html:, css:, placement:, token_contract:, asset_root: nil, viewport: nil)
        Engine.new(html:, css:, placement:, token_contract:, asset_root:, viewport:).measure
      end

      class Engine
        def initialize(html:, css:, placement:, token_contract:, asset_root:, viewport:)
          @html, @css, @placement, @contract = html.to_s, css.to_s, placement.to_s, token_contract
          @asset_root = File.expand_path(asset_root || Dir.pwd)
          @requested_viewport = viewport
          @diagnostics, @unsupported, @rules, @assets = [], [], [], []
          @boxes, @styles, @nodes = {}, {}, []
          @asset_bytes = 0
          @rule_order = 0
        end

        def measure
          @viewport = viewport_size
          @document = parse_html
          embedded = @nodes.select { |n| n.tag == "style" }.map { |n| n.children.grep(String).join }.join("\n")
          inline = @nodes.filter_map { |n| n.attributes["style"] }
          @analysis_css = [@css, embedded, *inline].reject(&:empty?).join("\n")
          parse_css(@analysis_css)
          detect_runtime_features
          measure_assets
          layout
          roles = find_roles
          bounds = roles.to_h { |name, node| [name, @boxes[node.object_id]] }.compact
          missing = %w[headline logo cta] - bounds.keys
          @diagnostics.concat(missing.map { |role| "could not locate measurable #{role} element" })
          safe_zone = make_safe_zone(bounds, roles)
          pairs = contrast_pairs(roles)
          disclosure = disclosure_evidence(roles)
          text_fit = measure_text_fit(roles)
          @diagnostics.concat(text_fit.reject { |item| item["pass"] }.map { |item| "#{item["role"]} text may overflow its measured box" })
          collisions = layout_collisions(roles)
          @diagnostics.concat(collisions.map { |item| "#{item["first"]} overlaps #{item["second"]}" })
          stability = stability_evidence(roles, text_fit, collisions)
          structural = missing.empty? && @unsupported.empty? && safe_zone["geometry_confidence"] == "high" &&
                       text_fit.all? { |item| item["pass"] } && collisions.empty? && stability["pass"]
          evidence = {
            "measurement_mode" => "browserless_static",
            "measurement_version" => VERSION,
            "viewport" => @viewport,
            "contrast_pairs" => pairs,
            "disclosure" => disclosure,
            "safe_zone" => safe_zone,
            "integrity" => {
              "assets_loaded" => @assets.all? { |asset| asset["loaded"] == true },
              "transfer_bytes" => @html.bytesize + @css.bytesize + @asset_bytes,
              "source_analyzed" => true,
              "static_layout_complete" => structural,
              "layout_stability" => stability,
            },
          }
          {
            rendered: evidence,
            measurements: {
              "engine" => "browserless_static",
              "version" => VERSION,
              "viewport" => @viewport,
              "asset_inventory" => @assets,
              "role_bounds" => bounds,
              "text_fit" => text_fit,
              "collisions" => collisions,
              "diagnostics" => @diagnostics.uniq,
              "unsupported_features" => @unsupported.uniq,
              "confidence" => structural ? "high" : "estimated",
            },
          }
        end

        private

        def viewport_size
          given = @requested_viewport
          if given.is_a?(Hash)
            width = given["width"] || given[:width]
            height = given["height"] || given[:height]
            return { "width" => Integer(width), "height" => Integer(height) } if width && height && width.to_i.positive? && height.to_i.positive?
          end
          match = @placement.match(/(?:^|[^0-9])(\d{2,5})\s*[x×]\s*(\d{2,5})(?:$|[^0-9])/i)
          raise ArgumentError, "placement must encode WIDTHxHEIGHT or provide manifest viewport" unless match

          { "width" => Integer(match[1]), "height" => Integer(match[2]) }
        end

        def parse_html
          document = Node.new(tag: "#document", attributes: {}, parent: nil, children: [])
          stack = [document]
          @html.scan(/<!--.*?-->|<![^>]*>|<\/?[\w:-]+\b[^>]*>|[^<]+/m).each do |token|
            next if token.start_with?("<!--", "<!")
            if token.start_with?("</")
              tag = token[/\A<\/\s*([\w:-]+)/, 1].to_s.downcase
              index = stack.rindex { |node| node.tag == tag }
              stack.slice!(index..-1) if index && index.positive?
            elsif token.start_with?("<")
              tag = token[/\A<\s*([\w:-]+)/, 1].to_s.downcase
              next if tag.empty?
              attrs, rest = {}, token.sub(/\A<\s*[\w:-]+/, "").sub(/\/?>\s*\z/, "")
              rest.scan(/([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+)))?/m).each do |m|
                attrs[m[0].downcase] = CGI.unescapeHTML(m[1] || m[2] || m[3] || "")
              end
              node = Node.new(tag:, attributes: attrs, parent: stack.last, children: [], geometry_confidence: "estimated")
              stack.last.children << node
              @nodes << node
              stack << node unless VOID_TAGS.include?(tag) || token.match?(/\/\s*>\z/)
            else
              stack.last.children << CGI.unescapeHTML(token)
            end
          end
          document
        end

        def parse_css(text)
          parse_css_blocks(text.gsub(%r{/\*.*?\*/}m, ""))
        end

        def parse_css_blocks(text)
          cursor = 0
          while (open_index = text.index("{", cursor))
            selector = text[cursor...open_index].to_s.strip
            depth, index, quote, escaped = 1, open_index + 1, nil, false
            while index < text.length && depth.positive?
              char = text[index]
              if quote
                if escaped then escaped = false
                elsif char == "\\" then escaped = true
                elsif char == quote then quote = nil
                end
              elsif char == '"' || char == "'"
                quote = char
              elsif char == "{"
                depth += 1
              elsif char == "}"
                depth -= 1
              end
              index += 1
            end
            break if depth.positive?
            body = text[(open_index + 1)...(index - 1)].to_s
            cursor = index
            next if selector.empty?
            if selector.match?(/\A@media\b/i)
              condition = selector.sub(/\A@media\s*/i, "")
              decision = media_matches?(condition)
              if decision.nil?
                @unsupported << "unrecognised media query: #{condition}"
              elsif decision
                parse_css_blocks(body)
              end
            elsif selector.match?(/\A@font-face\b/i)
              @unsupported << "web-font loading cannot be measured without a browser"
            elsif selector.match?(/\A@import\b/i)
              @unsupported << "CSS @import cannot be resolved offline"
            elsif selector.start_with?("@")
              @unsupported << "unsupported CSS at-rule: #{selector.split(/\s+/, 2).first}"
            else
              declarations = parse_declarations(body)
              selector.split(",").map(&:strip).reject(&:empty?).each do |part|
                if part.match?(/::|:(?!root\b)|\[[^\]]*[~|^$*]=|[>+~]/)
                  @unsupported << "dynamic or unsupported selector: #{part}"
                  next
                end
                @rule_order += 1
                @rules << Rule.new(selector: part, declarations:, specificity: specificity(part), order: @rule_order)
              end
            end
          end
        end

        def media_matches?(condition)
          matches = condition.scan(/\(\s*(min|max)-(width|height)\s*:\s*([\d.]+)px\s*\)/i)
          residue = condition.gsub(/\(\s*(?:min|max)-(?:width|height)\s*:\s*[\d.]+px\s*\)/i, "")
                           .gsub(/\b(?:and|screen|all|only)\b/i, "").strip
          return if matches.empty? || !residue.gsub(/[()]/, "").strip.empty?

          matches.all? do |bound, axis, value|
            actual = @viewport.fetch(axis.downcase)
            bound.downcase == "min" ? actual >= value.to_f : actual <= value.to_f
          end
        end

        def parse_declarations(block)
          block.split(";").filter_map do |item|
            key, value = item.split(":", 2)
            next unless key && value && key.strip.match?(/\A[a-z-]+\z/i)
            [key.strip.downcase, value.strip.sub(/\s*!important\s*\z/i, "").strip]
          end.to_h
        end

        def specificity(selector)
          [selector.scan(/#[\w-]+/).size * 100 + selector.scan(/\.[\w-]+|\[[\w-]+(?:=[^\]]+)?\]/).size * 10 +
            selector.scan(/(?:^|\s|>)[a-z][\w-]*/i).size, @rule_order]
        end

        def match_simple?(node, part)
          return false unless node
          return node.tag == "html" if part == ":root"
          return false if part.include?(":") && part != ":root"
          tag = part[/\A[a-z][\w-]*/i]
          return false if tag && node.tag != tag.downcase
          return false if part.scan(/#([\w-]+)/).flatten.any? { |id| node.attributes["id"] != id }
          classes = part.scan(/\.([\w-]+)/).flatten
          node_classes = node.attributes.fetch("class", "").split
          return false if classes.any? { |value| !node_classes.include?(value) }
          part.scan(/\[([\w-]+)(?:=["']?([^"' \]]+)["']?)?\]/).each do |key, value|
            return false unless node.attributes.key?(key)
            return false if value && node.attributes[key] != value
          end
          true
        end

        def selector_matches?(node, selector)
          parts = selector.split(/\s+/)
          current = node
          return false unless match_simple?(current, parts.pop)
          parts.reverse_each do |part|
            current = current.parent
            current = current.parent while current && current.tag != "#document" && !match_simple?(current, part)
            return false unless current && match_simple?(current, part)
          end
          true
        end

        def detect_runtime_features
          @unsupported << "JavaScript may mutate the measured layout" if @nodes.any? { |n| n.tag == "script" && n.attributes["type"] != "application/ld+json" }
          @unsupported << "external stylesheet is not embedded in manifest CSS" if @nodes.any? { |n| n.tag == "link" && n.attributes["rel"].to_s.split.include?("stylesheet") }
          @unsupported << "CSS Grid is outside the browserless layout subset" if @analysis_css.match?(/display\s*:\s*(?:inline-)?grid\b|grid-template-/i)
          @unsupported << "complex CSS geometry is outside the browserless layout subset" if @analysis_css.match?(/(?:width|height|top|left|right|bottom|inset|margin|padding|font-size|line-height|gap)\s*:\s*(?:calc|clamp|min|max)\s*\(/i)
          @unsupported << "transforms, clipping, zoom or overflow may change visual bounds" if @analysis_css.match?(/\b(?:transform|zoom|clip-path|mask|overflow(?:-[xy])?)\s*:/i)
          @unsupported << "opacity changes contrast and cannot be certified statically" if @analysis_css.match?(/opacity\s*:\s*(?!1(?:\.0+)?\s*[;}])[^;}]+/i)
          @unsupported << "background image/gradient cannot be certified as a solid colour" if @analysis_css.match?(/\bbackground(?:-image)?\s*:\s*(?:url\s*\(|(?:linear|radial|conic)-gradient\s*\()/i)
          @unsupported << "canonical ad tokens may not be redefined in creative CSS" if @analysis_css.match?(/--ad-organ-(?:surface|on-surface|accent|disclosure-background|disclosure-foreground)\s*:/i)
          @unsupported << "responsive image selection is outside the static asset subset" if @nodes.any? { |node| node.tag == "picture" || node.attributes.key?("srcset") || node.attributes.key?("sizes") }
          @unsupported << "runtime media/embed element is outside the static layout subset" if @nodes.any? { |node| %w[iframe video audio canvas object embed].include?(node.tag) }
          @unsupported << "letter/word spacing changes estimated glyph widths" if @analysis_css.match?(/(?:letter-spacing|word-spacing)\s*:\s*(?!0(?:px|em|rem)?\s*[;}])[^;}]+/i)
          @unsupported << "text-transform changes estimated glyph widths" if @analysis_css.match?(/text-transform\s*:\s*(?!none\b)[^;}]+/i)
          @unsupported << "layout animation or transition may change geometry" if @analysis_css.match?(/(?:animation(?:-name)?|transition(?:-property)?)\s*:[^;}]*(?:all|width|height|top|left|right|bottom|margin|padding|flex|grid)/i)
          @unsupported << "network font source is present" if @analysis_css.match?(/url\(\s*['"]?https?:\/\/[^)]*\.(?:woff2?|ttf|otf)/i)
          families = @analysis_css.scan(/font-family\s*:\s*([^;}]+)/i).flatten.map { |item| item.gsub(/['"]/, "").strip.downcase }
          safe_families = %w[arial courier georgia helvetica monospace sans-serif serif system-ui tahoma verdana]
          custom = families.flat_map { |item| item.split(",").map(&:strip) }.reject { |item| safe_families.include?(item) }
          @unsupported << "non-system font metrics cannot be proven: #{custom.uniq.join(', ')}" unless custom.empty?
          body = @nodes.find { |node| node.tag == "body" }
          if body
            body_style = styles(body)
            margin = body_style["margin"].to_s.strip
            side_margins = %w[margin-top margin-right margin-bottom margin-left].map { |key| body_style[key].to_s.strip }
            reset = margin.match?(/\A0(?:px|rem|em)?\z/) || side_margins.all? { |value| value.match?(/\A0(?:px|rem|em)?\z/) }
            padding = body_style["padding"].to_s.strip
            side_padding = %w[padding-top padding-right padding-bottom padding-left].map { |key| body_style[key].to_s.strip }
            no_padding = padding.match?(/\A0(?:px|rem|em)?\z/) || side_padding.all? { |value| value.match?(/\A0(?:px|rem|em)?\z/) }
            @unsupported << "body margin/padding reset is not explicit; user-agent geometry may differ" unless reset && no_padding
          end
          html = @nodes.find { |node| node.tag == "html" }
          if html
            html_style = styles(html)
            %w[margin margin-top margin-right margin-bottom margin-left padding padding-top padding-right padding-bottom padding-left].each do |property|
              value = html_style[property].to_s.strip
              @unsupported << "non-zero html margin/padding is outside the static viewport model" if !value.empty? && !value.match?(/\A0(?:px|rem|em)?\z/)
            end
          end
          @nodes.select { |node| node.tag.match?(/\Ah[1-6]\z/) }.each do |heading|
            @unsupported << "heading font size depends on user-agent defaults" unless explicit_property?(heading, "font-size")
            heading_style = styles(heading)
            margins = %w[margin-top margin-right margin-bottom margin-left].map { |key| heading_style[key].to_s.strip }
            reset_margin = heading_style["margin"].to_s.strip.match?(/\A0(?:px|rem|em)?\z/) ||
                           margins.all? { |value| value.match?(/\A0(?:px|rem|em)?\z/) }
            @unsupported << "heading margin depends on user-agent defaults" unless reset_margin
          end
          @nodes.select { |node| node.tag == "a" && !text_content(node).empty? }.each do |link|
            @unsupported << "anchor colour depends on user-agent defaults" unless explicit_property?(link, "color")
          end

          roles = find_roles
          critical_nodes = []
          roles.values.each do |role_node|
            current = role_node
            while current && current.tag != "#document"
              critical_nodes << current
              break if current.attributes.fetch("class", "").split.include?("ad-organ")
              current = current.parent
            end
          end
          critical_nodes.uniq.each do |node|
            style = styles(node)
            box_properties = %w[margin margin-top margin-right margin-bottom margin-left padding padding-top padding-right padding-bottom padding-left border border-width border-top-width border-right-width border-bottom-width border-left-width]
            nonzero = box_properties.filter_map do |property|
              value = style[property].to_s.strip
              property if !value.empty? && !value.match?(/\A(?:0(?:px|rem|em)?|none)\z/)
            end
            @unsupported << "non-zero margin/padding/border on critical boxes is outside the static layout subset: #{nonzero.join(', ')}" unless nonzero.empty?
          end
          roles.each do |role, node|
            style = styles(node)
            next unless %w[cta disclosure].include?(role)
            next if %w[block inline-block flex inline-flex].include?(style["display"])
            @unsupported << "#{role} must explicitly establish a block box for static size measurements"
          end
        end

        def explicit_property?(node, property)
          inline = parse_declarations(node.attributes["style"] || "")
          inline.key?(property) || @rules.any? { |rule| rule.declarations.key?(property) && selector_matches?(node, rule.selector) }
        end

        def styles(node, inherited = {}, mode: "light")
          out = inherited.select { |key, _| INHERITED.include?(key) }.dup
          @rules.select { |rule| selector_matches?(node, rule.selector) }
                .sort_by { |rule| [rule.specificity, rule.order] }
                .each { |rule| out.merge!(rule.declarations) }
          out.merge!(parse_declarations(node.attributes["style"])) if node.attributes["style"]
          out["font-size"] ||= inherited["font-size"] || "16px"
          out["line-height"] ||= inherited["line-height"] || "1.2"
          out["font-weight"] ||= inherited["font-weight"] || "400"
          out["font-weight"] = "700" if node.tag.match?(/\Ah[1-6]\z/) && !explicit_property?(node, "font-weight")
          out["color"] ||= inherited["color"] || "var(--ad-organ-on-surface)"
          out["background-color"] ||= out["background"]
          out["__mode"] = mode
          out
        end

        def layout
          html = @document.children.find { |n| n.is_a?(Node) && n.tag == "html" }
          if html
            @boxes[html.object_id] = box(0, 0, @viewport["width"], @viewport["height"], "high")
            html_style = styles(html)
            @styles[html.object_id] = html_style
            body = descendants(html).find { |node| node.tag == "body" }
            if body
              @boxes[body.object_id] = box(0, 0, @viewport["width"], @viewport["height"], "high")
              @styles[body.object_id] = styles(body, html_style)
              layout_children(body, @boxes[body.object_id], @styles[body.object_id])
            else
              layout_children(html, @boxes[html.object_id], html_style)
            end
          else
            @boxes[@document.object_id] = box(0, 0, @viewport["width"], @viewport["height"], "high")
            layout_children(@document, @boxes[@document.object_id], {})
          end
        end

        def layout_children(parent, parent_box, parent_style)
          children = parent.children.select { |n| n.is_a?(Node) && !%w[style script].include?(n.tag) }
          return if children.empty?
          pstyle = styles(parent, parent_style)
          flex = %w[flex inline-flex].include?(pstyle["display"])
          column = pstyle["flex-direction"] == "column"
          gap = px(pstyle["gap"] || pstyle[column ? "row-gap" : "column-gap"] || "0", parent_box["width"], font_px(pstyle)) || 0
          pad_l = px(pstyle["padding-left"] || "0", parent_box["width"], font_px(pstyle)) || 0
          pad_t = px(pstyle["padding-top"] || "0", parent_box["height"], font_px(pstyle)) || 0
          pad_r = px(pstyle["padding-right"] || "0", parent_box["width"], font_px(pstyle)) || 0
          pad_b = px(pstyle["padding-bottom"] || "0", parent_box["height"], font_px(pstyle)) || 0
          x0, y0 = parent_box["x"] + pad_l, parent_box["y"] + pad_t
          available_w, available_h = parent_box["width"] - pad_l - pad_r, parent_box["height"] - pad_t - pad_b
          cursor_x, cursor_y = x0, y0
          children.each do |child|
            style = styles(child, pstyle)
            next if style["display"] == "none" || child.attributes.key?("hidden")
            absolute = %w[absolute fixed].include?(style["position"])
            forced = nil
            unless absolute
              if flex
                w = px(style["width"], available_w, font_px(style)) || (column ? available_w : intrinsic_width(child, style, available_w))
                h = px(style["height"], available_h, font_px(style)) || intrinsic_height(child, style, w)
                forced = box(cursor_x, cursor_y, w, h, "estimated")
                if column then cursor_y += h + gap
                else cursor_x += w + gap
                end
              elsif !inline_element?(child)
                h = px(style["height"], available_h, font_px(style)) || intrinsic_height(child, style, available_w)
                frame_width = px(style["width"], available_w, font_px(style)) || available_w
                frame_confidence = if parent.tag == "body" &&
                    child.attributes.fetch("class", "").split.include?("ad-organ") &&
                    cursor_y == parent_box["y"] && cursor_x == x0 &&
                    px(style["width"], available_w, font_px(style)) && px(style["height"], available_h, font_px(style)) &&
                    !%w[absolute fixed].include?(style["position"])
                  "high"
                else
                  "estimated"
                end
                forced = box(x0, cursor_y, frame_width, h, frame_confidence)
                cursor_y += h + (px(style["margin-bottom"], available_w, font_px(style)) || 0)
              else
                w = px(style["width"], available_w, font_px(style)) || intrinsic_width(child, style, available_w)
                h = px(style["height"], available_h, font_px(style)) || intrinsic_height(child, style, w)
                forced = box(cursor_x, cursor_y, w, h, "estimated")
                cursor_x += w
                if cursor_x > x0 + available_w
                  cursor_x, cursor_y = x0, cursor_y + h
                end
              end
            end
            layout_node(child, parent_box, pstyle, forced:)
          end
        end

        def layout_node(node, parent_box, parent_style, forced: nil)
          style = styles(node, parent_style)
          @styles[node.object_id] = style
          return if style["display"] == "none" || node.attributes.key?("hidden")
          pw, ph, fs = parent_box["width"], parent_box["height"], font_px(style)
          width = px(style["width"], pw, fs) || numeric_attr(node, "width") || image_dims(node)&.first ||
                  (inline_element?(node) ? intrinsic_width(node, style, pw) : pw)
          height = px(style["height"], ph, fs) || numeric_attr(node, "height") || image_dims(node)&.last || intrinsic_height(node, style, width)
          if forced
            x, y = forced.values_at("x", "y")
            width = px(style["width"], pw, fs) || forced["width"]
            height = px(style["height"], ph, fs) || forced["height"]
            confidence = forced["confidence"]
          elsif %w[absolute fixed].include?(style["position"])
            left, right = px(style["left"], pw, fs), px(style["right"], pw, fs)
            top, bottom = px(style["top"], ph, fs), px(style["bottom"], ph, fs)
            x = parent_box["x"] + (left || (right ? pw - right - width : 0))
            y = parent_box["y"] + (top || (bottom ? ph - bottom - height : 0))
            confidence = if left && top && px(style["width"], pw, fs) && px(style["height"], ph, fs) && parent_box["confidence"] == "high"
              "high"
            else
              "estimated"
            end
          else
            x, y, confidence = parent_box["x"], parent_box["y"], "estimated"
          end
          node.geometry_confidence = confidence
          @boxes[node.object_id] = box(x, y, width, height, confidence)
          layout_children(node, @boxes[node.object_id], style) unless VOID_TAGS.include?(node.tag)
        end

        def intrinsic_width(node, style, available)
          size = font_px(style)
          [text_width(text_content(node), size, style["font-weight"]), available].min
        end

        def intrinsic_height(node, style, width)
          size = font_px(style)
          text = text_content(node)
          line_height = line_px(style, size)
          lines = text.empty? ? 0 : [(text_width(text, size, style["font-weight"]) / [width, 1].max).ceil, 1].max
          padding = (px(style["padding-top"], width, size) || 0) + (px(style["padding-bottom"], width, size) || 0)
          [lines * line_height + padding, size.zero? ? 0 : line_height].max
        end

        def text_content(node)
          node.children.map { |child| child.is_a?(String) ? child : text_content(child) }.join(" ").gsub(/\s+/, " ").strip
        end

        def text_width(text, size, weight)
          em = text.to_s.each_char.sum do |char|
            case char
            when /\s/ then 0.28
            when /[ilI.,'!:;|]/ then 0.27
            when /[MW@%#&]/ then 0.88
            when /[A-Z]/ then 0.64
            when /[0-9]/ then 0.56
            when /[\u{2E80}-\u{9FFF}]/ then 1.0
            else 0.52
            end
          end
          em *= 1.04 if weight.to_s.to_i >= 600
          (em * size).ceil
        end

        def line_px(style, size)
          value = style["line-height"].to_s.strip
          return size * value.to_f if value.match?(/\A\d+(?:\.\d+)?\z/)
          px(value, size, size) || size * 1.2
        end

        def font_px(style)
          px(style["font-size"], 16, 16) || 16.0
        end

        def px(value, basis, font_size)
          return if value.nil? || value.to_s.empty?
          raw = value.to_s.strip.downcase
          return 0.0 if raw == "0" || raw.match?(/\A0(?:px|rem|em|%)\z/)
          return raw.to_f if raw.match?(/\A-?\d+(?:\.\d+)?px\z/)
          return raw.to_f * 16 if raw.match?(/\A-?\d+(?:\.\d+)?rem\z/)
          return raw.to_f * font_size if raw.match?(/\A-?\d+(?:\.\d+)?em\z/)
          return basis * raw.to_f / 100 if raw.match?(/\A-?\d+(?:\.\d+)?%\z/)
          return @viewport["width"] * raw.to_f / 100 if raw.match?(/\A-?\d+(?:\.\d+)?vw\z/)
          return @viewport["height"] * raw.to_f / 100 if raw.match?(/\A-?\d+(?:\.\d+)?vh\z/)
          nil
        end

        def inline_element?(node)
          %w[a abbr b em i label small span strong sub sup u img].include?(node.tag) ||
            !BLOCK_TAGS.include?(node.tag)
        end

        def box(x, y, width, height, confidence)
          { "x" => x.round(3), "y" => y.round(3), "width" => width.round(3), "height" => height.round(3), "confidence" => confidence }
        end

        def find_roles
          result = {}
          @nodes.each do |node|
            classes = node.attributes.fetch("class", "").split
            data = node.attributes["data-visual-role"].to_s.downcase
            patterns = {
              "headline" => /(?:^|[-_\s])(?:ad-organ-)?(?:headline|heading|title)(?:$|[-_\s])/i,
              "logo" => /(?:^|[-_\s])(?:ad-organ-)?logo(?:$|[-_\s])/i,
              "cta" => /(?:^|[-_\s])(?:ad-organ-)?(?:cta|call-to-action|action-button)(?:$|[-_\s])/i,
              "disclosure" => /(?:^|[-_\s])(?:ad-organ-)?disclosure(?:$|[-_\s])/i,
            }
            patterns.each { |role, regex| result[role] ||= node if data == role || classes.any? { |klass| klass.match?(regex) } }
          end
          result
        end

        def make_safe_zone(bounds, roles)
          inset = @contract.dig("placement", "safe_insets") || {}
          left, right = inset.fetch("left", 0).to_f, inset.fetch("right", 0).to_f
          top, bottom = inset.fetch("top", 0).to_f, inset.fetch("bottom", 0).to_f
          confidence = %w[headline logo cta].all? { |role| roles[role]&.geometry_confidence == "high" && bounds[role] } ? "high" : "estimated"
          {
            "rect" => { "x" => left, "y" => top, "width" => @viewport["width"] - left - right, "height" => @viewport["height"] - top - bottom },
            "bounds" => bounds.slice("headline", "logo", "cta"),
            "geometry_confidence" => confidence,
          }
        end

        def contrast_pairs(roles)
          nodes = (@nodes.select { |node| !%w[style script head title meta link].include?(node.tag) && (!text_content(node).empty? || node.tag == "img") } + roles.values).uniq
          nodes.flat_map do |node|
            %w[light dark].map do |mode|
              style = computed_style(node, mode)
              fg = resolve_color(style["color"] || "var(--ad-organ-on-surface)", mode)
              bg = find_background(node, mode)
              {
                "mode" => mode, "element" => node.attributes["data-visual-role"] || node.attributes["class"].to_s.split.first || node.tag,
                "ratio" => fg && bg ? contrast_ratio(fg, bg) : nil,
                "minimum" => 4.5, "basis" => "browserless_css_cascade_estimate"
              }
            end
          end
        end

        def disclosure_evidence(roles)
          node = roles["disclosure"]
          return {} unless node && @boxes[node.object_id]
          style = computed_style(node, "light")
          fg = resolve_color(style["color"] || "var(--ad-organ-disclosure-foreground)", "light")
          bg = find_background(node, "light")
          others = %w[headline logo cta].filter_map { |role| @boxes[roles[role].object_id] if roles[role] }
          {
            "distance_px" => (others.map { |other| rect_distance(@boxes[node.object_id], other) }.min unless others.empty?),
            "contrast_ratio" => (contrast_ratio(fg, bg) if fg && bg),
            "font_size_px" => font_px(style).round(3),
            "measurement_mode" => "browserless_static",
            "confidence" => node.geometry_confidence,
          }
        end

        def computed_style(node, mode)
          chain, current = [], node
          while current && current.tag != "#document"
            chain.unshift(current)
            current = current.parent
          end
          result = {}
          chain.each { |item| result = styles(item, result, mode:) }
          result
        end

        def find_background(node, mode)
          current = node
          while current && current.tag != "#document"
            style = computed_style(current, mode)
            colour = resolve_color(style["background-color"] || style["background"], mode)
            return colour if colour
            current = current.parent
          end
          resolve_color("var(--ad-organ-surface)", mode)
        end

        def resolve_color(value, mode)
          return if value.to_s.empty?
          text = value.to_s.strip
          match = text.match(/\Avar\(\s*--([\w-]+)\s*\)\z/i)
          if match
            prefix = "#{@contract.fetch('token_prefix', 'ad-organ')}-"
            name = match[1].downcase
            return unless name.start_with?(prefix)
            colour = @contract.fetch("colors", {})[name.delete_prefix(prefix).tr("-", "_")]
            return colour && colour[mode]
          end
          hex = text.match(/\A#([0-9a-f]{3}|[0-9a-f]{6})\z/i)
          if hex
            digits = hex[1]
            digits = digits.chars.map { |char| char * 2 }.join if digits.length == 3
            return "##{digits.upcase}"
          end
          rgb = text.match(/\Argb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)\z/i)
          return format("#%02X%02X%02X", *rgb.captures.map(&:to_i)) if rgb && rgb.captures.all? { |v| v.to_i <= 255 }
          nil
        end

        def contrast_ratio(foreground, background)
          light, dark = [luminance(foreground), luminance(background)].sort.reverse
          (light + 0.05) / (dark + 0.05)
        end

        def luminance(hex)
          channels = hex.delete_prefix("#").scan(/../).map { |part| part.to_i(16) / 255.0 }
          channels.map! { |v| v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }
          channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        end

        def rect_distance(a, b)
          dx = [a["x"] - b["x"] - b["width"], b["x"] - a["x"] - a["width"], 0].max
          dy = [a["y"] - b["y"] - b["height"], b["y"] - a["y"] - a["height"], 0].max
          Math.sqrt(dx * dx + dy * dy).round(3)
        end

        def measure_text_fit(roles)
          %w[headline cta disclosure].filter_map do |role|
            node = roles[role]
            next unless node && @boxes[node.object_id]
            bounds = @boxes[node.object_id]
            style = computed_style(node, "light")
            size = font_px(style)
            text = text_content(node)
            measured_width = text_width(text, size, style["font-weight"])
            line_height = line_px(style, size)
            nowrap = style["white-space"] == "nowrap"
            horizontal = nowrap && measured_width > bounds["width"]
            lines = nowrap ? 1 : [1, (measured_width / [bounds["width"], 1].max).ceil].max
            measured_height = line_height * lines
            vertical = measured_height > bounds["height"]
            # Heuristic glyph widths need 20% vertical headroom.
            guarded_vertical = measured_height * 1.2 > bounds["height"]
            guarded_vertical = measured_height * 1.2 > bounds["height"]
            {
              "role" => role,
              "measured_text_width_px" => measured_width,
              "available_width_px" => bounds["width"],
              "estimated_line_height_px" => measured_height.round(3),
              "available_height_px" => bounds["height"],
              "horizontal_overflow" => horizontal,
              "vertical_overflow" => vertical,
              "confidence" => "heuristic_glyph_metrics",
              "pass" => !horizontal && !guarded_vertical && !text.empty?,
            }
          end
        end

        def layout_collisions(roles)
          names = %w[headline logo cta disclosure]
          names.combination(2).filter_map do |first, second|
            a_node, b_node = roles[first], roles[second]
            next unless a_node && b_node
            a, b = @boxes[a_node.object_id], @boxes[b_node.object_id]
            next unless a && b
            left = [a["x"], b["x"]].max
            right = [a["x"] + a["width"], b["x"] + b["width"]].min
            top = [a["y"], b["y"]].max
            bottom = [a["y"] + a["height"], b["y"] + b["height"]].min
            next unless left < right && top < bottom
            { "first" => first, "second" => second, "overlap_area" => ((right - left) * (bottom - top)).round(3) }
          end
        end

        def stability_evidence(roles, text_fit, collisions)
          images = @nodes.select { |node| node.tag == "img" }
          reserved = images.all? do |node|
            style = computed_style(node, "light")
            (numeric_attr(node, "width") || px(style["width"], @viewport["width"], font_px(style))) &&
              (numeric_attr(node, "height") || px(style["height"], @viewport["height"], font_px(style)))
          end
          async_fonts = @analysis_css.match?(/@font-face|font-display\s*:\s*swap|url\([^)]*\.(?:woff2?|ttf|otf)/i)
          layout_motion = @analysis_css.match?(/(?:animation(?:-name)?|transition(?:-property)?)\s*:[^;}]*(?:all|width|height|top|left|right|bottom|margin|padding|flex|grid)/i)
          {
            "basis" => "browserless_structural_proxy_not_measured_cls",
            "reserved_geometry" => !!reserved,
            "no_async_font_swap" => !async_fonts,
            "no_layout_animations" => !layout_motion,
            "unsupported_features" => @unsupported.uniq,
            "pass" => !!reserved && !async_fonts && !layout_motion && @unsupported.empty? &&
              text_fit.all? { |item| item["pass"] } && collisions.empty? &&
              %w[headline logo cta].all? { |role| roles[role]&.geometry_confidence == "high" },
          }
        end

        def measure_assets
          refs = []
          @nodes.each do |node|
            refs << [node.attributes["src"], "html:#{node.tag}"] if %w[img source video audio].include?(node.tag) && node.attributes["src"]
            refs << [node.attributes["poster"], "html:poster"] if node.attributes["poster"]
          end
          refs.concat(css_urls(@analysis_css).map { |url| [url, "css"] })
          refs.uniq.each do |reference, origin|
            next if reference.to_s.empty?
            asset = inspect_asset(reference, origin)
            @assets << asset
            @asset_bytes += asset["bytes"].to_i if asset["loaded"] && !asset["embedded"]
            @unsupported << "asset #{reference} is not inspectable without network access" unless asset["loaded"]
          end
        end

        def css_urls(value)
          value.to_s.scan(/url\(\s*(['"]?)(.*?)\1\s*\)/i).map { |item| item[1].strip }.reject(&:empty?)
        end

        def inspect_asset(reference, origin)
          value = reference.to_s.strip
          if value.start_with?("data:")
            header, payload = value.split(",", 2)
            bytes = header.include?(";base64") ? Base64.decode64(payload.to_s) : URI.decode_www_form_component(payload.to_s)
            dims = image_dimensions(bytes, header)
            return { "reference" => value[0, 72], "origin" => origin, "loaded" => !dims.nil?, "embedded" => true, "bytes" => bytes.bytesize, "dimensions" => dims }
          end
          uri = URI.parse(value)
          return { "reference" => value, "origin" => origin, "loaded" => false, "embedded" => false, "bytes" => nil } if uri.scheme || value.start_with?("//")
          path = URI.decode_www_form_component(uri.path).delete_prefix("/")
          return { "reference" => value, "origin" => origin, "loaded" => false, "embedded" => false, "bytes" => nil } if path.empty?
          root = File.realpath(@asset_root)
          file = File.realpath(File.join(root, path))
          return { "reference" => value, "origin" => origin, "loaded" => false, "embedded" => false, "bytes" => nil } unless file.start_with?(root + File::SEPARATOR) && File.file?(file)
          bytes = File.binread(file)
          dims = image_dimensions(bytes, file)
          { "reference" => value, "origin" => origin, "loaded" => true, "embedded" => false, "bytes" => bytes.bytesize, "dimensions" => dims }
        rescue URI::InvalidURIError, SystemCallError, ArgumentError
          { "reference" => value, "origin" => origin, "loaded" => false, "embedded" => false, "bytes" => nil }
        end

        def image_dims(node)
          asset = @assets.find { |item| item["reference"] == node.attributes["src"] }
          asset && asset["dimensions"]
        end

        def image_dimensions(bytes, hint = nil)
          return if bytes.nil? || bytes.empty?
          if bytes.start_with?("\x89PNG\r\n\x1A\n".b) && bytes.bytesize >= 24
            return [bytes.byteslice(16, 4).unpack1("N"), bytes.byteslice(20, 4).unpack1("N")]
          end
          if bytes.start_with?("GIF87a", "GIF89a") && bytes.bytesize >= 10
            return bytes.byteslice(6, 4).unpack("v2")
          end
          if bytes.start_with?("\xFF\xD8".b)
            index = 2
            while index + 9 < bytes.bytesize
              index += 1 while index < bytes.bytesize && bytes.getbyte(index) != 0xFF
              index += 1 while index < bytes.bytesize && bytes.getbyte(index) == 0xFF
              marker = bytes.getbyte(index)
              index += 1
              next if [0xD8, 0xD9, 0x01].include?(marker) || (0xD0..0xD7).cover?(marker)
              break if index + 1 >= bytes.bytesize
              length = bytes.byteslice(index, 2).unpack1("n")
              break if length < 2 || index + length > bytes.bytesize
              if [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].include?(marker)
                return [bytes.byteslice(index + 5, 2).unpack1("n"), bytes.byteslice(index + 3, 2).unpack1("n")]
              end
              index += length
            end
          end
          if bytes.start_with?("RIFF".b) && bytes.bytesize >= 30 && bytes.byteslice(8, 4) == "WEBP" && bytes.byteslice(12, 4) == "VP8X"
            return [1 + bytes.byteslice(24, 3).bytes.each_with_index.sum { |byte, i| byte << (8 * i) },
                    1 + bytes.byteslice(27, 3).bytes.each_with_index.sum { |byte, i| byte << (8 * i) }]
          end
          text = bytes.dup.force_encoding("UTF-8")
          if text.valid_encoding? && (text.lstrip.start_with?("<svg") || hint.to_s.end_with?(".svg") || hint.to_s.include?("image/svg+xml"))
            width = text[/\bwidth\s*=\s*["']([\d.]+)(?:px)?["']/i, 1]
            height = text[/\bheight\s*=\s*["']([\d.]+)(?:px)?["']/i, 1]
            viewbox = text[/\bviewBox\s*=\s*["']\s*[\d.-]+\s+[\d.-]+\s+([\d.]+)\s+([\d.]+)\s*["']/i]
            dimensions = viewbox && viewbox.scan(/[\d.]+/).last(2)
            return [width.to_f, height.to_f] if width && height && width.to_f.positive? && height.to_f.positive?
            return dimensions.map(&:to_f) if dimensions
          end
          nil
        end

        def numeric_attr(node, key)
          value = node.attributes[key]
          Float(value) if value && value.match?(/\A\d+(?:\.\d+)?\z/)
        rescue ArgumentError
          nil
        end

        def descendants(node)
          node.children.flat_map { |child| child.is_a?(Node) ? [child] + descendants(child) : [] }
        end
      end
    end
  end
end
