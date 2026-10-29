# frozen_string_literal: true

# Did that effect actually change the picture?
#
# Off unless POSTPRO_EXPLAIN=1, because it costs two reductions per step and the
# ordinary path should not pay for a diagnostic. When on, every fx line gains
# the mean and spread it moved, and an effect that moved neither is named as
# having done nothing — which is a defect this file has already had once, in the
# form of an fx name with no implementation.
module PostproExplain
  def self.on? = ENV["POSTPRO_EXPLAIN"] == "1"

  # Brightness, contrast and TEXTURE.
  #
  # The third was missing, and its absence is why a chain that was destroying
  # micro-detail read as healthy here. avg and deviate are both nearly blind to
  # a gaussian blur — softening a photograph moves its mean not at all and its
  # standard deviation barely, while taking most of the high-frequency energy
  # out of it. Measured on one frame: optical_blur reported spread-0.0021, a
  # number small enough to ignore, in the same step that removed 57% of the
  # picture's texture.
  #
  # uncanny.rb's own header says the number to watch is the texture delta. The
  # per-step report could not see it.
  def self.snapshot(image)
    return unless on?

    { avg: image.avg, deviate: image.deviate, texture: texture(image) }
  rescue StandardError
    nil
  end

  # Laplacian energy, as uncanny.rb measures it. Inlined rather than delegated:
  # this module is defined before the bootstrap has decided whether vips is
  # present, so it cannot require uncanny at load time.
  def self.texture(image)
    luma = image.bands >= 3 ? image.colourspace("b-w") : image
    luma = luma.cast(:float) / 255.0
    luma.conv(Vips::Image.new_from_array([[0, -1, 0], [-1, 4, -1], [0, -1, 0]]), precision: :float).abs.avg
  rescue StandardError
    nil
  end

  def self.delta(before, image)
    return "" unless before

    now = snapshot(image)
    return "" unless now

    d_avg = (now[:avg] - before[:avg]).abs
    d_dev = (now[:deviate] - before[:deviate]).abs
    d_tex = now[:texture] && before[:texture] ? (now[:texture] - before[:texture]).abs : 0.0
    return " NO-OP (moved nothing)" if d_avg < 1e-9 && d_dev < 1e-9 && d_tex < 1e-9

    line = format(" avg%+.4f spread%+.4f", now[:avg] - before[:avg], now[:deviate] - before[:deviate])
    line += format(" texture%+.4f", now[:texture] - before[:texture]) if now[:texture] && before[:texture]
    line
  rescue StandardError
    ""
  end
end
