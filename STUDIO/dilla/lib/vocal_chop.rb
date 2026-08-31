# frozen_string_literal: true

require "json"
require "fileutils"
# For slug_for: the record's stems live under the directory that slug names, and
# both modules have to agree on how a source path becomes that name.
require_relative "radio_chop"

# The voices we were throwing away.
#
# The chop pipeline runs demucs, keeps bass, guitar, piano and other, and
# discards drums and vocals. Discarding the drums is right -- the whole point is
# a bed to put OUR kit on. Discarding the vocals was not thought about; it fell
# out of the same line.
#
# Donuts is built on vocal chops. Not sung lines: fragments, a syllable or a
# word, used as rhythm and as punctuation, often too short to make out. They are
# the most recognisable thing about the record and we had them separated,
# written to disk, and deleted.
#
# This recovers them. No new separation is needed -- demucs already wrote
# vocals.wav for every thirty-second cut it examined, and those files are still
# in the scratch directory. All that is required is to take the same span the
# loop was taken from, out of the vocal stem instead of the instrumental one.
module VocalChop
  ROOT = File.expand_path("..", __dir__)
  WORK = File.join(ROOT, "scratch", "chop_work")
  MODEL_DIR = "htdemucs_6s"
  MANIFEST = File.join(ROOT, "samples", "chopped", "loops.json")
  SAMPLE_RATE = 44_100

  # Below this the stem holds no voice worth cutting -- just bleed from the
  # instruments the separator could not fully remove. Four of the eight loops
  # measure under -36 dB, which is silence with a rumour in it.
  MIN_VOCAL_DB = -35.0

  module_function

  def loops
    return [] unless File.file?(MANIFEST)

    JSON.parse(File.read(MANIFEST))["loops"] || []
  end

  # Which thirty-second cut of THIS record contains this moment of it.
  #
  # Cut directories are named for where they start and how long they run, both
  # in tenths of a second: cut_001650_0300 begins at 165.0 seconds and lasts 30.
  # The name carries the offset and nothing else, so the record has to come from
  # the directory above it. Searched flat across every record's stems, a lookup
  # by timestamp alone returns whichever record was chopped last and happens to
  # run that long -- one record's voice cut against another record's loop, with
  # nothing in the result saying so.
  def cut_for(second, source)
    slug = RadioChop.slug_for(source.to_s)
    Dir[File.join(WORK, slug, MODEL_DIR, "cut_*")].each do |dir|
      m = File.basename(dir).match(/\Acut_(\d{6})_(\d{4})\z/)
      next unless m

      start = m[1].to_i / 10.0
      span = m[2].to_i / 10.0
      return [dir, second - start] if second >= start && second < start + span
    end
    nil
  end

  # Cuts one loop's worth of voice and writes it beside the loop.
  #
  # Slightly wider than the loop itself: a syllable that begins just before the
  # bar line is exactly the kind of fragment worth having, and a cut made to the
  # instrumental's boundaries would clip its front off.
  LEAD_IN_SEC = 0.25

  def extract!(loop_entry)
    level = loop_entry.dig("dropped_db", "vocals").to_f
    return { slug: loop_entry["slug"], skipped: "quiet (#{level.round(1)} dB)" } if level < MIN_VOCAL_DB

    # No source on the row, no lookup. A row that cannot name its record is one
    # the registry was rebuilt for rather than chopped, and guessing the record
    # is the failure this method exists to prevent.
    source = loop_entry["source"].to_s
    return { slug: loop_entry["slug"], skipped: "row names no source" } if source.empty?

    found = cut_for(loop_entry["source_start_sec"].to_f, source)
    return { slug: loop_entry["slug"], skipped: "no cached cut" } unless found

    dir, offset = found
    stem = File.join(dir, "vocals.wav")
    return { slug: loop_entry["slug"], skipped: "no vocal stem on disk" } unless File.file?(stem)

    dest = File.join(ROOT, File.dirname(loop_entry["path"]), "vocal.wav")
    FileUtils.mkdir_p(File.dirname(dest))
    from = [offset - LEAD_IN_SEC, 0.0].max
    dur = loop_entry["duration_sec"].to_f + LEAD_IN_SEC

    ok = system("ffmpeg", "-nostdin", "-y", "-v", "error",
                "-ss", from.round(3).to_s, "-t", dur.round(3).to_s, "-i", stem,
                # Voices below 120 Hz are separator bleed, not voice. The
                # loudness pass brings eight different broadcasts to one level so
                # a chop from a quiet passage is as usable as one from a loud.
                "-af", "highpass=f=120,loudnorm=I=-18:TP=-2:LRA=7",
                "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest,
                out: File::NULL, err: File::NULL)
    return { slug: loop_entry["slug"], skipped: "ffmpeg failed" } unless ok && File.file?(dest)

    { slug: loop_entry["slug"], path: dest, level: level.round(1), from: from.round(2) }
  end

  def build!
    found = loops
    if found.empty?
      puts "no chopped loops recorded — run `ruby dilla.rb chop` first"
      return []
    end

    results = found.map { |l| extract!(l) }
    kept = results.reject { |r| r[:skipped] }
    puts "vocal chops: #{kept.length} of #{results.length} loops had a voice worth cutting"
    results.each do |r|
      puts(r[:skipped] ? format("  %-20s -- %s", r[:slug], r[:skipped]) : format("  %-20s %5.1f dB  from %.2fs", r[:slug], r[:level], r[:from]))
    end
    kept
  end

  # The vocal chop belonging to a loop, if one was cut.
  def for_loop(loop_path)
    candidate = File.join(File.dirname(loop_path.to_s), "vocal.wav")
    File.file?(candidate) ? candidate : nil
  end
end
