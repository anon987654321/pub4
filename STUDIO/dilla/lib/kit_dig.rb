# frozen_string_literal: true

require_relative "radio_chop"

# A drum kit cut from our own recordings.
#
# The engine plays downloaded kits. EXTERNAL_DRUM_KITS holds three of them --
# 01-hard-trap, 02-bounce, 03-soulful-vintage -- and every render that has ever
# come out of here used somebody else's drums, which is the same objection that
# applied to the track names.
#
# samples/own/ holds nine finished recordings by the operator and named
# collaborators. The drums in them are ours. They are also buried in a mix, so
# getting them out is the same problem `chop` solves, inverted: chop runs demucs
# and throws the drum stem away, and this runs demucs and throws everything else
# away.
#
# What comes out is one wav per role in samples/drums/custom/, which
# drum_sample_path prefers over every other source, so a kit written here
# replaces the downloaded ones in every render without a switch being set.
module KitDig
  ROOT = File.expand_path("..", __dir__)
  DEST = File.join(ROOT, "samples", "drums", "custom")
  MANIFEST = File.join(DEST, "provenance.json")
  MODEL = "htdemucs_6s"

  # The roles the engine asks drum_sample_path for, and what each one is in
  # frequency terms. Bands are the same ones the rest of the engine measures in.
  #
  # `pick` is which end of the sorted candidates to take. A kick wants the one
  # with the most low end; a hat wants the shortest, brightest thing available.
  ROLES = {
    "kick.wav" => { band: [40, 140], min_len: 0.10, max_len: 0.60, prefer: :low },
    "snare.wav" => { band: [180, 1400], min_len: 0.08, max_len: 0.45, prefer: :mid },
    "ghost.wav" => { band: [180, 1400], min_len: 0.04, max_len: 0.18, prefer: :quiet },
    "hat.wav" => { band: [6000, 14_000], min_len: 0.02, max_len: 0.12, prefer: :high },
    "open_hat.wav" => { band: [6000, 14_000], min_len: 0.18, max_len: 0.70, prefer: :high },
  }.freeze

  # A hit is worth cutting if it stands this far above the surrounding level.
  ONSET_LIFT_DB = 7.0
  ONSET_WINDOW = 0.01
  # Two hits closer than this are one hit with a flam on it.
  MIN_GAP_SEC = 0.09
  SLICE_SEC = 0.9

  module_function

  def sources
    Dir[File.join(ROOT, "samples", "own", "*.{mp3,wav,flac,m4a}")].sort
  end

  # Onsets on the isolated drum stem, in seconds.
  #
  # A lift above the local median rather than a fixed threshold: these are nine
  # different recordings at nine different levels, and a constant that suits one
  # finds nothing in another.
  def onsets(path)
    series = RadioChop.rms_series(path, window: ONSET_WINDOW)
    return [] if series.length < 32

    sorted = series.sort
    floor = sorted[series.length / 2]
    gap = (MIN_GAP_SEC / ONSET_WINDOW).to_i
    hits = []
    series.each_with_index do |v, i|
      next if v < floor + ONSET_LIFT_DB
      next if hits.any? && (i - hits.last) < gap
      next if i.positive? && series[i - 1] >= v      # only the rising edge

      hits << i
    end
    hits.map { |i| (i * ONSET_WINDOW).round(4) }
  end

  # Cut one hit and describe it, so the picker has something to sort on.
  def measure(src, start, dest)
    RadioChop.run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                   "-ss", start.to_s, "-t", SLICE_SEC.to_s, "-i", src,
                   "-ac", "1", "-ar", RadioChop::SAMPLE_RATE.to_s,
                   "-c:a", "pcm_s16le", dest, label: "slice")
    pcm = RadioChop.pcm_mono(dest)
    return nil if pcm.empty?

    peak = pcm.map(&:abs).max
    return nil if peak < 0.05

    # Decay length: how long until it falls 30 dB below its own peak. That is
    # what separates a closed hat from an open one, and a ghost from a snare,
    # far more reliably than any spectral measure.
    floor = peak * 0.032
    tail = pcm.rindex { |s| s.abs > floor } || 0
    {
      path: dest, start:, peak: peak.round(4),
      length: (tail.to_f / RadioChop::ANALYSIS_RATE).round(4),
      bands: RadioChop::BANDS.keys.to_h { |k| [k, RadioChop.mean(RadioChop.rms_series(dest, filter: RadioChop::BANDS[k], window: 0.02)) || -90.0] },
    }
  end

  # How well does this hit serve this role?
  def score(hit, role)
    spec = ROLES.fetch(role)
    return -99 unless hit[:length].between?(spec[:min_len], spec[:max_len])

    low = hit[:bands][:low]
    body = hit[:bands][:body]
    air = hit[:bands][:air]
    case spec[:prefer]
    when :low then (low - body) + (low - air)
    when :mid then body - ((low + air) / 2.0)
    when :high then air - body
    when :quiet then (body - ((low + air) / 2.0)) - (hit[:peak] * 12)
    else 0
    end
  end

  def build!(demucs:, limit: nil)
    raise "demucs required" if demucs.nil? || demucs.empty?

    srcs = sources
    srcs = srcs.first(limit) if limit
    raise "no recordings in samples/own" if srcs.empty?

    work = File.join(ROOT, "scratch", "kit_dig")
    FileUtils.mkdir_p(work)
    puts "kit: #{srcs.length} recordings -> demucs #{MODEL}, keeping the drum stem only"

    stems = srcs.filter_map do |src|
      dir = File.join(work, MODEL, File.basename(src, ".*"))
      drums = File.join(dir, "drums.wav")
      unless File.file?(drums)
        RadioChop.run!(*demucs, "-n", MODEL, "-o", work, src, label: "demucs", quiet: false)
      end
      File.file?(drums) ? [src, drums] : nil
    end
    raise "demucs produced no drum stems" if stems.empty?

    hits = stems.flat_map do |(src, drums)|
      found = onsets(drums)
      puts "  #{File.basename(src)}: #{found.length} hits"
      found.each_with_index.filter_map do |t, i|
        measure(drums, t, File.join(work, "#{File.basename(src, '.*')}_#{i}.wav"))
                &.merge(source: File.basename(src))
      end
    end
    raise "no usable hits" if hits.empty?
    puts "  #{hits.length} hits measured"

    FileUtils.mkdir_p(DEST)
    chosen = ROLES.keys.filter_map do |role|
      best = hits.max_by { |h| score(h, role) }
      next unless best && score(best, role) > -99

      # Normalise and trim: the engine expects a one-shot that starts at zero
      # and does not clip, not a slice of a mix.
      out = File.join(DEST, role)
      RadioChop.run!("ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", best[:path],
                     "-af", "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0," \
                            "afade=t=out:st=#{[best[:length] - 0.02, 0.02].max.round(3)}:d=0.02," \
                            "loudnorm=I=-16:TP=-1.5:LRA=6",
                     "-ac", "1", "-ar", RadioChop::SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", out,
                     label: "one-shot")
      { "role" => role, "source" => best[:source], "at_sec" => best[:start],
        "length_sec" => best[:length], "peak" => best[:peak] }
    end

    File.write(MANIFEST, "#{JSON.pretty_generate({
      'version' => 1, 'built_at' => Time.now.utc.iso8601,
      'note' => 'Cut from samples/own/ via demucs; the drum stem kept and everything else discarded.',
      'model' => MODEL, 'roles' => chosen,
    })}\n")
    FileUtils.rm_rf(work)

    puts "\nkit -> #{DEST.sub("#{ROOT}/", '')}"
    chosen.each { |c| puts format("  %-13s %-34s %.2fs at %.1fs", c["role"], c["source"], c["length_sec"], c["at_sec"]) }
    chosen
  end
end
