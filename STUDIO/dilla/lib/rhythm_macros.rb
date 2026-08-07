# frozen_string_literal: true

# Macro/micro rhythm — tempo ramps, stripdown, gap rhythm, prime bars.
module DillaRhythm
  @ctx = { n_bars: 16, base_bpm: 90.0, duration: 32.0 }

  module_function

  def configure!(n_bars:, bpm:, duration: nil)
    @ctx = { n_bars:, base_bpm: bpm.to_f, duration: duration || (60.0 / bpm * 4 * n_bars) }
  end

  def ctx
    @ctx
  end

  def bar_bpm(bar)
    n = @ctx[:n_bars]
    base = @ctx[:base_bpm]
    return base unless macro_enabled?

    return staircase_bpm(bar, base) if ENV["BPM_STAIRCASE"] == "1"
    return ramp_bpm(bar, n, base) if ENV["TEMPO_RAMP"] == "1"
    return accel_bpm(bar, n, base) if ENV["TEMPO_ACCEL"] == "1"
    base
  end

  def macro_enabled?
    ENV["RHYTHM_MACROS"] != "0"
  end

  def ramp_bpm(bar, n_bars, base)
    steps = (n_bars / 4.0).ceil
    base + (bar / 4) * (ENV["TEMPO_RAMP_STEP"] || 1).to_f
  end

  def accel_bpm(bar, n_bars, base)
    mult = 1.0 + (bar.to_f / [n_bars, 1].max) * 0.01 * (ENV["TEMPO_ACCEL_PCT"] || 1).to_f
    base * mult
  end

  def staircase_bpm(bar, base)
    base + bar * (180.0 - 60.0) / [(@ctx[:n_bars] - 1), 1].max
  end

  def bar_duration_sec(bar, _beat_p)
    bpm = bar_bpm(bar)
    (60.0 / bpm) * 4.0
  end

  def stripdown_gain(bar, section)
    return 1.0 unless macro_enabled? && ENV["STRIPDOWN"] == "1"
    n = @ctx[:n_bars]
    return 1.0 if section != :main
    progress = bar.to_f / n
    1.0 - (progress * 0.35)
  end

  def element_strip_gain(elapsed_sec)
    return 1.0 unless macro_enabled? && ENV["ELEMENT_STRIP"] == "1"
    removed = (elapsed_sec / 10.0).floor
    [1.0 - removed * 0.08, 0.25].max
  end

  def subdivision_density_steps(base_steps, bar)
    return base_steps unless macro_enabled? && ENV["SUB_DENSITY"] == "1"
    extra = (0..15).select { |s| s % 2 == 0 && Random.new(bar).rand < 0.4 }
    (base_steps + extra).uniq.sort
  end

  # Periodic full-layer drop-out — "remove elements periodically for
  # contrast" rather than stripdown's one-way fade to silence. Ducks (not
  # mutes) for `span` bars every `period` bars; never on bar 0, so the
  # arrangement is fully established before the first variation.
  def periodic_layer_drop_gain(bar, period: 8, span: 1)
    return 1.0 unless macro_enabled? && ENV["ARRANGEMENT_VARIATION"] != "0"
    return 1.0 if period <= 0 || bar.zero?
    (bar % period) < span ? 0.12 : 1.0
  end
end
