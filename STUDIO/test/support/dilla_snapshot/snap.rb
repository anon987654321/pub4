# frozen_string_literal: true

# Proof that a restructuring of dilla changed no sound, taken without listening.
#
# A render is mostly a sequence of external commands, and their arguments decide
# what it sounds like. hook.rb, loaded into every Ruby process of a render,
# writes each command down with paths, pids and scratch counters replaced by
# tokens. This script renders a fixed set of configurations at pinned seeds and
# keeps, for each one, that command log, the output's SHA-256, integrated
# loudness and duration, and the loudness of every stem. compare.rb reads two
# snapshots and gives each configuration PASS when the commands match and
# loudness and length agree, or FAIL with the first commands that differ.
#
# From the repository root, on the Ruby dilla runs on:
#
#   ruby STUDIO/test/support/dilla_snapshot/snap.rb before
#   ... make the change ...
#   ruby STUDIO/test/support/dilla_snapshot/snap.rb after
#   ruby STUDIO/test/support/dilla_snapshot/compare.rb before after
#
# To take the baseline from another checkout instead, name its dilla directory
# as the second argument: snap.rb before ../other-checkout/STUDIO/dilla.
#
# Snapshots take minutes and land in STUDIO/dilla/scratch/snapshot/<label>,
# which git ignores; DILLA_SNAPSHOT_DIR puts them elsewhere. SNAP_ONLY takes a
# comma list of configurations, SNAP_BARS the length (4), SNAP_PAR how many
# render at once (3), and SNAP_BED the chopped bed the two sampled live sets
# play, which they need and skip without.
#
# What the evidence covers. The SHA is reported and never decides: dilla renders
# at one seed are not bit-identical (see the note above noise_seed in dilla.rb).
# Sound that a Ruby synth writes straight into a wav -- AnalogSynth, the bed,
# the live player -- reaches the log only as the file it produces, so for those
# the loudness figures are the whole of the proof, and they are coarse.
require "json"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"

