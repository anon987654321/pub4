# frozen_string_literal: true

require "vips"

# Four numbers that say whether a picture looks rendered.
#
# Generated skin is too clean and its specular response uniform, because
# diffusion models learn from retouched photography and carry no account of
# subsurface scattering: real skin is translucent, and light comes back from
# below it warm and uneven. That is the tell of a generated portrait, and the
# one layer of a photograph a grade can reach. Everything written about fixing
# it — the grain, the halation, the H&D shoulder — is an assertion until
# something measures it.
#
# Deliberately whole-image and deliberately without face detection. A metric
# that needs a face model is a metric that fails on half the inputs and brings a
# second dependency to disagree with; these four work on any image and move in
# the right direction for the right reasons. They are proxies and are named as
# proxies.
#
# Three more readings sit beside the four, outside Reading because the grade
# calls read_image and has no use for them: finest_octave, squint_image and
# palette. They print under --measure.
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
      [0, -1, 0],
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
      read_image(Vips::Image.new_from_file(path.to_s, access: :random))
    end

    # The same four numbers, from an image already in hand.
    #
    # read() takes a path because every caller had one. The grade does not: it
    # is holding a Vips::Image and would have to write a temporary file to ask
    # what it is looking at, which is why it never asked and why it graded a
    # photograph as though it were a render.
    def self.read_image(image)
      luma = image.bands >= 3 ? image.colourspace("b-w") : image
      luma = luma.cast(:float) / 255.0

      Reading.new(
        texture: texture_energy(luma),
        specular_spread: specular_spread(luma),
        clipping: clipping_percent(luma),
        tonal_range: luma.deviate
      )
    end

    # Where the blacks actually sit, 0..1.
    #
    # The 1st percentile rather than the minimum: one dead pixel or one JPEG
    # ringing artefact reaches 0 in almost any frame, so the minimum answers a
    # question about noise and this answers the question about the picture.
    def self.black_point(image)
      luma = image.bands >= 3 ? image.colourspace("b-w") : image
      luma.cast(:uchar).percent(1) / 255.0
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

    # The finest octave's energy against the next octave down.
    #
    # MASTER's LEVELS_OF_SCALE, read on a picture: a photograph resolves at every distance,
    # from the silhouette at a glance to the pores up close. A frame recorded at
    # its own resolution carries detail in every octave, and the finest holds
    # about twice the next, so this reads near 2. An upscaled frame holds almost
    # nothing in its finest octave — interpolation adds pixels between the
    # recorded ones without adding detail — and heavy denoise strips it, which is
    # the picture that looks right as a thumbnail and wrong at full size.
    #
    # On cases whose answer is known, native detail reads 1.85 to 2.0, a median
    # denoise 0.89 and a 2x upscale 0.49. Those cases are synthetic, and a real
    # frame with a shallow depth of field reads lower than its sharpness deserves,
    # so this is a reading for --measure rather than a rescue finding.
    #
    # Deliberately outside Reading: read_image runs inside every grade, and the
    # grade has no use for a second pyramid level.
    def self.finest_octave(image)
      luma = image.bands >= 3 ? image.colourspace("b-w") : image
      luma = luma.cast(:float) / 255.0
      coarser = texture_energy(luma.shrink(2, 2))
      return 0.0 if coarser.zero?

      texture_energy(luma) / coarser
    end

    # Whether a frame's structure survives a squint.
    #
    # MASTER's SQUINT_TEST, in its original photographic use: squint until
    # detail disappears, and if the subject no longer separates from its
    # surroundings, the composition depends on detail a viewer will not always have.
    # The squint is a gaussian blur a fortieth of the long edge wide — a face in a
    # portrait survives it as a light oval and its features do not — and the
    # reading is the share of the frame's tonal deviation still present after it.
    #
    # On cases whose answer is known, a bright disc on a dark field keeps 0.94 and a
    # field of uniform noise keeps 0.03. There is no measured line yet between a
    # strong composition and a weak one, so this is a reading and not a verdict: a
    # rule that cannot be checked is a principle, not a gate.
    SQUINT_DIVISOR = 40.0

    def self.squint_image(image)
      luma = (image.bands >= 3 ? image.colourspace("b-w") : image).cast(:float)
      whole = luma.deviate
      return 0.0 if whole.zero?

      sigma = [image.width, image.height].max / SQUINT_DIVISOR
      luma.gaussblur(sigma).deviate / whole
    end

    # Where a frame's colour sits, as shares of nine named hues and a neutral.
    #
    # A chain of radically different models is supposed to produce radically
    # different colour, and whether it did is a question about the pixels rather
    # than about the recipe. Hue is read in LCh, where the named colours do not
    # sit evenly: measured on pure sRGB, rose reads 3 degrees, red 40, orange 60,
    # yellow 103, green 136, cyan 196, azure 285, blue 306 and magenta 328. Equal
    # bins called sRGB red orange and blue magenta, so each boundary here is the
    # midpoint between two measured neighbours. A pixel under CHROMA_FLOOR has no
    # hue worth naming and counts as neutral, which is how a black-and-white frame
    # reads as all neutral rather than as noise spread across every hue.
    HUE_BOUNDARIES = [21.5, 50.0, 81.5, 118.5, 165.0, 240.5, 297.0, 318.0, 345.5].freeze
    HUE_NAMES = %w[rose red orange yellow green cyan azure blue magenta rose].freeze
    CHROMA_FLOOR = 8.0

    def self.palette(image)
      rgb = image.bands >= 3 ? image.extract_band(0, n: 3) : image.colourspace("srgb")
      lch = rgb.copy(interpretation: :srgb).colourspace("lch")
      hue = HUE_BOUNDARIES.map { |edge| (lch[2] >= edge) / 255 }.reduce(:+)
      labels = (lch[1] >= CHROMA_FLOOR).ifthenelse(hue + 1, 0).cast(:uchar)
      counts = labels.hist_find.to_a.first.map(&:first)
      total = counts.sum.to_f
      shares = { "neutral" => counts[0] / total }
      HUE_NAMES.each_with_index { |name, index| shares[name] = shares.fetch(name, 0.0) + counts[index + 1].to_f / total }
      shares
    end

    # The palette as one line, strongest first, dropping hues under 2%.
    def self.palette_line(image)
      palette(image).select { |_, share| share >= 0.02 }.sort_by { |_, share| -share }
                    .map { |name, share| format("%s=%.2f", name, share) }.join(" ")
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
