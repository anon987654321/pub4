# frozen_string_literal: true

require_relative "png_diff"

module Deploy
  # pixelmatch (mapbox/pixelmatch, ISC) in Ruby, over PngDiff's decoder.
  #
  # PngDiff.compare counts any byte that moved, so a font hinted a shade
  # differently reads as change. This keeps the two ideas that make pixelmatch
  # usable on screenshots: a perceptual YIQ colour delta with a threshold, and
  # anti-aliasing detection (a pixel with few identical neighbours that sits
  # between its darkest and brightest neighbour in both images is an edge
  # resampled, not a change). It adds what a repair has to answer to: the
  # changed pixels grouped into boxes, and a 4x crop of any box.
  module PixelMatch
    THRESHOLD = 0.1
    # The squared YIQ distance between black and white.
    MAX_YIQ = 35_215.0
    CELL = 16
    ZOOM = 4

    Y_WEIGHTS = [0.29889531, 0.58662247, 0.11448223].freeze
    I_WEIGHTS = [0.59597799, -0.2741761, -0.32180189].freeze
    Q_WEIGHTS = [0.21147017, -0.52261711, 0.31114694].freeze

    # One decoded image: packed 0xRRGGBBAA integers, row-major.
    Frame = Data.define(:width, :height, :pixels) do
      def at(col, row) = pixels[row * width + col]

      def edge?(col, row) = col.zero? || row.zero? || col == width - 1 || row == height - 1

      def neighbours(col, row)
        cols = ([col - 1, 0].max..[col + 1, width - 1].min).to_a
        rows = ([row - 1, 0].max..[row + 1, height - 1].min).to_a
        rows.product(cols).map(&:reverse) - [[col, row]]
      end

      def place(pos) = pos.divmod(width).reverse

      def size = [width, height]

      def lines = pixels.each_slice(width).to_a
    end

    # The two images compared; anti-aliasing is judged in both.
    Pair = Data.define(:base, :current)

    module_function

    def read(path)
      decoded = PngDiff.decode(File.binread(path))
      Frame.new(width: decoded[:width], height: decoded[:height], pixels: unpacked_pixels(decoded))
    end

    def unpacked_pixels(decoded)
      channels = decoded[:channels]
      row_bytes = decoded[:width] * channels
      previous = Array.new(row_bytes, 0)
      rows = Array.new(decoded[:height]) do |line|
        bytes = decoded[:raw].byteslice(line * (row_bytes + 1), row_bytes + 1)
        previous = PngDiff.unfilter_row(bytes, previous:, channels:)
        words(previous, channels)
      end
      rows.flatten
    end

    def words(row, channels)
      return row.pack("C*").unpack("N*") if channels == 4

      row.each_slice(3).map { |red, green, blue| (red << 24) | (green << 16) | (blue << 8) | 255 }
    end

    def pack(rgba) = rgba.inject(0) { |word, channel| (word << 8) | channel }

    def unpack(word) = [24, 16, 8, 0].map { |shift| (word >> shift) & 255 }

    DIFF = pack([255, 0, 0, 255])
    ALIASED = pack([255, 255, 0, 255])
    MARK = { diff: DIFF, aliased: ALIASED }.freeze

    # baseline vs current: changed and anti-aliased pixel counts, the changed boxes and a diff PNG
    # (changed red, anti-aliased yellow, unchanged a faded copy of the baseline).
    def compare(baseline_path:, current_path:, diff_path: nil, threshold: THRESHOLD)
      pair = Pair.new(base: read(baseline_path), current: read(current_path))
      return mismatch(pair) unless pair.base.size == pair.current.size

      mask = scan(pair, max_delta: MAX_YIQ * threshold * threshold)
      measured(pair.base, mask).merge(pixel_diff_image: diff_image(diff_path, base: pair.base, mask:))
    end

    def measured(base, mask)
      changed = mask.count { |entry| entry[1] == :diff }
      { status: :compared, width: base.width, height: base.height, pixel_diff_count: changed,
        aliased: mask.size - changed, pixel_diff_ratio: (changed.to_f / base.pixels.size).round(8),
        regions: regions(mask, base) }
    end

    def mismatch(pair)
      { status: :dimension_mismatch, baseline_dimensions: pair.base.size, current_dimensions: pair.current.size,
        pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil, regions: [] }
    end

    # index => :diff or :aliased, for every pixel that differs past the threshold.
    def scan(pair, max_delta:)
      before = pair.base.pixels
      after = pair.current.pixels
      before.each_index.with_object({}) do |pos, mask|
        next if before[pos] == after[pos] || delta(before[pos], after[pos]).abs <= max_delta

        mask[pos] = kind(pair, pair.base.place(pos))
      end
    end

    def kind(pair, place)
      aliased = antialiased?(pair.base, pair.current, place) || antialiased?(pair.current, pair.base, place)
      aliased ? :aliased : :diff
    end

    # pixelmatch's colorDelta: signed, negative when the first pixel is the lighter one.
    def delta(first, second)
      luma_step, hue, saturation = channels(blend(first)).zip(channels(blend(second))).map { |one, two| one - two }
      value = 0.5053 * luma_step**2 + 0.299 * hue**2 + 0.1957 * saturation**2
      luma_step.positive? ? -value : value
    end

    def channels(rgb) = [yiq(rgb, Y_WEIGHTS), yiq(rgb, I_WEIGHTS), yiq(rgb, Q_WEIGHTS)]

    def luma_delta(first, second) = yiq(blend(first), Y_WEIGHTS) - yiq(blend(second), Y_WEIGHTS)

    def yiq(rgb, weights) = rgb[0] * weights[0] + rgb[1] * weights[1] + rgb[2] * weights[2]

    # Translucent pixels are read over white, as pixelmatch does.
    def blend(word)
      return [(word >> 24) & 255, (word >> 16) & 255, (word >> 8) & 255] if (word & 255) == 255

      *rgb, alpha = unpack(word)
      rgb.map { |channel| 255 + (channel - 255) * alpha / 255.0 }
    end

    # The pixel sits between a darker and a lighter neighbour, both of them inside flat areas.
    def antialiased?(frame, other, place)
      extremes = luma_extremes(frame, place)
      return false unless extremes

      extremes.any? { |spot| siblings?(frame, spot) && siblings?(other, spot) }
    end

    # The darkest and the lightest neighbour; nil when more than two neighbours are identical.
    def luma_extremes(frame, place)
      centre = frame.at(*place)
      steps = frame.neighbours(*place).map { |spot| [luma_delta(centre, frame.at(*spot)), spot] }
      return if flat?(steps, frame.edge?(*place))

      low, high = steps.minmax_by(&:first)
      return unless low.first.negative? && high.first.positive?

      [low.last, high.last]
    end

    def flat?(steps, edge) = steps.count { |step| step.first.zero? } + (edge ? 1 : 0) > 2

    # More than two neighbours of exactly the same colour: part of a flat area, not an edge.
    def siblings?(frame, spot)
      centre = frame.at(*spot)
      same = frame.neighbours(*spot).count { |near| frame.at(*near) == centre }
      same + (frame.edge?(*spot) ? 1 : 0) > 2
    end

    # Changed pixels in CELL-sized cells, touching cells joined: one box per changed area.
    def regions(mask, frame)
      pending = changed_cells(mask, frame).to_h { |spot| [spot, true] }
      boxes = []
      boxes << box(flood(pending, pending.keys.first), frame) until pending.empty?
      boxes.sort_by { |found| [found[:y], found[:x]] }
    end

    def changed_cells(mask, frame)
      changed = mask.select { |_pos, kind| kind == :diff }.keys
      changed.map { |pos| frame.place(pos).map { |at| at / CELL } }.uniq
    end

    def box(group, frame)
      cols, rows = group.transpose
      left = cols.min * CELL
      top = rows.min * CELL
      { x: left, y: top, w: [(cols.max + 1) * CELL, frame.width].min - left,
        h: [(rows.max + 1) * CELL, frame.height].min - top }
    end

    def flood(pending, start)
      stack = [start]
      group = []
      pending.delete(start)

      while (spot = stack.pop)
        group << spot
        [-1, 0, 1].product([-1, 0, 1]).each do |step|
          near = [spot[0] + step[0], spot[1] + step[1]]
          stack << near if pending.delete(near)
        end
      end
      group
    end

    def diff_image(path, base:, mask:)
      return unless path && mask.value?(:diff)

      rgba = base.pixels.each_with_index.map { |word, pos| MARK.fetch(mask[pos]) { faded(word) } }.pack("N*")
      File.binwrite(path, PngDiff.encode_rgba(base.width, base.height, rgba))
      path
    end

    def faded(word)
      grey = (255 + (yiq(blend(word), Y_WEIGHTS) - 255) * 0.1).round
      pack([grey, grey, grey, 255])
    end

    # A box of the image, padded and enlarged ZOOM times by nearest neighbour, so an edge, an
    # alignment or a baseline is judged at the pixel and not at a glance.
    def crop(path, area, out:, pad: 8)
      frame = read(path)
      window = window(frame, area.merge(pad:))
      File.binwrite(out, PngDiff.encode_rgba(window[2] * ZOOM, window[3] * ZOOM, zoomed(frame, window)))
      out
    end

    def window(frame, area)
      left, width = span(area[:x], area[:w], pad: area[:pad], limit: frame.width)
      top, height = span(area[:y], area[:h], pad: area[:pad], limit: frame.height)
      [left, top, width, height]
    end

    # One axis of a padded crop: its start and its length, inside the image.
    def span(start, length, pad:, limit:)
      from = (start - pad).clamp(0, limit - 1)
      [from, [length + 2 * pad, limit - from].min]
    end

    def zoomed(frame, window)
      left, top, width, height = window
      rows = Array.new(height * ZOOM) do |line|
        Array.new(width * ZOOM) { |col| frame.at(left + col / ZOOM, top + line / ZOOM) }
      end
      rows.flatten.pack("N*")
    end
  end
end
