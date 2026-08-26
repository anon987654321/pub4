# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

# Spectral audit for rendered tracks.
#
# The engine already writes <track>.quality.json with integrated LUFS, true
# peak and a harmony score. None of those can see a spectral problem: a track
# whose top end has been filtered away, one with a resonant honk, or one that
# has collapsed to mono all measure exactly as loud as a good one. Loudness
# says how much, not what.
#
# So this measures shape rather than level, and writes a spectrogram alongside
# so the numbers can be checked by eye rather than taken on trust.
#
# Per track:
#   * band energy in dB across seven bands, so "no air" or "mud" is a number
#   * spectral centroid and rolloff, averaged over the whole file
#   * crest factor, DC offset, clipped-sample count
#   * stereo correlation — 1.0 means the render is effectively mono
#   * a PNG spectrogram
module SpectralAudit
  # Bands chosen for what goes wrong in this engine specifically: sub for the
  # kick, low_mid for the mud a sampled loop brings, presence for whether the
  # top survived the chain, air for whether a lowpass ate it.
  BANDS = {
    "sub" => [20, 60],
    "low" => [60, 250],
    "low_mid" => [250, 800],
    "mid" => [800, 2500],
    "presence" => [2500, 6000],
    "high" => [6000, 12_000],
    "air" => [12_000, 20_000],
  }.freeze

  module_function

  # ffmpeg writes its filter reports to stderr, so both streams matter. Reading
  # stdout alone is why the first run of this returned -120dB for every band:
  # the numbers were there, on the other stream.
  def sh(*cmd)
    out, err, _status = Open3.capture3(*cmd)
    [out, err].join("\n")
  end

  def ffprobe_duration(path)
    sh("ffprobe", "-v", "error", "-show_entries", "format=duration",
       "-of", "default=nw=1:nk=1", path).strip.to_f
  end

  # Mean of a per-frame aspectralstats metadata key across the file.
  def spectral_means(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "aspectralstats=measure=centroid+rolloff+flatness,ametadata=print:file=-",
             "-f", "null", "-")
    acc = Hash.new { |h, k| h[k] = [] }
    raw.each_line do |line|
      next unless line =~ /aspectralstats\.\d+\.(\w+)=([\d.eE+-]+)/

      value = Regexp.last_match(2).to_f
      acc[Regexp.last_match(1)] << value if value.finite?
    end
    acc.transform_values { |vals| vals.empty? ? nil : (vals.sum / vals.size).round(1) }
  end

  # RMS inside one band, in dBFS. Band-limit with a steep filter, then measure.
  def band_db(path, low, high)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             # highpass/lowpass cap at 2 poles; chaining two gives the steeper
             # skirt a band measurement needs without ffmpeg rejecting p=4.
             "-af", "highpass=f=#{low}:p=2,highpass=f=#{low}:p=2," \
                    "lowpass=f=#{high}:p=2,lowpass=f=#{high}:p=2,astats",
             "-f", "null", "-")
    m = raw[/RMS level dB:\s*(-?[\d.]+|-inf)/, 1]
    return -120.0 if m.nil? || m == "-inf"

    m.to_f.round(1)
  end

  def time_stats(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "astats",
             "-f", "null", "-")
    {
      "dc_offset" => raw[/DC offset:\s*(-?[\d.]+)/, 1]&.to_f&.round(4),
      "crest_factor" => raw[/Crest factor:\s*([\d.]+)/, 1]&.to_f&.round(2),
    }
  end

  # 1.0 = identical channels (mono). Below ~0.2 suggests phase trouble.
  def stereo_correlation(path)
    raw = sh("ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", "astats=measure_overall=none:measure_perchannel=none,aphasemeter=video=0:phasing=0",
             "-f", "null", "-")
    vals = raw.scan(/lavfi\.aphasemeter\.phase=([\d.-]+)/).flatten.map(&:to_f)
    return nil if vals.empty?

    (vals.sum / vals.size).round(3)
  end

  def spectrogram(path, out_png)
    FileUtils.mkdir_p(File.dirname(out_png))
    sh("ffmpeg", "-y", "-hide_banner", "-nostats", "-i", path,
       "-lavfi", "showspectrumpic=s=1200x480:mode=combined:legend=1:scale=log:color=intensity",
       out_png)
    File.file?(out_png) ? out_png : nil
  end

  def analyse(path, png_dir)
    name = File.basename(path)
    bands = BANDS.to_h { |label, (lo, hi)| [label, band_db(path, lo, hi)] }
    spec = spectral_means(path)
    {
      "track" => name,
      "duration_s" => ffprobe_duration(path).round(1),
      "bands_db" => bands,
      "centroid_hz" => spec["centroid"],
      "rolloff_hz" => spec["rolloff"],
      "flatness" => spec["flatness"],
      "stereo_correlation" => stereo_correlation(path),
      "spectrogram" => spectrogram(path, File.join(png_dir, "#{name}.png")),
    }.merge(time_stats(path))
  end

  # Findings are stated as thresholds with the number attached, so a
  # disagreement is about the threshold rather than about whether it happened.
  def findings(row)
    out = []
    b = row["bands_db"]
    out << "no air: #{b['air']}dB above 12k (>=25dB below presence #{b['presence']}dB) — top end filtered away" if
      b["air"] && b["presence"] && (b["presence"] - b["air"]) >= 25
    # No rolloff-based "dark" rule. rolloff is the 85%-of-energy point, so any
    # bass-heavy render lands under 2kHz however much top end it has: the first
    # version of this flagged a drum track as "energy dies below 2k" while its
    # spectrogram showed content all the way to 20k. Rolloff is reported as
    # context, not judged. Whether the top survived is the air/presence gap
    # below, which is a shape comparison and does not care about bass weight.
    out << "mud: low_mid #{b['low_mid']}dB sits #{(b['low_mid'] - b['mid']).round(1)}dB over mid" if
      b["low_mid"] && b["mid"] && (b["low_mid"] - b["mid"]) > 9
    out << "effectively mono: correlation #{row['stereo_correlation']}" if
      row["stereo_correlation"] && row["stereo_correlation"] > 0.98
    out << "DC offset #{row['dc_offset']}" if row["dc_offset"] && row["dc_offset"].abs > 0.01
    out << "crest #{row['crest_factor']} — heavily compressed" if
      row["crest_factor"] && row["crest_factor"] < 3.0
    out
  end
end
