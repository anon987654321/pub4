# frozen_string_literal: true

require "vips"

# Four numbers that say whether a picture looks rendered.
#
# PHOTOGRAPHY.md §4 states the failure and STUDIO/AMBITION.md §F 96-98 asks for
# this: generated skin is too clean and its specular response uniform, because
# diffusion models learn from retouched photography and carry no account of
# subsurface scattering. Everything written about fixing that — the grain, the
# halation, the H&D shoulder, the whole of §G — is an assertion until something
# measures it.
#
# Deliberately whole-image and deliberately without face detection. A metric
# that needs a face model is a metric that fails on half the inputs and brings a
# second dependency to disagree with; these four work on any image and move in
# the right direction for the right reasons. They are proxies and are named as
# proxies.
#
# The number to watch is not any single score. It is the DELTA across postpro:
# if the grade is doing what §4 claims, texture rises and clipping falls, and if
# it is not, that shows up here rather than in an argument.
module Postpro
  module Uncanny
    Reading = Struct.new(:texture, :specular_spread, :clipping, :tonal_range, keyword_init: true) do
      def to_h = { texture:, specular_spread:, clipping:, tonal_range: }

      def to_s
        format("texture=%.4f specular_spread=%.4f clipping=%.4f%% tonal_range=%.4f",
               texture, specular_spread, clipping, tonal_range)
      end
    end

    # A 3x3 Laplacian. High-frequency energy is what pores, vellus hair and
    # grain all are, and what retouching and diffusion both remove — so this is
    # the closest single number to "how plastic is it".
    LAPLACIAN = [
      [0, -1, 0],
      [-1, 4, -1],
      [0, -1, 0]
    ].freeze

    # Above this, in a 0..1 luminance, a pixel is a highlight rather than a
    # bright midtone.
    SPECULAR_FLOOR = 0.80
    CLIPPING_FLOOR = 0.99

    def self.read(path)
      # :random, not :sequential. A sequential image may be read once,
      # top to bottom, and this reads it four times — which surfaces as
      # "vipspng: out of order read at line 64" on the second metric, after
      # the first has already returned a plausible number.
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      luma = image.bands >= 3 ? image.colourspace("b-w") : image
      luma = luma.cast(:float) / 255.0

      Reading.new(
        texture: texture_energy(luma),
        specular_spread: specular_spread(luma),
        clipping: clipping_percent(luma),
        tonal_range: luma.deviate
      )
    end

    # Mean absolute response to the Laplacian. Smooth areas return ~0; pores,
    # hair and grain return signal.
    def self.texture_energy(luma)
      mask = Vips::Image.new_from_array(LAPLACIAN)
      luma.conv(mask, precision: :float).abs.avg
    end

    # How varied the highlights are.
    #
    # Real skin is translucent and lit unevenly — an oily forehead throws a hard
    # specular while a cheek stays matte, so the bright pixels have a spread.
    # Rendered skin returns light uniformly, so its highlights cluster. Low is
    # the tell.
    #
    # Measured as the deviation WITHIN the highlight population rather than
    # across the frame, or a dark background would dominate the answer.
    def self.specular_spread(luma)
      highlights = (luma >= SPECULAR_FLOOR).ifthenelse(luma, 0)
      lit = highlights.avg
      return 0.0 if lit.zero?

      highlights.deviate
    end

    # Blown highlights, as a percentage. A real photograph rolls off; a render
    # frequently clips, and a grade cannot recover what was never there.
    def self.clipping_percent(luma)
      ((luma >= CLIPPING_FLOOR).avg / 255.0) * 100.0
    end

    # Before and after, with the direction each number should move if the grade
    # is doing what the film emulation claims.
    def self.compare(before_path, after_path)
      before = read(before_path)
      after = read(after_path)
      {
        before: before,
        after: after,
        texture_delta: after.texture - before.texture,
        clipping_delta: after.clipping - before.clipping,
        specular_delta: after.specular_spread - before.specular_spread
      }
    end

    def self.verdict(comparison)
      lines = []
      lines << if comparison[:texture_delta] > 0
                 format("texture rose %+.4f — grain put back micro-detail the model had smoothed away",
                        comparison[:texture_delta])
               else
                 format("texture fell %+.4f — the grade removed detail rather than adding it, which is " \
                        "the opposite of what film grain does", comparison[:texture_delta])
               end
      lines << if comparison[:clipping_delta] <= 0
                 format("clipping %+.4f%% — highlights roll rather than clip", comparison[:clipping_delta])
               else
                 format("clipping %+.4f%% — the grade BLEW highlights that were intact before it",
                        comparison[:clipping_delta])
               end
      lines
    end
  end
end
