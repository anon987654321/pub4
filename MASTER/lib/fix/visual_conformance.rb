# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Deterministic rule conformance for rendered surfaces. A rule in
    # data/visual_directives.yml names a project_context.yml directive, a probe
    # that reads one value off a measured element, and checks that value must
    # pass. The council still judges taste; this judges what a computed style
    # can settle, so a directive the operator wrote down is never left to a
    # model's reading of a screenshot.
    module VisualConformance
      Finding = Data.define(:rule, :directive, :surface, :viewport, :selector, :text, :detail) do
        def to_s = "#{rule} #{surface}@#{viewport} #{selector}: #{detail}"
      end

      GENERIC = %w[serif sans-serif monospace cursive fantasy system-ui ui-serif ui-sans-serif ui-monospace ui-rounded -apple-system].freeze

      # Font stacks arrive as computed `font-family` text; tokens are lowercased
      # and unquoted so a rule compares names, not spelling.
      PROBES = {
        "font_family" => lambda { |element|
          computed = element["font_family"].to_s.split(",").map { |t| t.strip.delete("\"'").downcase }.reject(&:empty?)
          painted = Array(element["painted"]).map { |f| f["name"].to_s.downcase }.reject(&:empty?)
          next computed if painted.empty?

          # A named head is a request the browser may have declined, so the
          # face it painted stands in; a generic head is the OS picking, and
          # its pick is not the page's to answer for.
          head = GENERIC.include?(computed.first) ? computed.first : painted.first
          ([head] + painted.drop(1) + computed.drop(1)).uniq
        },
      }.freeze

      MONO = ["monospace", "ui-monospace", "sf mono", "menlo", "monaco", "consolas", "courier new", "courier"].freeze

      CHECKS = {
        "forbid_generic" => lambda { |tokens, args, _el, _key|
          hit = tokens & Array(args)
          "generic #{hit.join(", ")} in stack" unless hit.empty?
        },
        "forbid_named" => lambda { |tokens, args, _el, _key|
          hit = tokens & Array(args)
          "named face #{hit.join(", ")} in stack" unless hit.empty?
        },
        "head_in" => lambda { |tokens, args, _el, _key|
          head = tokens.first
          "first family #{head.inspect} is outside the house stack" if head && !Array(args).include?(head)
        },
        "monospace_only_in" => lambda { |tokens, args, _el, key|
          next unless MONO.include?(tokens.first) && !key.match?(Regexp.new(args, Regexp::IGNORECASE))

          "monospace #{tokens.first.inspect} outside code and terminal chat"
        },
      }.freeze

      module_function

      def rules
        path = File.expand_path("../../data/visual_directives.yml", __dir__)
        Array(YAML.safe_load_file(path)["rules"])
      end

      # Each captured surface against every rule whose scope matches its app.
      def check(captures)
        found = Array(captures).flat_map { |c| check_payload(c[:surface], c[:payload]) }
        summary(found, Array(captures).size)
        found
      end

      def check_payload(surface, payload)
        return [] unless payload.is_a?(Hash)

        rules.flat_map do |rule|
          next [] unless surface.id.to_s.match?(Regexp.new(rule.fetch("scope")))

          Array(payload["elements"]).flat_map { |element| violations(rule, surface, with_painted(element, payload)) }
        end.uniq { |f| [f.rule, f.selector, f.detail] }
      end

      # The painted faces for one element, and the note a finding carries when
      # the probe could not ask Chrome and the computed stack stands in.
      def with_painted(element, payload)
        status = payload["painted_fonts_status"].to_s
        note = status.start_with?("unverified") ? " [#{status}; computed stack only]" : ""
        element.merge("painted" => payload["painted_fonts"].to_h[element["key"]], "painted_note" => note)
      end

      def violations(rule, surface, element)
        return [] unless element["visible"] != false && (element["text"].to_s != "" || element["interactive"])

        tokens = PROBES.fetch(rule.fetch("probe")).call(element)
        return [] if tokens.empty?

        rule.fetch("checks").filter_map do |name, args|
          detail = CHECKS.fetch(name).call(tokens, args, element, element["key"].to_s)
          next unless detail

          Finding.new(rule["id"], rule["directive"], surface.id, surface.viewport, element["key"], element["text"].to_s[0, 40], detail + element["painted_note"].to_s)
        end
      end

      # The directive list for the critique prompt, with this pass's measured
      # violations so the council starts from settled facts.
      def context(captures)
        lines = rules.map { |r| "#{r["id"]} (#{r["directive"]}): #{directive_body(r["directive"])}" }
        found = Array(captures).flat_map { |c| check_payload(c[:surface], c[:payload]) }
        measured = found.first(20).map { |f| "- #{f}" }
        ["DIRECTIVE CONFORMANCE", "Operator directives verified against computed styles; treat a measured violation as a finding.",
         *lines, (measured.empty? ? "Measured violations: none" : "Measured violations (#{found.size}):\n#{measured.join("\n")}")].join("\n")
      end

      def directive_body(key)
        path = File.expand_path("../../data/project_context.yml", __dir__)
        entry = Array(YAML.safe_load_file(path)["entries"]).find { |e| e["key"] == key }
        entry ? entry["body"].to_s.split(/(?<=\.)\s/).first(2).join(" ") : "directive text missing"
      rescue StandardError
        "directive text unreadable"
      end

      def summary(found, surfaces)
        Master::Trace::Dmesg.status("visual0", "conformance: #{found.size} violation(s) over #{surfaces} surface(s)")
      rescue StandardError
        nil
      end
    end
  end
end
