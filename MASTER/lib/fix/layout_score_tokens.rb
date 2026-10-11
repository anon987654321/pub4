# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # The design tokens a layout is measured against, read from the files that
    # declare them and never restated: scale.space_px / radius_px in
    # RAILS/__shared/design_tokens.yml, and the --space-*, --text-*, --radius-*
    # and --sp custom properties in the shared stylesheets. Every entry carries
    # its pixel value and, when a custom property declares it, that name.
    class LayoutScoreTokens
      TOKENS_YML = "RAILS/__shared/design_tokens.yml"
      STYLES = "RAILS/__shared/app/assets/stylesheets"
      REM_PX = 16.0
      DECL = /^\s*(--(space|text|radius)-[a-z0-9-]+)\s*:\s*([0-9.]+)(rem|px)\s*;/.freeze
      SP = /^\s*--sp\s*:\s*([0-9.]+)px\s*;/.freeze
      DEFAULT_RATIO = 1.25

      Token = Data.define(:px, :name)

      attr_reader :space, :radius, :font

      def self.load(root)
        new(root)
      end

      def initialize(root)
        yml = YAML.safe_load_file(File.join(root, TOKENS_YML), aliases: true) || {}
        scale = yml["scale"] || {}
        @space = literals(scale["space_px"])
        @radius = literals(scale["radius_px"])
        @font = []
        @base = nil
        Dir[File.join(root, STYLES, "{_tokens,_dialect_tokens}.scss")].sort.each { |path| declared(path) }
        chrome = (yml["shared_chrome"] || {}).select { |k, _| k.start_with?("font_size_") }
        @ratio = chrome["font_size_title"].to_f / chrome["font_size_body"].to_f if chrome.key?("font_size_title") && chrome.key?("font_size_body")
        chrome.each_value { |v| @font << Token.new(rem_px(v), nil) if v.to_s.match?(/\A[0-9.]+rem\z/) }
        [@space, @radius, @font].each { |list| list.sort_by!(&:px) }
      rescue Errno::ENOENT, Psych::Exception
        @space = []
        @radius = []
        @font = []
      end

      def space_px = @space.map(&:px).uniq

      # The rhythm unit: the declared --sp, else the largest step that divides
      # every scale value of 8px and above.
      def base_unit
        @base ||= begin
          steps = space_px.select { |v| v >= 8 }
          [8, 4].find { |unit| steps.all? { |v| (v % unit).zero? } } || 8
        end
      end

      # Modular-scale ratio: the declared title step over the body step
      # (shared_chrome font_size_title / font_size_body), else a major third.
      def type_ratio
        @ratio || DEFAULT_RATIO
      end

      def declared_size?(px) = @font.any? { |t| (t.px - px).abs <= 1.0 }

      def nearest(list, px)
        list.min_by { |t| [(t.px - px).abs, t.name ? 0 : 1] }
      end

      private

      def literals(values) = Array(values).select { |v| v.is_a?(Numeric) }.map { |v| Token.new(v.to_f, nil) }

      def rem_px(text) = text.to_s.to_f * REM_PX

      def declared(path)
        File.foreach(path, encoding: "UTF-8") do |line|
          if (m = line.match(DECL))
            px = m[4] == "rem" ? m[3].to_f * REM_PX : m[3].to_f
            bucket(m[2]) << Token.new(px, m[1])
          elsif (m = line.match(SP))
            @base = m[1].to_i
          end
        end
      end

      def bucket(kind) = { "space" => @space, "radius" => @radius, "text" => @font }.fetch(kind)
    end
  end
end
