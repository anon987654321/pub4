# frozen_string_literal: true

module Master
  module Review
    class BaymardLaw
      # Deterministic source observations only. Framework-generated UI is
      # deliberately returned as unknown until a browser can inspect the
      # rendered accessibility tree.
      class SourceAudit
        Result = Data.define(:issues, :measured, :unknown)

        def call(id, records)
          method = "probe_#{id}"
          raise BaymardLaw::InvalidProfile, "no source probe for #{id}" unless respond_to?(method, true)

          # Probes are private; the respond_to? guard above admits only probe_* ids.
          __send__(method, records).then do |issues, measured, unknown|
            Result.new(issues:, measured:, unknown:)
          end
        end

        private

        # An ERB region inside a tag breaks both tag extraction (`[^>]*>` stops at
        # the `%>`'s `>`) and attribute parsing (quotes inside the interpolation).
        # Mask every `<%...%>` span with same-length filler so offsets survive 1:1:
        # tag heads then parse real attribute names, while dynamic VALUES read as
        # present-but-unresolvable, which the rendered accessibility-tree review
        # settles. Body probes that judge visible text keep the original content.
        def erb_masked(content) = content.gsub(/<%.*?%>/m) { |span| "E" * span.length }

        # A `>` closes a tag only when it sits outside a quoted attribute value.
        # Stimulus runs on `data-action="input->auto-submit#submit"` — a naive
        # `[^>]*>` cut the tag inside that value and dropped every attribute
        # after it, so a control carrying aria-label past the arrow read as
        # unnamed. The alternation consumes quoted values wholesale instead.
        TAG_BODY = %r{(?>[^>"']|"[^"]*"|'[^']*')*}
        FORM_CONTROL_TAG = /<(input|select|textarea)\b#{TAG_BODY.source}>/im
        IMAGE_TAG = /<img\b#{TAG_BODY.source}>/im
        META_TAG = /<meta\b#{TAG_BODY.source}>/im
        INTERACTIVE_TAG = /<(button|a)\b(#{TAG_BODY.source})>(.*?)<\/\1\s*>/im
        CLICKABLE_TAG = /<(div|span)\b#{TAG_BODY.source}>/im
        LINK_TAG = /<a\b(#{TAG_BODY.source})>/im
        FORM_HELPERS = /\b(?:form_with|form_for|fields_for|text_field|email_field|password_field|search_field|select_tag|label_tag)\b/

        def probe_form_control_names(records)
          controls = []
          unknown = []
          records.each do |record|
            content = record.content
            erb_masked(content).to_enum(:scan, FORM_CONTROL_TAG).each do
              match = Regexp.last_match
              tag = match[0]
              attrs = attributes(tag)
              next if control_not_rendered_for_naming?(attrs)

              controls << [record, tag, match.begin(0), attrs]
            end
            unknown << record if content.match?(FORM_HELPERS) ||
              %w[.haml .slim].include?(File.extname(record.path).downcase)
          end

          issues = controls.filter_map do |record, tag, offset, attrs|
            state = named_control?(attrs, record.content, offset)
            if state == :unknown
              unknown << record
              next
            end
            next if state

            issue(record, offset, "Form control has no inspectable label or accessible name: #{tag[0, 100]}")
          end
          [issues, controls.size, unknown.uniq]
        end

        # Controls that never render for a reader, or that name themselves by
        # construction, carry no accessible-name failure. A hidden control's
        # labelled trigger button is what the reader meets.
        def control_not_rendered_for_naming?(attrs)
          return true if attrs.key?("hidden") || attrs["aria-hidden"].to_s.casecmp?("true")

          type = attrs["type"].to_s.downcase
          return true if type == "hidden" || %w[submit reset].include?(type)

          type == "button" && !attrs["value"].to_s.strip.empty?
        end

        def probe_image_alternatives(records)
          images = []
          unknown = []
          records.each do |record|
            erb_masked(record.content).to_enum(:scan, IMAGE_TAG).each do
              match = Regexp.last_match
              images << [record, match[0], match.begin(0), attributes(match[0])]
            end
            unknown << record if record.content.match?(/\bimage_tag\b/) ||
              %w[.haml .slim].include?(File.extname(record.path).downcase)
          end

          issues = images.filter_map do |record, tag, offset, attrs|
            # alt="" is the standard explicit marker for a decorative image;
            # the task-level screen-reader review is still needed to catch a
            # meaningful image incorrectly marked decorative.
            alt = attrs["alt"]
            next if attrs.key?("alt") && (alt == "" || !alt.to_s.strip.empty?)
            next if %w[presentation none].include?(attrs["role"].to_s.downcase) || attrs["aria-hidden"].to_s.casecmp?("true")

            issue(record, offset, "Image has no non-empty alternative text or decorative marker: #{tag[0, 100]}")
          end
          [issues, images.size, unknown.uniq]
        end

        def probe_interactive_names(records)
          elements = []
          unknown = []
          records.each do |record|
            record.content.to_enum(:scan, INTERACTIVE_TAG).each do
              match = Regexp.last_match
              tag_name = match[1].downcase
              attrs = attributes(match[2])
              next if tag_name == "a" && attrs["href"].to_s.empty?

              elements << [record, tag_name, match[0], match[3], match.begin(0), attrs]
            end
            unknown << record if record.content.match?(/\b(?:link_to|button_to)\b/) ||
              %w[.haml .slim].include?(File.extname(record.path).downcase)
          end

          issues = []
          elements.each do |record, tag_name, tag, inner, offset, attrs|
            name_state = named?(attrs, content: record.content)
            next if name_state == true || text_name?(inner) || image_name?(inner)

            if name_state == :unknown || inner.include?("<%")
              unknown << record
            else
              issues << issue(record, offset, "#{tag_name} has no visible or programmatic accessible name: #{tag[0, 120]}")
            end
          end
          [issues, elements.size, unknown.uniq]
        end

        def probe_native_click_targets(records)
          issues = []
          unknown = []
          measured = 0
          records.each do |record|
            masked = erb_masked(record.content)
            # Native links and buttons are the baseline. Their accessible names
            # and rendered keyboard behaviour are evaluated by separate checks.
            measured += masked.scan(/<button\b#{TAG_BODY.source}>/im).size
            measured += masked.scan(LINK_TAG).count do |attr_text|
              !attributes("<a#{attr_text}>")["href"].to_s.empty?
            end

            masked.to_enum(:scan, CLICKABLE_TAG).each do
              match = Regexp.last_match
              attrs = attributes(match[0])
              next unless attrs.key?("onclick")

              measured += 1
              role = attrs["role"].to_s
              tab = Integer(attrs["tabindex"], exception: false)
              if %w[button link].include?(role) && tab && tab >= 0
                unknown << record
              else
                issues << issue(record, match.begin(0), "Clickable #{match[1].downcase} needs a link/button role and a non-negative tab stop, or should use a native interactive element.")
              end
            end
            unknown << record if %w[.haml .slim].include?(File.extname(record.path).downcase)
          end
          [issues, measured, unknown.uniq]
        end

        def probe_focus_visibility(records)
          issues = []
          unknown = []
          measured = records.size
          records.each do |record|
            matches = record.content.to_enum(:scan, /outline(?:-width|-[\w-]+)?\s*:\s*(?:none|0(?:\s|;|!))/i).map do
              Regexp.last_match.begin(0)
            end
            next if matches.empty?

            if record.content.match?(/:focus(?:-visible)?\b/i)
              unknown << record
              next
            end

            matches.each do |offset|
              issues << issue(record, offset, "Stylesheet suppresses the focus outline and contains no :focus or :focus-visible replacement.")
            end
          end
          [issues, measured, unknown]
        end

        def probe_mobile_viewport(records)
          layouts = records.select { |record| device_layout_document?(record) }
          return [[], 0, records] if layouts.empty?

          issues = []
          unknown = []
          measured = 0
          layouts.each do |record|
            if %w[.haml .slim].include?(File.extname(record.path).downcase)
              unknown << record
              next
            end

            measured += 1
            audit_viewport(record, issues, unknown)
          end
          [issues, measured, unknown.uniq]
        end

        # Mailers and underscore partials shape no device viewport; only a full
        # HTML document layout does.
        def device_layout_document?(record)
          record.relative.match?(%r{/app/views/layouts/}) &&
            !File.basename(record.path).start_with?("_") &&
            record.content.match?(%r{<\s*(?:html|head)\b}i)
        end

        def audit_viewport(record, issues, unknown)
          content = record.content
          tags = erb_masked(content).to_enum(:scan, META_TAG).filter_map do
            tag = Regexp.last_match[0]
            attrs = attributes(tag)
            [tag, attrs] if attrs["name"].to_s.casecmp?("viewport")
          end
          # A layout that renders its meta through ERB (`tag.meta name: "viewport"`)
          # has no inspectable meta element after masking. The declaration exists,
          # but only the rendered accessibility-tree review can read it.
          if tags.empty? && content.match?(%r{<%[^%]*\bviewport\b[^%]*%>}im)
            unknown << record
            return
          end
          return if tags.any? { |_tag, attrs| attrs["content"].to_s.match?(/(?:\A|,)\s*width\s*=\s*device-width(?:\s*,|\z)/i) }

          message = if tags.empty?
                      "Application layout declares no viewport meta element."
                    else
                      "Viewport meta element does not declare width=device-width."
                    end
          offset = tags.empty? ? 0 : (content.index(tags.first.first) || 0)
          issues << issue(record, offset, message)
        end

        def named_control?(attrs, content, offset)
          state = named?(attrs, content:)
          return true if state == true
          return :unknown if state == :unknown

          type = attrs["type"].to_s.downcase
          return true if type == "image" && !attrs["alt"].to_s.strip.empty?
          return true if type == "button" && !attrs["value"].to_s.strip.empty?

          id = attrs["id"].to_s
          unless id.empty?
            escaped = Regexp.escape(id)
            explicit = content.match(
              %r{<label\b(?=[^>]*\bfor\s*=\s*["']#{escaped}["'])[^>]*>(.*?)</label\s*>}im
            )
            return label_name_state(explicit[1]) if explicit
          end

          before = content[0...offset]
          last_open_match = before.match(/<label\b[^>]*>(?!.*<label\b)/im)
          return false unless last_open_match

          last_close = before.rindex(%r{</label\s*>}i)
          return false if last_close && last_close > last_open_match.begin(0)

          close_label = content.index(%r{</label\s*>}i, offset)
          return false unless close_label

          opening_end = content.index(">", last_open_match.begin(0))
          return false unless opening_end

          label_name_state(content[(opening_end + 1)...close_label])
        end

        def label_name_state(value)
          return :unknown if value.to_s.include?("<%")

          text_name?(value.to_s)
        end

        # A non-empty aria-labelledby attribute is not proof that its
        # references resolve. A missing local target is INCONCLUSIVE because
        # the label may be rendered by a shared partial; a present but empty
        # target is a source defect.
        def named?(attrs, content: nil)
          return true if %w[aria-label title].any? { |key| !attrs[key].to_s.strip.empty? }

          references = attrs["aria-labelledby"].to_s.split
          return false if references.empty?
          return :unknown unless content

          references.each do |id|
            escaped = Regexp.escape(id)
            target = content.match(
              %r{<([a-z][a-z0-9:-]*)\b(?=[^>]*\bid\s*=\s*["']#{escaped}["'])[^>]*>(.*?)</\1\s*>}im
            )
            return :unknown unless target

            target_attrs = attributes(target[0].split(">", 2).first.to_s + ">")
            labelled = %w[aria-label title].any? { |key| !target_attrs[key].to_s.strip.empty? }
            return false unless labelled || text_name?(target[2])
          end
          true
        end

        def text_name?(inner)
          visible = inner.gsub(/<%.*?%>/m, " ").gsub(/<[^>]*>/m, " ").gsub(/&nbsp;|&#160;/i, " ").strip
          !visible.empty?
        end

        def image_name?(inner)
          return true if inner.match?(/<img\b[^>]*\balt\s*=\s*["'][^"']+["']/im)

          inner.scan(%r{<svg\b([^>]*)>(.*?)</svg>}im).any? do |attributes_text, body|
            svg_attrs = attributes("<svg#{attributes_text}>")
            next false if svg_attrs["aria-hidden"].to_s.casecmp?("true")
            next false unless svg_attrs["role"].to_s.casecmp?("img") || svg_attrs.key?("aria-label")

            named?(svg_attrs, content: inner) == true || body.match?(/<title\b[^>]*>\s*\S.*?<\/title>/im)
          end
        end

        def attributes(tag)
          pairs = /([a-zA-Z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/
          out = tag.scan(pairs).each_with_object({}) do |match, out|
            out[match[0].downcase] = (match[1] || match[2] || match[3]).to_s
          end
          # Bare boolean attributes (`hidden`, `disabled`, `required`) carry no
          # `=`. Pairs scan never sees them; scan the residue outside quoted
          # values so words inside a value are not misread as keys.
          residue = tag.delete_prefix("<").gsub(/"[^"]*"|'[^']*'/, " ")
          residue.scan(/(?:\A|\s)([a-zA-Z_:][\w:.-]*)(?=[\s>\/]|\z)/).each do |(word)|
            out[word.downcase] ||= ""
          end
          out
        end

        def issue(record, offset, message)
          line = record.content[0...offset].count("\n") + 1
          { record:, offset:, line:, message: }
        end
      end
    end
  end
end
