# frozen_string_literal: true

# A take must stay a grade of its source, judged on what a colourist protects
# rather than on whether the palette moved, since moving it is often the point
# of a look. Measured against the source at TAKE_PROBE_EDGE px, every take must
# keep the source's shapes, keep its black and white points (no more than
# TAKE_MAX_CLIP of the frame newly blown or crushed) and keep at least half its
# tonal spread. Colour may move within the look's own budget: how far overall
# colourfulness may rise, how far neutral greys may be tinted (mean C*), and how
# far skin may turn in hue, which is held tightest, as a colourist holds it on
# the skin-tone line. A take that drains colour on purpose (black and white,
# toned) is judged on shapes and tones alone. Every bound is relative to the
# source, so a low-key photograph is judged against its own darkness; the fixed
# brightness window this replaced refused every faithful grade of one. Default
# budgets sit at the 90th percentile of the light takes of nine photographs
# (2026-10-27): chroma 1.8x, neutral C* 10.4, skin 17.6 degrees, which is how far
# an ordinary film grade moves them. The heavy takes testers called destroyed ran
# 6.7x, 58.6 and 90.8 at the same percentile. Colourfulness is judged only where
# the source has colour to compare against; a grey source is all neutral.
TAKE_PROBE_EDGE = 512.0
TAKE_MIN_STRUCTURE = 0.5
TAKE_MAX_CLIP = 0.05
TAKE_MIN_SPREAD_RATIO = 0.5
TAKE_TONED_CHROMA = 0.6
TAKE_BUDGET = { chroma: 1.8, neutral: 10.0, skin: 18.0 }.freeze
# A named look tints neutrals and lifts colour by design, as its stock and print do.
LOOK_BUDGET = { chroma: 2.2, neutral: 16.0, skin: 22.0 }.freeze
TAKE_MIN_SOURCE_CHROMA = 4.0
# Colourfulness is measured against at least this mean C*, so a frame that is
# mostly grey wall does not turn a modest tint into a tenfold rise.
TAKE_CHROMA_FLOOR = 10.0
# Looks whose point is a new palette get more of it; skin still has a ceiling.
LOOK_BUDGETS = {
  day_for_night: { chroma: 2.6, neutral: 30.0, skin: 30.0 },
  cross_process: { chroma: 2.8, neutral: 18.0, skin: 25.0 },
  tokyo_night: { chroma: 2.8, neutral: 18.0, skin: 20.0 },
  neon_night: { chroma: 2.8, neutral: 18.0, skin: 20.0 },
  infrared_look: { chroma: 2.0, neutral: 16.0, skin: 40.0 },
  technicolor_3strip: { chroma: 2.6, neutral: 12.0, skin: 22.0 },
  golden_age: { chroma: 2.6, neutral: 18.0, skin: 22.0 },
  # A toning process: blue neutrals are its point, and skin goes blue with them.
  cyanotype_look: { chroma: 3.0, neutral: 40.0, skin: 90.0 },
  magic_hour: { chroma: 2.6, neutral: 16.0, skin: 22.0 },
  blockbuster: { chroma: 2.4, neutral: 28.0, skin: 22.0 },
  cinematic: { chroma: 2.2, neutral: 14.0, skin: 22.0 },
}.freeze

# A look's own budget only ever widens the baseline it starts from.
def take_budget(look)
  base = look ? LOOK_BUDGET : TAKE_BUDGET
  base.merge(LOOK_BUDGETS.fetch(look&.to_sym, {})) { |_key, floor, own| [floor, own].max }
end

def check_take_survives!(take, source, look = nil)
  problems = take_problems(take_readings(source, take), take_budget(look))
  return if problems.empty?

  raise ArgumentError, "take refused: #{problems.join(", ")}"
end

def take_problems(readings, budget = TAKE_BUDGET)
  problems = []
  problems << format("structure %.2f", readings[:structure]) if readings[:structure] < TAKE_MIN_STRUCTURE
  problems << format("clipping +%.1f%%", 100 * readings[:clip]) if readings[:clip] > TAKE_MAX_CLIP
  problems << format("spread %.2fx", readings[:spread]) if readings[:spread] < TAKE_MIN_SPREAD_RATIO
  problems.concat(palette_problems(readings, budget))
