# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    # A spatial breadcrumb — where attention is, at what zoom, doing what.
    #
    # The vocabulary and the rendering come from data/attention_context.yml
    # rather than from constants here. They were constants, and the two
    # populations had drifted apart in both directions: the file allowed `out`,
    # `lateral` and `narrow_to_wide` zooms this class rejected, and this class
    # allowed `repair`, `checkpoint` and `review` acts the file does not name.
    # A protocol file whose only reader was a schema test is a protocol nothing
    # obeys, which is the shape DEBT.md calls inert config.
    class AttentionContext
      DATA = File.expand_path("../../data/attention_context.yml", __dir__)

      class << self
        def protocol = @protocol ||= YAML.safe_load_file(DATA, aliases: true) || {}

        def valid_zooms = @valid_zooms ||= allowed("zoom")
        def valid_acts  = @valid_acts  ||= allowed("act")
        def default_zoom = valid_zooms.first || "wide"
        def default_act  = valid_acts.first  || "scout"

        # `complex_only` is the protocol's default visibility, so what counts as
        # complex is everything past the first act — scouting is the resting
        # state and does not earn a breadcrumb.
        def complex_acts = @complex_acts ||= (valid_acts - [default_act]).freeze

        def template(name) = protocol.dig("rendering", name.to_s).to_s

        def from_yaml(path)
          return new unless File.exist?(path)

          data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
          new(
            map: data["map"],
            zoom: data["zoom"],
            act: data["act"],
            target: data["target"] || [],
            parent: data["parent"] || [],
          )
        end

        private

        def allowed(field)
          Array(protocol.dig("fields", field, "allowed")).map(&:to_s).freeze
        end
      end

      attr_reader :map, :zoom, :act, :target, :parent

      def initialize(map: nil, zoom: nil, act: nil, target: [], parent: [])
        @map = map.to_s
        @zoom = self.class.valid_zooms.include?(zoom.to_s) ? zoom.to_s : self.class.default_zoom
        @act = self.class.valid_acts.include?(act.to_s) ? act.to_s : self.class.default_act
        @target = Array(target).map(&:to_s)
        @parent = Array(parent).map(&:to_s)
      end

      def complex?
        self.class.complex_acts.include?(@act)
      end

      def to_s = render("compact_text")
      def to_markdown = render("markdown_text")

      def to_h
        { map: @map, zoom: @zoom, act: @act, target: @target, parent: @parent }
      end

      private

      def render(style)
        format(self.class.template(style), map: @map, zoom: @zoom, act: @act,
                                           target: @target.inspect, parent: @parent.inspect)
      rescue KeyError, ArgumentError
        "⟦#{@map} | zoom: #{@zoom} | act: #{@act}⟧"
      end
    end
  end
end
