# frozen_string_literal: true

# Does every preset name things that exist, and does every table have a row for
# every stock that reaches it?
#
# Nothing asked, and the answers were no. preset() returned the image unchanged
# for an fx name it had no arm for while still logging the step as run; five
# presets declared a lens that no chain applied; four stocks had no row in
# RECIPROCITY_SHIFT and one none in PUSH_RESPONSE, so they silently borrowed
# Portra's; every STOCKS entry carried a colour matrix that nothing read; and
# recipe() called two thirds of its allowed effects with an intensity in the
# slot where a stock symbol, an RGB triplet or a Kelvin value belongs.
#
# None of it raised. That is the whole reason for this: the failure mode of a
# table-driven pipeline is not a crash, it is a picture that came out slightly
# wrong and a log that says everything ran.
#
# No image processing and no files touched — it reads the tables.
# What grain does this scan actually carry?
#
# Until this existed the only way to set STOCKS[:grain] was to choose a number
# that looked about right, and every number in that column was chosen that way.
# Zhang, Wang, Tian and Pappas (TOG 42:4, 2023) derive the Boolean model's
# statistics in closed form and, with them, estimators that run backwards from
# a scan to the parameters. This is that estimator at the resolution this file
# needs: sigma per tone, which is the scaling function, and the correlation
# radius, which is the crystal.
#
# Point it at a flat frame — a sky, a wall, a grey card, a clear rebate.
# Structure in the picture reads as grain and inflates the answer, which is why
# the bins are printed rather than one confident number.
#
# Run against this file's own output at a known strength it reads about 15% low
# and one step fine: tri_x rendered at a declared 6.0 levels and a 4.0 px
# crystal comes back 5.0 and 3.4. The residual is a high-pass, so the grain's
# coarsest octave is subtracted along with the picture. Read the figures as a
# floor, and read the knots, which are a ratio and carry none of the bias.
FIT_GRAIN_BINS = 16
FIT_GRAIN_LAGS = 12

def fit_grain(path)
  image = load_image(path)
  return "fit-grain: cannot read #{path}" unless image

  luma = rgb_bands(image).colourspace("b-w").cast("float")
  local = luma.gaussblur(4.0)
  residual = luma - local
  pixels = luma.width * luma.height

  bins = (0...FIT_GRAIN_BINS).map do |bin|
    low = bin * 256.0 / FIT_GRAIN_BINS
    mask = ((local >= low) & (local < low + 256.0 / FIT_GRAIN_BINS)).linear([1.0 / 255], [0])
    share = mask.avg
    next [low.round, nil, 0] if share * pixels < 256

    [low.round, Math.sqrt((residual * residual * mask).avg / share), (share * pixels).round]
  end

  [fit_grain_report(path, luma, bins), fit_grain_correlation(residual)].join("\n")
end

# The first lag at which the residual stops agreeing with itself is the
# crystal, in pixels of this scan.
def fit_grain_correlation(residual)
  width = residual.width
  variance = residual.deviate**2
  return "  correlation: flat residual, nothing to measure" if variance < 1e-9

  correlations = (1..FIT_GRAIN_LAGS).map do |lag|
    shifted = residual.extract_area(lag, 0, width - lag, residual.height)
    (residual.extract_area(0, 0, width - lag, residual.height) * shifted).avg / variance
  end
  crossing = correlations.index { |c| c < Math::E**-1 }
  radius = crossing ? crossing + 1 : FIT_GRAIN_LAGS
  implied = radius * GRAIN_REFERENCE_WIDTH / width
  format("  correlation radius %d px at this width, which is GRAIN_CELL_BASE %.1f at the 2048 px reference\n" \
         "  lags 1..%d: %s", radius, implied, FIT_GRAIN_LAGS, correlations.map { |c| c.round(2) }.join(" "))
end

def fit_grain_report(path, luma, bins)
  midtone = bins.map { |low, sigma, _| [((low + 8) - 128).abs, sigma] }.reject { |_, s| s.nil? }.min_by(&:first)
  peak = midtone&.last
  knots = bins.map { |_, sigma, _| peak && sigma ? (sigma / peak).round(3) : 0.0 }
  lines = ["fit-grain #{File.basename(path)} #{luma.width}x#{luma.height}"]
  bins.each do |low, sigma, count|
    lines << format("  sRGB %3d-%3d  sigma %s  (%d px)", low, low + (256 / FIT_GRAIN_BINS) - 1,
                    sigma ? format("%5.2f", sigma) : "    -", count)
  end
  lines << format("  mid-grey sigma %.2f levels, which is STOCKS[:grain] %.0f at GRAIN_SIGMA_SCALE %.2f",
                  peak || 0.0, (peak || 0.0) / GRAIN_SIGMA_SCALE, GRAIN_SIGMA_SCALE)
  lines << "  grain_knots: [#{knots.join(", ")}]"
  # Newson et al. (SSVM 2017): coverage u of a Boolean crystal field has
  # variance u(1-u). GRAIN_SCALING_KNOTS is that envelope. R² against it says
  # whether this scan is emulsion or a LUT.
  r2 = boolean_envelope_r2(knots)
  lines << format("  Boolean envelope R² %.3f (Newson u(1-u); a LUT stock lands well below 0.9)", r2)
  lines.join("\n")
end

def boolean_envelope_knots(bins = FIT_GRAIN_BINS)
  denom = [bins - 1, 1].max.to_f
  (0...bins).map do |index|
    coverage = index / denom
    Math.sqrt(coverage * (1.0 - coverage)) * 2.0
  end
end

def boolean_envelope_r2(measured)
  model = boolean_envelope_knots(measured.size)
  n = measured.size.to_f
  mean_m = measured.sum / n
  mean_b = model.sum / n
  cov = measured.zip(model).sum { |m, b| (m - mean_m) * (b - mean_b) }
  var_m = measured.sum { |m| (m - mean_m)**2 }
  var_b = model.sum { |b| (b - mean_b)**2 }
  return 0.0 if var_m < 1e-12 || var_b < 1e-12

  (cov / Math.sqrt(var_m * var_b))**2
end
