# frozen_string_literal: true

require "digest"

module Master
  module Fix
    # Deterministic source-level guards for constrained artifact edits. This
    # does not replace rendered visual or accessibility evidence.
    module ArtifactPreservation
      Result = Data.define(:status, :checks, :reason) do
        def to_h = { "status" => status, "checks" => checks, "reason" => reason }.compact
        def passed? = status == "PASS"
      end

      HTML_TOKENS = /<!--[\s\S]*?-->|<%[\s\S]*?%>|<![^>]*>|<\/?[A-Za-z][^>]*>/m
      STYLE_BLOCKS = /<style\b[^>]*>[\s\S]*?<\/style\s*>/im
      SCRIPT_BLOCKS = /<script\b[^>]*>[\s\S]*?<\/script\s*>/im
      SCRIPT_TAGS = /<script\b[^>]*>/im
      SVG_BLOCKS = /<svg\b[^>]*>[\s\S]*?<\/svg\s*>/im
      STYLE_LINKS = /<link\b[^>]*>/im
      ASSET_TAGS = /<(?:img|source|video|audio|object|embed|iframe)\b[^>]*>/im
      ASSET_REFS = /<(img|source|video|audio|object|embed|iframe)\b([^>]*)>/im

      module_function

      def verify(before:, after:, intent:, format:, protected_assets: [])
        mode = intent.to_s
        kind = format.to_s.downcase.delete_prefix(".")
        return result("INCONCLUSIVE", [], "redesign requires rendered visual and accessibility evidence") if mode == "redesign"
        unless %w[content_only content_and_structure functional_change].include?(mode)
          return result("INCONCLUSIVE", [], "unknown task intent: #{mode}")
        end

        assets = verify_assets(protected_assets)
        return assets unless assets.passed?

        case kind
        when "html", "htm", "erb"
          verify_html(before.to_s, after.to_s, mode)
        when "css", "scss"
          return result("PASS", ["stylesheet_bytes"], nil) if same_bytes?(before, after)
          status = mode == "functional_change" ? "INCONCLUSIVE" : "FAIL"
          reason = mode == "functional_change" ?
            "stylesheet changed; rendered evidence is required to prove visual identity" :
            "stylesheet changed outside the permitted content scope"
          result(status, ["stylesheet_bytes"], reason)
        else
          return result("PASS", ["unchanged_bytes"], nil) if same_bytes?(before, after)
          result("INCONCLUSIVE", [], "no preservation parser is registered for .#{kind}; add a format-specific verifier and rendered comparison")
        end
      end

      def assert!(**arguments)
        outcome = verify(**arguments)
        return outcome if outcome.passed?
        raise Violation, "#{outcome.status}: #{outcome.reason}"
      end

      def verify_html(before, after, mode)
        if mode == "content_only"
          unchanged = before.scan(HTML_TOKENS) == after.scan(HTML_TOKENS) &&
            raw_blocks(before) == raw_blocks(after)
          return result("PASS", %w[html_markup inline_style_script_svg], nil) if unchanged
          return result("FAIL", %w[html_markup inline_style_script_svg],
                        "content-only edit changed tags, attributes, comments, templates or protected inline content")
        end

        unless visual_contract(before) == visual_contract(after)
          return result("FAIL", %w[html_visual_contract], "stylesheet links, font links, inline styles or SVG assets changed")
        end
        if mode == "content_and_structure" && script_contract(before) != script_contract(after)
          return result("FAIL", %w[html_behavior_contract], "content-and-structure edit changed script tags, sources or inline behavior")
        end
        result("PASS", %w[html_visual_contract], nil)
      end

      def raw_blocks(source)
        [source.scan(STYLE_BLOCKS), source.scan(SCRIPT_BLOCKS), source.scan(SVG_BLOCKS)]
      end

      def script_blocks(source) = source.scan(SCRIPT_BLOCKS)

      def script_contract(source)
        [source.scan(SCRIPT_TAGS), script_blocks(source)]
      end

      def asset_references(source)
        source.scan(ASSET_REFS).map do |name, attributes|
          references = attributes.scan(/\b(src|srcset|poster|data)\s*=\s*(["\x27])([^"\x27]*)\2/im)
          [name.downcase, references.map { |attribute, _quote, value| [attribute.downcase, value] }]
        end
      end

      def visual_contract(source)
        links = source.scan(STYLE_LINKS).flatten.select do |tag|
          tag.match?(/\brel\s*=\s*["']?[^"']*(?:stylesheet|icon|preload|modulepreload|mask-icon)\b/i) ||
            tag.match?(/fonts\.googleapis\.com|fonts\.gstatic\.com/i)
        end
        metas = source.scan(/<meta\b[^>]*>/im).flatten.select do |tag|
          tag.match?(/\b(?:charset|name\s*=\s*["']viewport)/i)
        end
        [links, metas, source.scan(STYLE_BLOCKS), source.scan(SVG_BLOCKS),
         asset_references(source), source.scan(ASSET_TAGS).length]
      end

      def verify_assets(assets)
        Array(assets).each do |asset|
          row = asset.to_h.transform_keys(&:to_s)
          path = row.fetch("path", "unnamed asset")
          unless row.key?("before") && row.key?("after")
            return result("INCONCLUSIVE", [], "protected asset #{path} is missing before/after evidence")
          end
          unless same_bytes?(row["before"], row["after"])
            return result("FAIL", ["protected_asset"], "protected asset changed: #{path}")
          end
        end
        result("PASS", ["protected_assets"], nil)
      end

      def same_bytes?(before, after)
        Digest::SHA256.hexdigest(before.to_s.b) == Digest::SHA256.hexdigest(after.to_s.b)
      end

      def result(status, checks, reason)
        Result.new(status, checks.freeze, reason)
      end

      class Violation < StandardError; end
    end
  end
end