end

def palette_problems(readings, budget)
  return [] if readings[:chroma] && readings[:chroma] < TAKE_TONED_CHROMA

  problems = []
  problems << format("colour %.1fx", readings[:chroma]) if readings[:chroma].to_f > budget[:chroma]
  problems << format("neutrals tinted C* %.0f", readings[:neutral]) if readings[:neutral].to_f > budget[:neutral]
  problems << format("skin turned %.0f deg", readings[:skin]) if readings[:skin].to_f > budget[:skin]
  problems
end

# Readings of a take against its source: edge-map correlation for structure,
# then palette, clipping and spread. Colour is read on a light blur, so grain
# counts as texture and not as a change of palette.
def take_readings(source, take)
  before = take_probe(source)
  after = take_probe(take)
  after = after.resize(before.width.to_f / after.width, vscale: before.height.to_f / after.height)
  {
    structure: edge_correlation(before, after),
    clip: take_extremes(after) - take_extremes(before),
    spread: take_spread(after) / [take_spread(before), 1.0].max,
  }.merge(take_palette(before.gaussblur(2), after.gaussblur(2)))
end

def take_probe(image)
  rgb = rgb_bands(image).cast(:uchar).copy(interpretation: :srgb)
  rgb.resize(TAKE_PROBE_EDGE / [rgb.width, rgb.height].max).copy_memory
end

def take_luma(image) = image.colourspace(:b_w).extract_band(0).cast(:float)

def edge_correlation(before, after)
  left = take_luma(before).sobel.cast(:float)
  right = take_luma(after).sobel.cast(:float)
  spread = left.deviate * right.deviate
  return 1.0 if spread.zero?

  ((left * right).avg - (left.avg * right.avg)) / spread
end

def take_extremes(image)
  luma = take_luma(image)
  ((luma >= 250).avg + (luma <= 5).avg) / 255.0
end

# A float, because the ratio of two integer spreads divided to zero for every
# take with less spread than its source.
def take_spread(image)
  luma = take_luma(image).cast(:uchar)
  (luma.percent(95) - luma.percent(5)).to_f
end

# Overall chroma ratio; the mean C* a take gives what was neutral grey in the
# source; and the mean hue turn over what was skin. Neutral and skin read nil
# when too little of the frame holds either for the number to mean anything.
SKIN_LAB_HUE = (20.0..75.0)
SKIN_LAB_CHROMA = (8.0..55.0)
SKIN_LAB_LIGHTNESS = (25.0..92.0)
NEUTRAL_CHROMA = 6.0

def take_palette(before, after)
  lightness, chroma_before, hue_before = before.colourspace(:lch).bandsplit
  _, chroma_after, hue_after = after.colourspace(:lch).bandsplit
  {
    chroma: chroma_before.avg < TAKE_MIN_SOURCE_CHROMA ? nil : chroma_after.avg / [chroma_before.avg, TAKE_CHROMA_FLOOR].max,
    neutral: masked_mean(chroma_after, chroma_before < NEUTRAL_CHROMA, 0.02),
    skin: masked_mean(hue_turn(hue_before, hue_after), skin_tones(lightness, chroma_before, hue_before), 0.01),
  }
end

def skin_tones(lightness, chroma, hue)
  [[hue, SKIN_LAB_HUE], [chroma, SKIN_LAB_CHROMA], [lightness, SKIN_LAB_LIGHTNESS]]
    .map { |band, range| (band > range.first) & (band < range.last) }.reduce(:&)
end

def hue_turn(before, after)
  turn = (before - after).abs
  (turn > 180).ifthenelse(turn * -1 + 360, turn)
end

# The mean of `values` over a 0/255 mask, or nil below `min_share` of the frame.
def masked_mean(values, mask, min_share)
  share = mask.avg / 255.0
  return if share < min_share

  (values * (mask / 255)).avg / share
end
