# frozen_string_literal: true

# Scores a render's MIX, not its harmony.
#
# beauty_report already scores chords. Nothing scored the thing that actually
# decided which tracks survived: whether the kick sits right against the mids,
# whether the track has any dynamics left, whether the top is harsh. Every one
# of those judgements this engine's operator made by ear had a number behind it
# that was computed by hand and then thrown away.
#
# The targets are not invented. They are measured from tracks that were kept
# after listening, which is the only defensible source for a "should sound like"
# number -- a threshold picked in advance measures the person who picked it.
module MixScore
  # Measured from demo29 and demo30, the two renders kept on their merits.
  # Ranges span both plus a little tolerance, rather than averaging them into a
  # single value neither actually has.
  REFERENCE = {
    kick_vs_mid: { range: (2.0..6.0), unit: "dB",
                   why: "kick against the midrange; demo29 +4.7, demo30 +3.0" },
    lufs: { range: (-18.0..-15.0), unit: "LUFS",
            why: "integrated loudness; both keepers near -16.5" },
    lra: { range: (4.0..9.0), unit: "LU",
           why: "loudness range; keepers 6.0 and 7.0. Below 3 is flat" },
    # Derived from the keepers like the rest, after the first attempt was
    # invented instead. I guessed -14..-4 on the reasoning that sub above -4
    # would mask the mids; demo29 measures +3.3 and demo30 +1.5, so the guess
    # was wrong and the tracks were right. This is precisely the failure the
    # comment at the top of this file warns about, committed by the person who
    # wrote the warning, one field after writing it.
    sub_vs_mid: { range: (0.0..5.5), unit: "dB",
                  why: "sub against mids; demo29 +3.3, demo30 +1.5" },
    cymbal_crest: { range: (18.0..30.0), unit: "dB",
                    why: "peak minus mean above 6k; low means smeared, high means spiky" },
    tilt: { range: (14.0..26.0), unit: "dB",
            why: "lows minus highs; high is dull, low is harsh" },
  }.freeze

  module_function

  def band(path, lo, hi, stat = :mean)
    key = stat == :peak ? "max_volume" : "mean_volume"
    out = `ffmpeg -v info -i "#{path}" -af "highpass=f=#{lo},lowpass=f=#{hi},volumedetect" -f null - 2>&1`
    out[/#{key}: ([-0-9.]+)/, 1].to_f
  end

  def loudness(path)
    out = `ffmpeg -v info -i "#{path}" -af ebur128=framelog=quiet -f null - 2>&1`
    [out[/I:\s*([-0-9.]+)/, 1].to_f, out[/LRA:\s*([-0-9.]+)/, 1].to_f]
  end

  def measure(path)
    i, lra = loudness(path)
    mids = band(path, 400, 3000)
    cym = band(path, 6000, 14_000)
    {
      kick_vs_mid: (band(path, 40, 110) - mids).round(2),
      lufs: i.round(2),
      lra: lra.round(2),
      sub_vs_mid: (band(path, 20, 60) - mids).round(2),
      cymbal_crest: (band(path, 6000, 14_000, :peak) - cym).round(2),
      tilt: (band(path, 40, 400) - band(path, 5000, 14_000)).round(2),
    }
  end

  # Distance from the acceptable range, zero when inside it. Reported rather
  # than reduced to a single score: a track that is 6 dB off on one axis and
  # perfect elsewhere is a different problem from one slightly off on all six,
  # and a single number hides which.
  def score(path)
    m = measure(path)
    m.map do |key, value|
      spec = REFERENCE.fetch(key)
      r = spec[:range]
      miss =
        if value < r.begin then (value - r.begin).round(2)
        elsif value > r.end then (value - r.end).round(2)
        else 0.0
        end
      [key, value, miss, spec]
    end
  end

  def report(path)
    unless File.file?(path)
      warn "mix score: no such file #{path}"
      return false
    end

    rows = score(path)
    puts "  #{File.basename(path)}"
    puts format("  %-14s %9s %11s %8s  %s", "measure", "value", "target", "miss", "")
    rows.each do |key, value, miss, spec|
      r = spec[:range]
      puts format("  %-14s %9.2f %11s %8s  %s",
                  key, value, "#{r.begin}..#{r.end}",
                  miss.zero? ? "ok" : format("%+.2f", miss),
                  miss.zero? ? "" : spec[:why])
    end
    off = rows.count { |r| !r[2].zero? }
    puts
    puts off.zero? ? "  in range on all #{rows.size} measures" : "  #{off} of #{rows.size} outside the reference"
    off.zero?
  end

  # Compare two files directly, for A/B where the reference is another render
  # rather than the stored ranges.
  def compare(a, b)
    ma = measure(a)
    mb = measure(b)
    puts format("  %-14s %10s %10s %9s", "measure", File.basename(a, ".*")[0, 10],
                File.basename(b, ".*")[0, 10], "delta")
    ma.each_key do |k|
      puts format("  %-14s %10.2f %10.2f %+9.2f", k, ma[k], mb[k], mb[k] - ma[k])
    end
  end
end
