# frozen_string_literal: true

require "digest"

module Master::Core::Design
  # SymmetrySweep — an automated auditor for visual consistency.
  #
  # It scans the RAILS frontend for CSS and HTML patterns that violate 
  # the LayoutGrammar.
  class SymmetrySweep
    attr_reader :violations

    def initialize
      @violations = []
    end

    # Scans a set of files for non-canonical spacing, radii, or typography.
    def sweep(paths)
      paths.each do |path|
        content = File.read(path)
        find_spacing_violations(content, path)
        find_radius_violations(content, path)
      end
      @violations
    end

    private

    def find_spacing_violations(content, path)
      # Look for pixel values that are not multiples of 4
      content.scan(/(\d+)px/).each do |match|
        val = match[0].to_i
        unless (val % 4).zero? || LayoutGrammar::SPACE.values.include?(val)
          @violations << { path: path, type: :spacing, value: val, message: "non-canonical spacing" }
        end
      end
    end

    def find_radius_violations(content, path)
      # Look for border-radius values not in the grammar
      content.scan(/border-radius:\s*(\d+px)/).each do |match|
        val = match[0]
        unless LayoutGrammar::RADIUS.values.include?(val)
          @violations << { path: path, type: :radius, value: val, message: "non-canonical radius" }
        end
      end
    end
  end
end