module DillaSnapshotRun
  HERE = __dir__
  REPO = File.expand_path("../../../..", HERE)

  # IMPROV_SEED as well as RENDER_SEED: the improvised catalogue draws its keys
  # from its own seed, and left unpinned it changes every run.
  BASE = {
    "RENDER_SEED" => "4242", "IMPROV_SEED" => "4242", "LIVE_SEED" => "4242",
    "BARS" => ENV.fetch("SNAP_BARS", "4"), "DILLA_NO_PROVENANCE" => "1", "DILLA_SH_TIMEOUT" => "900",
  }.freeze

  OUT = "out.wav"
  OUT_MP3 = "out.mp3"

  CONFIGS = {
    "dilla_verified" => [["dilla", OUT], { "TRACK" => "pedal_e_descent" }],
    "dilla_improvised" => [["dilla", OUT], { "TRACK" => "bach_descending_fifths", "IMPROVISED_LEAD" => "1" }],
    "dilla_techno_slot" => [["dilla", OUT], { "TRACK" => "eb_minor_two_chord", "DRUMS" => "1", "DRUM_PRESET" => "industrial_techno",
                                              "POCKET_SET" => "industrial", "ECLECTIC_PERC" => "1", "SNARE_EARLY" => "0", "KICK_LATE" => "0" }],
    "dilla_drums" => [["dilla", OUT], { "TRACK" => "db_major_minor_fall", "DRUMS" => "1" }],
    "hiphop" => [["hiphop", OUT_MP3], {}],
    "industrial" => [["industrial", OUT_MP3], {}],
    "techno" => [["techno", OUT_MP3], {}],
    "analog" => [["analog", OUT_MP3], {}],
    "loose_pocket" => [["loose_pocket", OUT], {}],
    "bed_pass" => [["bed", "render", "seed", "4242", OUT], {}],
    "live_chords" => [%w[live set chord_based_beats], { "LIVE_RENDER_TO" => OUT }],
    "live_sampled" => [%w[live set sampled_based_beats], { "LIVE_RENDER_TO" => OUT, "LIVE_BED" => :bed }],
    "live_pads" => [%w[live set ambient_pads], { "LIVE_RENDER_TO" => OUT, "LIVE_BED" => :bed }],
    "live_synth" => [["live", "1", OUT], {}],
  }.freeze

  # The live player renders all nineteen progressions in Ruby, far longer than
  # the rest together, so it runs only when SNAP_ONLY names it.
  OPT_IN = %w[live_synth].freeze

  LUFS = /Integrated loudness:\s*\n\s*I:\s*(-?[\d.]+)/m

  module_function

  def main(argv)
    label, dilla_dir = argv
    abort "usage: ruby #{File.basename(__FILE__)} <label> [dilla_dir]" if label.to_s.empty?

    dilla_dir = File.expand_path(dilla_dir || File.join(REPO, "STUDIO", "dilla"))
    abort "no dilla.rb in #{dilla_dir}" unless File.file?(File.join(dilla_dir, "dilla.rb"))

    root = File.join(ENV.fetch("DILLA_SNAPSHOT_DIR", File.join(REPO, "STUDIO", "dilla", "scratch", "snapshot")), label)
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root)
    render_all(selected_jobs, dilla_dir, root)
    puts "snapshot #{label}: #{root}"
  end

  def selected_jobs
    only = ENV["SNAP_ONLY"]&.split(",")
    jobs = CONFIGS.select { |name, _| only ? only.include?(name) : !OPT_IN.include?(name) }
    bed = ENV["SNAP_BED"].to_s
    jobs.reject do |name, (_, env)|
      needs_bed = env.value?(:bed) && bed.empty?
      puts format("%-20s skipped: SNAP_BED names no chopped bed", name) if needs_bed
      needs_bed
    end
  end

  # Running the engine rewrites project/session.json and appends to the live
  # journal, and both are tracked. They are put back after every job, under one
  # lock so two jobs cannot restore over each other.
  def render_all(jobs, dilla_dir, root)
    state = %w[session.json liveset.jsonl].to_h { |name| [File.join(dilla_dir, "project", name), nil] }
    state.each_key { |path| state[path] = File.binread(path) if File.file?(path) }
    lock = Mutex.new
    queue = Queue.new
    jobs.each { |job| queue << job }
    queue.close
    workers = Array.new(Integer(ENV.fetch("SNAP_PAR", "3"))) do
      Thread.new do
        while (job = queue.pop)
          render_one(*job, dilla_dir, root)
          lock.synchronize { restore(state) }
        end
      end
    end
    workers.each(&:join)
  ensure
    restore(state) if state
  end

  def restore(state)
    state.each { |path, bytes| File.binwrite(path, bytes) if bytes }
  end

  def render_one(name, (args, env), dilla_dir, root)
    dir = File.join(root, name)
    FileUtils.mkdir_p(File.join(dir, "scratch"))
    log = File.join(dir, "cmds.jsonl")
    place = ->(value) { [OUT, OUT_MP3].include?(value) ? File.join(dir, value) : value }
    env = env.transform_values { |value| value == :bed ? ENV.fetch("SNAP_BED") : place.call(value) }
    full = BASE.merge(env).merge(
      "DILLA_OUTPUT_DIR" => dir, "DILLA_SCRATCH_DIR" => File.join(dir, "scratch"), "DILLA_SNAP_LOG" => log,
      "DILLA_SNAP_REPO" => File.expand_path("../..", dilla_dir), "RUBYOPT" => "-r#{File.join(HERE, 'hook.rb')}"
    )
    started = Time.now
    out, status = Open3.capture2e(full, RbConfig.ruby, File.join(dilla_dir, "dilla.rb"), *args.map(&place), chdir: dilla_dir)
    File.write(File.join(dir, "log.txt"), out)
    commands = File.file?(log) ? File.readlines(log).size : 0
    File.write(File.join(dir, "result.json"), JSON.pretty_generate(measure(dir).merge(
      "exit" => status.exitstatus, "seconds" => (Time.now - started).round(1), "commands" => commands
    )))
    puts format("%-20s exit=%s %6.1fs cmds=%s", name, status.exitstatus, Time.now - started, commands)
  end

  def measure(dir)
    produced = Dir.glob(File.join(dir, "out.{wav,mp3}")).first
    stems = Dir.glob(File.join(dir, "out_stems", "*.wav")).sort.to_h { |wav| [File.basename(wav), lufs(wav)] }
    return { "output_sha" => nil, "lufs" => nil, "duration" => nil, "stems" => stems } unless produced

    duration, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", produced)
    { "output_sha" => Digest::SHA256.file(produced).hexdigest, "lufs" => lufs(produced),
      "duration" => duration.to_f.round(2), "stems" => stems }
  end

  def lufs(path)
    meter, = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-")
    meter[LUFS, 1]&.to_f
  end
end

DillaSnapshotRun.main(ARGV) if __FILE__ == $PROGRAM_NAME
