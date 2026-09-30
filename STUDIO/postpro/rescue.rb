# frozen_string_literal: true

require "vips"
require_relative "uncanny"

# What is wrong with this photograph, and which half of it a grade can fix.
#
# The ask was "make any bad photo look good", with "although I realize that's a
# stretch" attached — and the stretch is the interesting part, because it is not
# uniformly a stretch. A photograph fails on four layers, and they fail
# independently:
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
    #
    # Raised from 12.0, which diagnosed a cast on six of nine ordinary
    # photographs of one person. Skin is not neutral: it is red over green over
    # blue by a wide margin in every light, so any frame filled by a face clears
    # a 12-point spread on its subject alone. The threshold was measuring "is
    # there a person in this picture".
    #
    # 12 was not arbitrary either — it is a reasonable number for a frame of
    # mixed content. The mistake was applying a whole-frame threshold to
    # portraits, which is what this tool is mostly pointed at.
    #
    # Set against the measured distribution of that set rather than by feel.
    # Spreads ran 2.2, 4.9, 23.8, 27.7, 27.7, 28.2, 44.0, 58.7 — a body of
    # ordinary warm indoor portraits clustered in the twenties, and a clear gap
    # above them. 34 keeps the two that are genuinely cast (one shot under
    # tungsten, one with a filter already baked in) and drops the four that were
    # only faces.
    CAST_SPREAD = 34.0
    # A frame whose middle sits below this, in coded 0..1 luminance, is dark
    # all through: 0.18 is about two and a half stops under mid-grey. It only
    # counts when the brightest two percent stay under DARK_HIGHLIGHT too,
    # because a night street with a lit window is dark by choice and its window
    # says so. On noisy frames whose answer is known, one at 30 of 255 reads 0.12
    # and 0.20, mid-grey 0.55 and 0.63, and the dark one with a lamp across 5% of
    # it 0.12 and 0.98.
    DARK_MEDIAN = 0.18
    DARK_HIGHLIGHT = 0.6

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

      if (dark = underexposure(image))
        findings << Finding.new(
          code: :underexposed, severity: :partly,
          message: format("underexposed — half the frame sits below %.2f and the brightest 2%% below %.2f",
                          dark[:median], dark[:highlight]),
          remedy: "not lifted here: raise exposure where the file was made, from raw if there is one. " \
                  "A grade can open shadows only as far as the capture recorded them, and noise rises with them"
        )
      end

      if (cast = colour_cast(image))
        findings << Finding.new(
          code: :cast, severity: :fixable,
          message: format("channel means %s are %.1f apart — a colour cast rather than a colour",
                          cast[:means].map { |m| m.round(1) }.inspect, cast[:spread]),
          remedy: "not corrected here: set white balance from something neutral in the frame. " \
                  "The portrait grade this rescue applies warms the picture; it does not neutralise a cast"
        )
      end

      findings
    end

    # The frame's median and its 98th percentile, when both say it is dark.
    def self.underexposure(image)
      luma = (image.bands >= 3 ? image.colourspace("b-w") : image).cast(:uchar)
      median = luma.percent(50) / 255.0
      highlight = luma.percent(98) / 255.0
      median < DARK_MEDIAN && highlight < DARK_HIGHLIGHT ? { median: median, highlight: highlight } : nil
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
          tag = { unfixable: "CANNOT FIX", partly: "partly" }.fetch(finding.severity, "fixable")
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
