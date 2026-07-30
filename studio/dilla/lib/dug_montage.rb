# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "crate_dig"

# One continuous source built from every dug side, for feeding the engine as a
# SAMPLE_LOOP.
#
# Each side is a ~3 minute 78rpm transfer, and the first half-minute of one is
# usually lead-in groove, a spoken announcement or an orchestral vamp before
# anything worth chopping. So the window is taken from a fraction into the side
# rather than the head, every side is loudness-matched before it is joined (78
# transfers vary enormously, and a montage of raw levels is unusable), and the
# joins are crossfaded so the seam is a transition rather than a click.
module DugMontage
  OUT = File.join(CrateDig::DUG, "montage.wav")
  RATE = 44_100

  # Where in each side to cut, and how much. A third of the way in clears the
  # intro on nearly everything in the crate without landing in the outro.
  START_FRACTION = 0.34
  WINDOW = 8.0
  CROSSFADE = 0.6

  module_function

  def sides
    CrateDig.manifest["items"]
            .map { |i| i.merge("abs" => File.join(CrateDig::ROOT, i["path"])) }
            .select { |i| File.file?(i["abs"]) }
            .sort_by { |i| [i["seam"].to_s, i["year"].to_i] }
  end

  def duration(path)
    out = `ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 #{path.inspect} 2>/dev/null`
    out.to_f
  end

  # Per-side: seek, window, mono-to-stereo, loudness-match, resample.
  #
  # 78s are mono. Upmixing to stereo here rather than at the join keeps the
  # montage a normal stereo file for everything downstream, and the engine's own
  # width and haas stages have something to work on.
  def slice!(side, index, dir)
    dur = duration(side["abs"])
    return nil if dur < WINDOW * 2

    start = (dur * START_FRACTION).round(2)
    dest = File.join(dir, format("%03d.wav", index))
    ok = system("ffmpeg", "-v", "error", "-y",
                "-ss", start.to_s, "-t", WINDOW.to_s, "-i", side["abs"],
                "-af", "aformat=channel_layouts=stereo,loudnorm=I=-18:TP=-1.5:LRA=11,afade=t=in:d=0.25," \
                       "afade=t=out:st=#{(WINDOW - 0.25).round(2)}:d=0.25",
                "-ar", RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest,
                out: File::NULL, err: File::NULL)
    ok && File.file?(dest) ? dest : nil
  end

  # acrossfade chains pairwise, so N files need N-1 nested filters. Built as a
  # filter_complex rather than the concat demuxer because concat butt-joins, and
  # a butt-join between two 78 transfers is an audible click every eight seconds.
  def join!(parts, out)
    return nil if parts.empty?
    return FileUtils.cp(parts.first, out) if parts.size == 1

    inputs = parts.flat_map { |p| ["-i", p] }
    graph = +""
    prev = "[0:a]"
    parts.each_with_index do |_, i|
      next if i.zero?

      label = i == parts.size - 1 ? "[out]" : "[a#{i}]"
      graph << "#{prev}[#{i}:a]acrossfade=d=#{CROSSFADE}:c1=tri:c2=tri#{label};"
      prev = label
    end
    system("ffmpeg", "-v", "error", "-y", *inputs,
           "-filter_complex", graph.chomp(";"), "-map", "[out]",
           "-ar", RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", out,
           out: File::NULL, err: File::NULL) or return nil
    out
  end

  def build!(out = OUT)
    rows = sides
    raise "nothing dug yet — ruby dilla.rb dig jazz_small 8" if rows.empty?

    dir = File.join(CrateDig::DUG, ".slices")
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)

    parts = rows.each_with_index.filter_map do |side, i|
      slice = slice!(side, i, dir)
      puts format("  %-11s %s  %-38s %s", side["seam"], side["year"],
                  side["title"].to_s[0, 38], slice ? "ok" : "skip (too short)")
      slice
    end

    join!(parts, out) or raise "montage join failed"
    FileUtils.rm_rf(dir)
    puts "montage: #{parts.size} sides, #{duration(out).round(1)}s → #{out.sub("#{CrateDig::ROOT}/", '')}"
    out
  end
end
