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

          public_send(method, records).then do |issues, measured, unknown|
            Result.new(issues:, measured:, unknown:)
          end
        end

        private

        def probe_form_control_names(records)
          controls = []
          unknown = []
          records.each do |record|
            record.content.to_enum(:scan, /<(input|select|textarea)\b[^>]*>/im).each do
              match = Regexp.last_match
              tag = match[0]
              attrs = attributes(tag)
              type = attrs["type"].to_s.downcase
              next if type == "hidden"
              next if %w[submit reset button].include?(type)
              next if type == "image" && !attrs["alt"].to_s.strip.empty?

              controls << [record, tag, match.begin(0), attrs]
            end
            unknown << record if record.content.match?(/\b(?:form_with|form_for|fields_for|text_field|email_field|password_field|search_field|select_tag|label_tag)\b/) ||
              %w[.haml .slim].include?(File.extname(record.path).downcase)
          end

          issues = controls.filter_map do |record, tag, offset, attrs|
            next if named_control?(attrs, record.content, offset)

            issue(record, offset, "Form control has no inspectable label or accessible name: #{tag[0, 100]}")
          end
          [issues, controls.size, unknown.uniq]
        end

        def probe_image_alternatives(records)
          images = []
          unknown = []
          records.each do |record|
            record.content.to_enum(:scan, /<img\b[^>]*>/im).each do
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
            next if attrs.key?("alt")
            next if %w[presentation none].include?(attrs["role"]) || attrs["aria-hidden"] == "true"

            issue(record, offset, "Image has no non-empty alternative text or decorative marker: #{tag[0, 100]}")
          end
          [issues, images.size, unknown.uniq]
        end

        def probe_interactive_names(records)
          elements = []
          unknown = []
          records.each do |record|
            record.content.to_enum(:scan, /<(button|a)\b([^>]*)>(.*?)<\/\1\s*>/im).each do
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
            next if named?(attrs) || text_name?(inner) || image_name?(inner)

            if inner.include?("<%")
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
            # Native links and buttons are the baseline. Their accessible names
            # and rendered keyboard behaviour are evaluated by separate checks.
            measured += record.content.scan(/<button\b[^>]*>/im).size
            measured += record.content.scan(/<a\b(?=[^>]*\bhref\s*=)[^>]*>/im).size

            record.content.to_enum(:scan, /<(div|span)\b[^>]*(?:onclick\s*=)[^>]*>/im).each do
              match = Regexp.last_match
              attrs = attributes(match[0])
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
          layouts = records.select { |record| record.relative.match?(%r{/app/views/layouts/}) }
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
            tags = record.content.to_enum(:scan, /<meta\b[^>]*>/im).filter_map do
              tag = Regexp.last_match[0]
              attrs = attributes(tag)
              [tag, attrs] if attrs["name"].to_s.casecmp?("viewport")
            end
            valid = tags.any? do |_tag, attrs|
              attrs["content"].to_s.match?(/(?:\A|,)\s*width\s*=\s*device-width(?:\s*,|\z)/i)
            end
            next if valid

            message = if tags.empty?
                        "Application layout declares no viewport meta element."
                      else
                        "Viewport meta element does not declare width=device-width."
                      end
            offset = if tags.empty?
                       0
                     else
                       record.content.index(/<meta\b[^>]*>/im) || 0
                     end
            issues << issue(record, offset, message)
          end
          [issues, measured, unknown.uniq]
        end

        def named_control?(attrs, content, offset)
          return true if named?(attrs)

          id = attrs["id"].to_s
          return false if id.empty?

          escaped = Regexp.escape(id)
          return true if content.match?(%r{<label\b[^>]*\bfor\s*=\s*["']#{escaped}["'][^>]*>}i)

          before = content[0...offset]
          open_label = before.rindex(/<label\b[^>]*>/i)
          close_label = content.index("</label>", offset)
          open_label && close_label && open_label < offset
        end

        def named?(attrs)
          %w[aria-label aria-labelledby title].any? { |key| !attrs[key].to_s.strip.empty? }
        end

        def text_name?(inner)
          visible = inner.gsub(/<%.*?%>/m, " ").gsub(/<[^>]*>/m, " ").gsub(/&nbsp;|&#160;/i, " ").strip
          !visible.empty?
        end

        def image_name?(inner)
          inner.match?(/<img\b[^>]*\balt\s*=\s*["'][^"']+["']/im) ||
            inner.match?(/<svg\b[^>]*(?:aria-label|role\s*=\s*["']img["'])/im)
        end

        def attributes(tag)
          tag.scan(/([a-zA-Z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/).each_with_object({}) do |match, out|
            out[match[0].downcase] = (match[1] || match[2] || match[3]).to_s
          end
        end

        def issue(record, offset, message)
          line = record.content[0...offset].count("\n") + 1
          { record:, offset:, line:, message: }
        end
      end
    end
  end
end
