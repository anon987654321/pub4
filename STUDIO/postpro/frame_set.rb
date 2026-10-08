# frozen_string_literal: true

require "vips"

# Two questions about a set of frames rather than about one.
#
# MASTER's DRY, read on a set: two frames of the same moment are one photograph
# stored twice, and a set carrying both loses a place to the repeat. And its
# CONSISTENT_ERROR_STRATEGY: a set graded frame by frame reads as a pile, because
# each frame arrives at the grade from a different exposure.
#
# Both are answered here as readings. Nothing in this file writes an image:
# moving a frame's exposure toward the set changes the graded look, and that is
# the operator's decision rather than a default.
module Postpro
  module FrameSet
    PATTERN = /\.(?:jpe?g|png|webp)\z/i

    # At or below this many differing bits out of 64, two frames are the same
    # picture. Measured on cases whose answer is known: a copy 8% brighter
    # differs by 0, a quality-60 JPEG by 3, a copy with its edges cropped and
    # scaled back by 10, and an unrelated frame by 30. Twelve sits above the
    # crop and well clear of a different picture.
    NEAR = 12

    Pair = Struct.new(:first, :second, :distance, keyword_init: true)

    def self.frames(dir)
      Dir.children(dir.to_s).grep(PATTERN).sort.map { |name| File.join(dir.to_s, name) }
    end

    # A 64-bit difference hash. The frame is reduced to 9 by 8 and each bit says
    # whether a cell is brighter than its right-hand neighbour, so the hash
    # follows the arrangement of light and ignores exposure, compression and
    # size. Float throughout: an 8-bit reduction ties neighbours, and a tie is
    # read as a match.
    def self.fingerprint(image)
      luma = (image.bands >= 3 ? image.colourspace("b-w") : image).cast(:float)
      cells = luma.resize(9.0 / luma.width, vscale: 8.0 / luma.height).to_a
      bits = cells.flat_map { |row| row.each_cons(2).map { |left, right| left.first > right.first } }
      bits.each_with_index.sum { |bright, index| bright ? 1 << index : 0 }
    end

    def self.distance(one, other) = (one ^ other).to_s(2).count("1")

    # Every pair close enough to be one photograph, nearest first.
    def self.near_duplicates(paths)
      prints = paths.to_h { |path| [path, fingerprint(load(path))] }
      pairs = paths.combination(2).map do |first, second|
        Pair.new(first:, second:, distance: distance(prints[first], prints[second]))
      end
      pairs.select { |pair| pair.distance <= NEAR }.sort_by(&:distance)
    end

    # Each frame's exposure against the set, in stops. Positive is brighter
    # than the set's median frame.
    #
    # The median of a frame's coded values is the median of its light, since the
    # sRGB curve only ever rises, so decoding the one number is enough to state
    # the gap in stops.
    def self.exposure_offsets(paths)
      medians = paths.to_h { |path| [path, linear_median(load(path))] }
      reference = medians.values.sort[medians.size / 2]
      return medians.transform_values { 0.0 } if reference.to_f <= 0

      medians.transform_values { |value| value.positive? ? Math.log2(value / reference) : -Float::INFINITY }
    end

    def self.linear_median(image)
      luma = image.bands >= 3 ? image.colourspace("b-w") : image
      coded = luma.cast(:uchar).percent(50) / 255.0
      coded <= 0.04045 ? coded / 12.92 : ((coded + 0.055) / 1.055)**2.4
    end

    def self.load(path) = Vips::Image.new_from_file(path.to_s, access: :random)
  end
end
