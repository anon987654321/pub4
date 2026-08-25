# frozen_string_literal: true

require "json"

# What separates the takes you keep from the ones you delete.
#
# Every other tuning surface in this engine asks somebody to name a number.
# Nobody can name the number for "beautiful", including and especially me: I
# cannot hear these renders, and the measurements I can take are only worth
# something once they are anchored to takes an ear has already sorted. So this
# does not score a beat. It takes two piles the operator has made -- kept and
# rejected -- measures both, and reports only the dimensions where the piles
# actually separate.
#
# That last part is the whole design. Twenty measurements over six files will
# always show differences; most of them are noise. A dimension is reported only
# when the two groups barely overlap, expressed as the gap between them relative
# to their spread (a t-like separation, not a p-value -- these are samples of
# five, and pretending otherwise would be the kind of confident wrong number
# this engine has been bitten by). Everything else is listed as "no separation",
# which is a real answer: it means that dimension is not what you are hearing.
#
#   dilla taste keep/*.wav -- reject/*.wav
#
# The output is a list of sentences and, where the separation is clean, the knob
# that moves that dimension. It stops there. It does not write a default,
# because a default that changes how a render sounds is the operator's, and
# because five takes is a hint, not a mandate.
module DillaTaste
  # Each dimension: how to measure it, and which knob moves it. The knob is
  # named so a finding is actionable; nothing here sets one.
  #
  # Every uppercase name here is checked against DillaKnobs by the suite. Two of
  # them were not knobs: MASTER_TARGET_LRA and MASTER_TARGET_LUFS, which the
  # engine reads nowhere. So this module's whole output -- a dimension, a
  # separation, and the knob that moves it -- ended by naming a control that does
  # not exist, on the two dimensions an operator is most likely to act on.
  #
  # That is the same defect this file exists to avoid in the other direction: a
  # confident number nobody can act on. Advice about a knob that is not there is
  # worse than no advice, because it is followed.
  #
  # LRA has no single knob and saying so is the honest answer -- it falls out of
  # the arrangement and the master compression, which is why both are named
  # rather than one invented.
  DIMENSIONS = {
    "loudness range (LRA)" => { units: "LU", knob: "SECTION_LAYERS, the master bus compression" },
    "integrated loudness" => { units: "LUFS", knob: "MASTER_LUFS (STREAM_LUFS in a stream)" },
    "true peak" => { units: "dBTP", knob: "the limiter" },
    "transient density" => { units: "onsets/s", knob: "GHOST_TIER, DRUM_CHOPS, the drum feel" },
    "low-versus-mid balance" => { units: "dB", knob: "KICK_GAIN, BASS_MIX_WEIGHT, SAMPLE_LOOP_SUB_DB" },
    "high-frequency energy" => { units: "dB", knob: "SAMPLE_EXCITE, SAMPLE_LOOP_LP" },
    "stereo width" => { units: "ratio", knob: "stereo_pan, apulsator amount" },
    "dynamic spread" => { units: "dB", knob: "the master bus compression" },
  }.freeze

  class << self
    def measure(path)
      return unless File.file?(path)

      values = {}
      values.merge!(loudness(path))
      values.merge!(bands(path))
      values.merge!(rhythm(path))
      values["stereo width"] = width(path)
      values.compact
    end

    # A pile against a pile.
    def compare(kept_paths, rejected_paths)
      kept = kept_paths.filter_map { |p| measure(p) }
      rejected = rejected_paths.filter_map { |p| measure(p) }
      return { error: "need at least two files on each side" } if kept.length < 2 || rejected.length < 2

      findings = DIMENSIONS.keys.filter_map do |dimension|
        a = kept.filter_map { |m| m[dimension] }
        b = rejected.filter_map { |m| m[dimension] }
        next if a.length < 2 || b.length < 2

        { dimension:, kept: stats(a), rejected: stats(b), separation: separation(a, b),
          knob: DIMENSIONS[dimension][:knob], units: DIMENSIONS[dimension][:units] }
      end
      { kept: kept.length, rejected: rejected.length,
        findings: findings.sort_by { |f| -f[:separation] } }
    end

    # How far apart two groups are, in units of their own spread. Above about
    # 1.5 the piles barely overlap; below 0.8 there is nothing here.
    def separation(a, b)
      ma = a.sum / a.length.to_f
      mb = b.sum / b.length.to_f
      pooled = Math.sqrt((variance(a) + variance(b)) / 2.0)
      return 0.0 if pooled < 1e-9

      ((ma - mb).abs / pooled).round(2)
    end

    def variance(values)
      m = values.sum / values.length.to_f
      values.sum { |v| (v - m)**2 } / [values.length - 1, 1].max
    end

    def stats(values)
      m = values.sum / values.length.to_f
      { mean: m.round(2), spread: Math.sqrt(variance(values)).round(2),
        min: values.min.round(2), max: values.max.round(2) }
    end

    private

    def ffmpeg(path, filter)
      IO.popen(["ffmpeg", "-hide_banner", "-nostats", "-i", path.to_s, "-af", filter, "-f", "null", "-"],
               err: %i[child out], &:read).to_s
    rescue StandardError
      ""
    end

    def loudness(path)
      # ebur128 and astats print their summaries at INFO level; -v error drops
      # them silently and leaves you measuring nothing, which has happened here.
      out = ffmpeg(path, "ebur128=peak=true")
      # LAST match, not first. ebur128 prints a running `I:` and `LRA:` for every
      # frame and then the summary at the end, so the first match is an early
      # frame -- which for a fade-in is -70 LUFS on everything. Two piles 14 dB
      # apart in level both read -70.0 and the tool reported no separation in
      # loudness, on the one dimension it had been handed a guaranteed
      # difference. Checked against a known case before being believed, which is
      # the only reason it was caught.
      {
        "integrated loudness" => out.scan(/I:\s*(-?[\d.]+)\s*LUFS/).flatten.last&.to_f,
        "loudness range (LRA)" => out.scan(/LRA:\s*(-?[\d.]+)\s*LU/).flatten.last&.to_f,
        "true peak" => out.scan(/Peak:\s*(-?[\d.]+)\s*dBFS/).flatten.map(&:to_f).max,
      }
    end

    def bands(path)
      low = band_level(path, 40, 160)
      mid = band_level(path, 400, 3000)
      high = band_level(path, 6000, 16_000)
      {
        "low-versus-mid balance" => (low && mid ? (low - mid).round(2) : nil),
        "high-frequency energy" => (high && mid ? (high - mid).round(2) : nil),
      }
    end

    def band_level(path, low, high)
      out = ffmpeg(path, "highpass=f=#{low},lowpass=f=#{high},astats=measure_overall=RMS_level:measure_perchannel=none")
      out[/RMS level dB:\s*(-?[\d.]+)/, 1]&.to_f
    end

    # Onsets per second and the peak-to-RMS spread, from one decode.
    def rhythm(path)
      raw = IO.popen(["ffmpeg", "-v", "quiet", "-i", path.to_s, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
                     "rb", &:read)
      return {} if raw.nil? || raw.empty?

      samples = raw.unpack("s<*")
      env = samples.each_slice(80).map { |c| Math.sqrt(c.sum { |v| v.to_f * v } / c.length) }
      return {} if env.length < 10

      mean = env.sum / env.length
      onsets = (1...env.length).count { |i| env[i] > mean * 1.6 && env[i] > env[i - 1] * 1.5 }
      peak = env.max
      {
        "transient density" => (onsets / (env.length / 100.0)).round(3),
        "dynamic spread" => (peak.positive? && mean.positive? ? (20 * Math.log10(peak / mean)).round(2) : nil),
      }
    end

    # Side energy over mid energy. A mono file reads 0.
    def width(path)
      out = ffmpeg(path, "astats=measure_overall=RMS_level:measure_perchannel=RMS_level")
      levels = out.scan(/RMS level dB:\s*(-?[\d.]+)/).flatten.map(&:to_f)
      return nil if levels.length < 3

      # channel 1, channel 2, overall — a crude but stable width proxy.
      (levels[0] - levels[1]).abs.round(3)
    end
  end
end
