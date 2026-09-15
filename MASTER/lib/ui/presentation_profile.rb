# frozen_string_literal: true

module Master
  module UI
    # PresentationProfile defines the capabilities and constraints of the output medium.
    class PresentationProfile
      attr_reader :medium, :color, :unicode, :hyperlinks, :motion, :audio, :width, :height

      def initialize(medium: :terminal, color: :ansi_256, unicode: true, hyperlinks: true, motion: true, audio: false, width: 120, height: 40)
        @medium = medium
        @color = color
        @unicode = unicode
        @hyperlinks = hyperlinks
        @motion = motion
        @audio = audio
        @width = width
        @height = height
      end

      def terminal? = @medium == :terminal
      def web? = @medium == :web
      def speech? = @medium == :speech
    end
  end
end
