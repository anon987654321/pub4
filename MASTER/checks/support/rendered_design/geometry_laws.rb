# frozen_string_literal: true

require_relative "../rendered_geometry/space_checks"

module Deploy
  module RenderedDesign
    # The four Laws whose rendered measurement already exists in the geometry probe
    # (geometry_probe/walk.js and geometry_type_walk.js, judged by RenderedGeometryCheck):
    # they read that payload, saved as *.geometry.json, through the same SpaceChecks the
    # rendered suite runs, so nothing is measured twice.
    module GeometryLaws
      SNAPSHOT = /\.geometry\.json\z/
      EXAMPLE = "/repo/MASTER/var/rendered/home.geometry.json"
      MONO = /mono|courier|menlo|consolas|monaco/i
      MONO_HOMES = /chat|terminal|console|code|pre|kbd|samp|messenger|irc|log/i
      SERIF = /\A(?:serif|ui-serif|georgia|times(?: new roman)?|garamond|palatino(?: linotype)?|iowan old style|
                 baskerville|playfair display|merriweather|didot|bodoni(?: 72)?|book antiqua)\z/xi
      Surface = Struct.new(:id, :width, :height, keyword_init: true)

      module Space
        extend RenderedGeometryCheck::SpaceChecks
      end

      module_function

      def surface(payload)
        Surface.new(id: payload["surface"].to_s, width: payload.fetch("width", 390),
                    height: payload.fetch("height", 844))
      end

      def leaves(payload) = Space.first_screen_leaves(surface(payload), payload["elements"])

      def wrap(payload) = Space.heading_wrap(leaves(payload))

      def grouping(payload)
        shown = leaves(payload)
        shown.empty? ? [] : Space.heading_proximity(shown) + Space.voids(surface(payload), shown)
      end

      def tabular(payload)
        Array(payload["tabular"]).reject { |row| row["numeric"].to_s.include?("tabular-nums") }
                                 .map { |row| "#{row["sel"]} sets a quantity in proportional figures" }
      end

      def family(element) = element["font_family"].to_s.split(",").first.to_s.delete("\"'").strip

      def typefaces(payload)
        payload["path"].to_s.include?("BPLANS/") ? [] : typeface_rows(leaves(payload))
      end

      # One sans for UI and text, monospace only where chat, terminal or code lives (operator 2026-10-11).
      def typeface_rows(text)
        mono, sans = text.partition { |leaf| family(leaf).match?(MONO) }
        names = sans.map { |leaf| family(leaf) }.uniq
        serif_rows(names) + family_rows(names) + mono_rows(mono)
      end

      def serif_rows(names) = names.grep(SERIF).map { |name| "serif family #{name}; the house type is one sans" }

      def family_rows(names)
        names.size > 1 ? ["#{names.size} text families (#{names.join(", ")}); one sans serves UI and text"] : []
      end

      def mono_rows(mono)
        stray = mono.reject { |leaf| leaf["key"].to_s.match?(MONO_HOMES) }
        stray.first(3).map { |leaf| "#{leaf["key"]} sets monospace outside chat, terminal or code" }
      end

      CHECKS = { "HEADING_WRAP_BALANCE" => :wrap, "NEGATIVE_SPACE_GROUPING" => :grouping,
                 "TABULAR_NUMERALS" => :tabular, "TYPEFACE_PER_ROLE" => :typefaces }.freeze

      # The Law check body over a saved geometry payload.
      def findings(id, text, path:)
        return [] unless path.to_s.match?(SNAPSHOT)

        payload = JSON.parse(text)
        return [] unless payload.is_a?(Hash) && payload["probe"] == "geometry"

        send(CHECKS.fetch(id.to_s), payload).uniq.map { |message| { line: 1, message: } }
      rescue JSON::ParserError # scan: intentional - a file that is not a payload holds no rendered finding
        []
      end

      def fixture(elements: [], **top)
        { "probe" => "geometry", "surface" => "brgen/core/mobile", "width" => 390, "height" => 844,
          "elements" => elements }.merge(top.transform_keys(&:to_s)).to_json
      end

      def leaf(key, **fields)
        { "key" => key, "tag" => key[/\A[a-z0-9]+/], "visible" => true, "text" => "Tekst", "font_size" => 16.0,
          "text_lines" => 1, "font_family" => "Helvetica Neue, Arial, sans-serif",
          "frect" => { "x" => 16, "y" => 16, "w" => 358, "h" => 24 } }.merge(fields.transform_keys(&:to_s))
      end
    end
  end
end
