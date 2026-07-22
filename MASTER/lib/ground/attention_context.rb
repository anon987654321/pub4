# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    class AttentionContext
      VALID_ZOOMS = %w[wide narrow wide_to_deep deep_to_wide deep].freeze
      VALID_ACTS = %w[scout mine repair land verify rollback checkpoint review].freeze
      COMPLEX_ACTS = %w[mine repair rollback checkpoint verify].freeze

      attr_reader :map, :zoom, :act, :target, :parent

      def initialize(map: nil, zoom: "wide", act: "scout", target: [], parent: [])
        @map = map.to_s
        @zoom = VALID_ZOOMS.include?(zoom.to_s) ? zoom.to_s : "wide"
        @act = VALID_ACTS.include?(act.to_s) ? act.to_s : "scout"
        @target = Array(target).map(&:to_s)
        @parent = Array(parent).map(&:to_s)
      end

      def complex?
        COMPLEX_ACTS.include?(@act)
      end

      def to_s
        parts = ["map: #{@map}"].tap do |p|
          p << "zoom: #{@zoom}" if @zoom != "wide"
          p << "act: #{@act}" if @act != "scout"
        end
        "⟦#{parts.join(" | ")}⟧"
      end

      def to_h
        { map: @map, zoom: @zoom, act: @act, target: @target, parent: @parent }
      end

      def self.from_yaml(path)
        return new unless File.exist?(path)
        data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
        new(
          map: data["map"],
          zoom: data["zoom"] || "wide",
          act: data["act"] || "scout",
          target: data["target"] || [],
          parent: data["parent"] || [],
        )
      end
    end
  end
end
