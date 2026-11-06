# frozen_string_literal: true

module Master
  module Visual
    # The layout-refinement evidence contract behind
    # VISUAL_LAYOUT_REFINEMENT_EVIDENCE. A refinement record claims a rendered
    # layout was compared against the owning Laws and repaired; this detector
    # verifies the record carries that measurement: a distinct before/after
    # screenshot pair that exists on disk, the viewport the pair was captured
    # at, and the Law citations naming what each edit repairs. Visual facts
    # come from the capturer; missing evidence is a named refusal, never an
    # invented pass.
    module LayoutRefinement
      module_function

      REQUIRED_FIELDS = %w[laws before after viewport].freeze
      VIEWPORT_SHAPE = /\A\s*\d{2,5}\s*[xX×]\s*\d{2,5}\s*(?:\z|,)/

      def evidence(record:)
        record = normalise(record)
        reasons = []
        if record.nil?
          reasons << "refinement record is missing entirely"
        else
          REQUIRED_FIELDS.each do |field|
            reasons << "refinement record is missing #{field}" if record[field].to_s.strip.empty?
          end
          law_refs = record["laws"].to_s.split(/\s*,\s*/).reject(&:empty?)
          reasons << "refinement record cites no Law for the repairs it claims" if law_refs.empty?
          reasons.concat(screenshot_reasons(record))
          reasons.concat(viewport_reasons(record))
        end
        result("VISUAL_LAYOUT_REFINEMENT_EVIDENCE", reasons)
      end

      def screenshot_reasons(record)
        before = record["before"].to_s.strip
        after = record["after"].to_s.strip
        reasons = []
        return reasons if before.empty? || after.empty?

        reasons << "before and after point at the same screenshot" if before == after
        %w[before after].each_with_object(reasons) do |field, out|
          path = record[field].to_s.strip
          out << "#{field} screenshot is not present at #{path}" unless File.file?(path)
        end
        reasons
      end

      def viewport_reasons(record)
        reasons = []
        viewport = record["viewport"].to_s.strip
        return reasons if viewport.empty?

        reasons << "viewport must declare width and height, like 1280x900" unless viewport.match?(VIEWPORT_SHAPE)
        reasons
      end

      def normalise(record)
        return nil unless record.is_a?(Hash)

        record.each_with_object({}) do |(key, value), out|
          out[key.to_s.downcase] = value
        end
      end

      def result(law, reasons)
        { law:, pass: reasons.empty?, reasons: reasons.freeze }
      end
    end
  end
end
