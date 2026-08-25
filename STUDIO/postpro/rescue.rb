# frozen_string_literal: true

require "vips"
require_relative "uncanny"

# What is wrong with this photograph, and which half of it a grade can fix.
#
# The ask was "make any bad photo look good", with "although I realize that's a
# stretch" attached — and the stretch is the interesting part, because it is not
# uniformly a stretch. STUDIO/PHOTOGRAPHY.md splits a photograph into four
# layers that fail independently:
#
#   geometry     perspective distortion from shooting too close. A projection,
#                not a rendering. NOT FIXABLE, at any effort.
#   light        the pattern the key made. Gradeable as tonality; a grade
#                cannot move a shadow to the other side of a nose. PARTLY.
#   expression   the moment. NOT FIXABLE.
#   optical      plastic skin, digital cleanliness, clipped highlights, colour
#                cast. THIS IS WHAT A GRADE IS FOR.
#
# So a rescue tool that quietly tries everything and reports success is lying
# about three of the four. This one names what it fixed, and — the part that
# makes it worth having — names what it cannot, so the answer can be "reshoot at
# three metres" rather than a grade that was never going to work.
module Postpro
  module Rescue
    # Below this the picture has no micro-detail: a phone's noise reduction, a
    # beauty filter, or a diffusion model. All three produce the same reading
    # and all three are fixed the same way.
    SMOOTH_FLOOR = 0.004
    # Above this, highlights are gone rather than compressed. A grade cannot
    # recover what was never recorded, and saying so is the whole point.
    BLOWN_CEILING = 1.0
    # Below this the picture has no separation at all — flat, underexposed, or
    # shot through haze.
    FLAT_CEILING = 0.06
    # Channel means further apart than this is a cast rather than a colour.
    CAST_SPREAD = 12.0

    Finding = Struct.new(:code, :severity, :message, :remedy, keyword_init: true)

    def self.diagnose(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      reading = Uncanny.read(path)
      findings = []

      if reading.clipping > BLOWN_CEILING
        findings << Finding.new(
          code: :blown, severity: :unfixable,
          message: format("%.1f%% of the frame is clipped white", reading.clipping),
          remedy: "nothing here can recover detail that was never recorded — " \
                  "the grade can only stop it looking deliberate"
        )
      end

      if reading.texture < SMOOTH_FLOOR
        findings << Finding.new(
          code: :plastic, severity: :fixable,
          message: format("almost no micro-texture (%.4f) — phone noise reduction, a beauty " \
                          "filter, or a generated image", reading.texture),
          remedy: "grain puts the texture back; this is the single highest-yield rescue there is"
        )
      end

      if reading.tonal_range < FLAT_CEILING
        findings << Finding.new(
          code: :flat, severity: :fixable,
          message: format("very little tonal separation (%.4f) — flat, underexposed, or hazy",
                          reading.tonal_range),
          remedy: "a film curve puts contrast back where the capture had none"
        )
      end

      if (cast = colour_cast(image))
        findings << Finding.new(
          code: :cast, severity: :fixable,
          message: format("channel means %s are %.1f apart — a colour cast rather than a colour",
                          cast[:means].map { |m| m.round(1) }.inspect, cast[:spread]),
          remedy: "spectral_temp neutralises it"
        )
      end

      findings
    end

    # Mixed lighting and wrong white balance both show as the channel means
    # pulling apart. A genuinely coloured subject does it too, which is why this
    # reports rather than corrects on its own.
    def self.colour_cast(image)
      return nil if image.bands < 3

      means = image.bandsplit.first(3).map(&:avg)
      spread = means.max - means.min
      spread > CAST_SPREAD ? { means: means, spread: spread } : nil
    end

    # The layers a grade cannot reach, said every time rather than only when
    # something is detected — because their absence from a report reads as their
    # absence from the photograph, and neither is measurable here.
    OUT_OF_REACH = [
      "geometry — if this was shot at arm's length the nose is enlarged and the ears " \
      "have fallen away. That is a projection, not a rendering: reshoot at 2-3 metres.",
      "focus and motion blur — no amount of sharpening invents detail the lens did not resolve.",
      "expression and the moment — the layer that decides whether anyone cares, and the " \
      "one nothing downstream touches."
    ].freeze

    # Which preset best answers what was found. Named rather than invented: the
    # rescue applies an existing grade, so a rescued photograph and a graded one
    # are the same look.
    def self.preset_for(findings)
      codes = findings.map(&:code)
      return "quality_uplift" if codes.include?(:flat) && codes.include?(:plastic)
      return "portrait" if codes.include?(:plastic)
      return "reportage" if codes.include?(:flat)
      return "portrait" if codes.include?(:cast)

      nil
    end

    def self.report(findings)
      lines = []
      if findings.empty?
        lines << "rescue: nothing measurable is wrong with the optical layer"
      else
        findings.each do |finding|
          tag = finding.severity == :unfixable ? "CANNOT FIX" : "fixable"
          lines << "rescue: [#{tag}] #{finding.message}"
          lines << "rescue:            #{finding.remedy}"
        end
      end
      lines << "rescue: and beyond any grade —"
      OUT_OF_REACH.each { |item| lines << "rescue:   #{item}" }
      lines
    end
  end
end
