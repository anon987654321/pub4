# frozen_string_literal: true
#
# Building the demo catalogue: ordering, titles, and rejecting dead parts.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# Pad / arp / voicing pools for demo-all — distinct sonic identity per slot
# (stream DNA alone keeps stack_soul+held+jonas_v and reads as "one song").
# Rhodes / Prophet first — glass/vapor/neon are spice, not the main course.
# The pad voices the demo draws from.
#
# This was fourteen slots naming nine voices, and three of them -- stack_rhodes,
# stack_prophet, stack_soul -- filled more than half. Measured across all 86
# tracks, 13 of the 37 defined pad voices were ever selected and 24 never were,
# including every one of pad_dilla, pad_flylo and pad_royksopp: voices named for
# the producers this engine models, which had never been rendered once.
#
# Widened to reach all of them. The repeats that remain are deliberate -- the
# Rhodes and Prophet stacks are the house sound and should still come up most
# often -- but a catalogue of 86 pieces now draws on 37 voices rather than
# leaning on three.
#
# stack_world, stack_giga, stack_yamaha and stack_vintage are layer stacks
# rather than single voices, so they arrive with their own internal blend; they
# are spaced out rather than clustered, because two thick stacks in consecutive
# slots read as one long stack.
DEMO_PAD_ROTATION = %w[
  stack_rhodes stack_prophet pad_dilla stack_soul rhodes
  pad_flylo prophet stack_glass rhodes_solo stack_vapor
  stack_rhodes pad_madlib moog stack_prophet vintage
  stack_soul pad_royksopp blend stack_yamaha glass
  stack_rhodes fm stack_vintage prophet nylon_soul
  stack_prophet vapor stack_giga crystal stack_fm_epiano
  stack_soul yamaha stack_world ice giga_fm
  stack_rhodes neon supersaw_bed stack_prophet orchestral
  pulse stack_soul vintage_choir stack_rhodes
  harmonica stack_vapor accordion stack_glass yamaha_solo
  stack_soul giga_stack stack_prophet texture
].freeze
DEMO_PAD_ARP_ROTATION = %w[held held wash shimmer held wash figure held].freeze
DEMO_VOICING_ROTATION = %w[
  rootless spread drop2 quartal bill_evans kenny_barron so_what cluster rootless
].freeze

# Every named piece dilla can render, not just the broadcast rotation.
#
# STREAM_ROTATION is the 69-track stream order. It misses two catalogues:
# GENERATED_STYLES (11 generative modes — major_third_cycle_full, negative_harmony,
# tritone_sub … resolved by dilla_progression rather than a CHORD_PROGRESSIONS
# lookup) and four ARTIST_VERIFIED_PROGRESSIONS turnarounds the rotation never
# reaches. Union is 84, and that is what the demo should represent — a demo of
# the stream order alone understates what the engine knows.
#
# DEMO_CATALOG=stream narrows back to the broadcast rotation.
# Every table that decides what the engine can reach, and what it leaves out.
#
# A capability nothing selects is a capability nothing tests, which is how a pad
# patch carried an out-of-range filter value for months without anyone hearing
# it: the voice was defined, no rotation named it, and the broken chain never
# ran. The audit lists what is defined against what is reachable, so that gap is
# a number somebody sees rather than something discovered by ear.
#
# Deliberately reports rather than enforces. A few entries SHOULD be
# unreachable -- a hard-trap kit has no place in this catalogue -- and a check
# that fails the build on those would just get switched off. A number that moves
# in the wrong direction is the useful signal.
def capability_surfaces
  {
    "drum presets" => [DillaLofiMachine::DRUM_PRESETS.keys, drum_rotation_full.map { |d| d[:preset] }],
    "pad voices" => [PAD_VOICE_PRESETS.keys + PAD_LAYER_STACKS.keys,
                     DEMO_PAD_ROTATION + STREAM_PAD_VOICE_ROTATION],
    "chord progressions" => [CHORD_PROGRESSIONS.keys, demo_all_order],
    "lead voices" => [(defined?(LEAD_VOICE_PRESETS) ? LEAD_VOICE_PRESETS.keys : []),
                      STREAM_LEAD_VOICE_ROTATION],
    # LEAD_ARP_PRESETS, not ARP_PATTERN_BUILDERS. The rotation holds arp *modes*
    # (flylo_spiral, soul_wash) and the builders are the low-level figures those
    # modes draw from (up, euclidean, rosary) -- two vocabularies that share no
    # key, so the old pairing reported 29 of 29 unreachable no matter what was
    # rotated. The builders are reached at render time by arp_styles unions and
    # rng sampling, which no rotation list can show.
    "lead arp modes" => [(defined?(LEAD_ARP_PRESETS) ? LEAD_ARP_PRESETS.keys : []),
                         STREAM_LEAD_ARP_ROTATION],
    "external kits" => [(defined?(EXTERNAL_DRUM_KITS) ? EXTERNAL_DRUM_KITS : []),
                        drum_rotation_full.map { |d| d[:kit] }],
    "sample loops" => [TRACK_SAMPLE_LOOPS.keys, demo_all_order],
  }
end

def capability_audit!
  total_missing = 0
  puts format("  %-22s %8s %10s %6s", "surface", "defined", "reachable", "gap")
  capability_surfaces.each do |label, (defined_keys, reachable_keys)|
    d = defined_keys.map(&:to_s).uniq
    r = reachable_keys.map(&:to_s).uniq
    missing = (d - r).sort
    total_missing += missing.length
    puts format("  %-22s %8d %10d %6d", label, d.length, d.length - missing.length, missing.length)
    puts "      #{missing.first(24).join(' ')}#{missing.length > 24 ? " …+#{missing.length - 24}" : ''}" unless missing.empty?
  end
  puts
  puts total_missing.zero? ? "  every defined capability is reachable" : "  #{total_missing} unreachable"
  true
end

def demo_all_order
  # An explicit list wins over every other rule here — it is how demo-quick asks
  # for a sample of the catalogue, and an operator naming tracks means it.
  named = ENV["DEMO_TRACKS"].to_s.split(",").map(&:strip).reject(&:empty?)
  return named.map(&:to_sym) unless named.empty?

  locked = stream_track_order
  # STREAM_LOCK pinned a single track — honour it rather than expanding.
  return locked if locked.length <= 1
  # DEMO_CATALOG=stream reproduces what the broadcast would actually play,
  # including any DILLA_PROGRESSIONS_ONLY filtering.
  return locked if ENV["DEMO_CATALOG"].to_s.strip.downcase == "stream"

  # Deliberately STREAM_TRACKS and not stream_track_order: the latter runs
  # through stream_track_pool, which DILLA_PROGRESSIONS_ONLY narrows to the
  # Dilla-produced handful. That is right for a broadcast and wrong for a
  # catalogue demo, which should show everything the engine knows regardless
  # of what the stream is currently filtered to.
  curated = demo_curated_order

  # ...and then everything else, which is most of it.
  #
  # The note above says this list "should show everything the engine knows", and
  # it did not. Those three sources union to 86 entries. CHORD_PROGRESSIONS holds
  # 250. Measured, 209 progressions could never appear in a catalogue demo --
  # gospel_walk_up, neapolitan_door, lament_ground, hexatonic_pole_shiver, every
  # eight_bar_* arc, both whole_tone entries. The engine knew them and no demo
  # ever played one, which is a large part of why eight tracks drawn from the
  # same 41 sounded like each other.
  #
  # Curated first, so the order of the front of the catalogue is unchanged and
  # DEMO_TRACKS/demo-quick still sample the good stuff first. The tail is sorted
  # rather than shuffled: a catalogue should be in a stable order so a track you
  # heard yesterday is in the same place today.
  #
  # DEMO_CURATED_ONLY=1 restores the old 86 for anyone who wants just those.
  return curated if ENV["DEMO_CURATED_ONLY"] == "1"

  # The sampled beds go in too, and they are the reason this matters.
  #
  # TRACK_SAMPLE_LOOPS entries are track names: name one as TRACK and the loop
  # plays underneath the arrangement on its own bus. All twelve were unreachable
  # from any demo -- the four hand-cut records and the eight cut from the Sheger
  # broadcast by `chop`, which was built this session precisely so the engine
  # could make beats out of them. It could, and no demo ever did.
  loops = TRACK_SAMPLE_LOOPS.keys.map(&:to_sym).sort
  tail = (CHORD_PROGRESSIONS.keys.map(&:to_sym).sort - curated - loops)
  (curated + loops + tail).uniq
end

# The curated head of the catalogue, on its own. Named because three places want
# it: demo_all_order builds from it, DEMO_CURATED_ONLY returns it, and the help
# text has to be able to say how big it is without guessing.
def demo_curated_order
  base = STREAM_TRACKS.map(&:to_sym)
  extra = GENERATED_STYLES.map(&:to_sym) + ARTIST_VERIFIED_PROGRESSIONS.keys.map(&:to_sym)
  (base + extra).uniq
end

# Catalogue sizes, derived rather than written down.
#
# Both counts in the help text were stale, and not by a little: it advertised
# "84 named pieces" for a default catalogue that had grown to 307, and a
# "69-track stream rotation" that was 205. The numbers were right when they were
# typed and nothing recomputed them when the pools grew -- the same shape as
# every other hardcoded count in this tree.
#
# It is worth deriving because the number IS the cost. demo-all at 70s a track is
# 1.7 hours at 86 and 6 hours at 307, and an operator choosing between them off
# the help text was choosing off numbers four times wrong.
#
# The :all and :curated counts read no ENV, deliberately. demo_all_order honours
# DEMO_TRACKS/DEMO_CATALOG/DEMO_CURATED_ONLY, which is right for a render and
# wrong for a help screen -- `DEMO_CATALOG=stream ruby dilla.rb help` should
# still report what the default catalogue costs. :stream goes through
# stream_track_order and therefore does follow STREAM_LOCK and any progression
# filter, because that is the honest answer to "what would DEMO_CATALOG=stream
# render for me", which is the question the help line is answering.
def demo_catalog_sizes
  curated = demo_curated_order
  loops = TRACK_SAMPLE_LOOPS.keys.map(&:to_sym)
  tail = CHORD_PROGRESSIONS.keys.map(&:to_sym) - curated - loops
  {
    all: (curated + loops + tail).uniq.length,
    curated: curated.length,
    stream: stream_track_order.length,
  }
end

# The mp3 is the artifact worth tracking. A full-catalogue WAV runs to hundreds
# of megabytes and git keeps it forever; at 192kbps the same audio is a few
# megabytes and still reviewable. The WAV stays on disk as the working master
# and is not tracked.
#
# DEMO_MP3=0 skips the encode; DEMO_MP3_BITRATE overrides 128k.
def demo_encode_mp3(wav)
  return nil if ENV.fetch("DEMO_MP3", "1") == "0"
  return nil unless File.file?(wav)

  mp3 = wav.sub(/\.wav\z/i, "") + ".mp3"
  # 128k, not 192k, because demo.mp3 is committed and GitHub's hard per-file push
  # limit is 100 MB with no LFS available here. The curated 86-track catalogue is
  # 71 minutes, which is 102 MB at 192k -- over the limit, rejected at push, and
  # discovered only after an hour of rendering. It is 68 MB at 128k.
  #
  # This is the one encode setting in the file chosen by a constraint outside the
  # audio. Raise it for a WAV you are keeping locally, not for the tracked demo,
  # and re-measure if the catalogue or the bar count grows.
  bitrate = ENV.fetch("DEMO_MP3_BITRATE", "128k")
  begin
    sh! "ffmpeg", "-y", "-i", wav, "-codec:a", "libmp3lame", "-b:a", bitrate, mp3
  rescue StandardError => e
    dmesg_warn("demo mp3 encode failed: #{e.message}")
    return nil
  end
  return nil unless File.file?(mp3) && File.size(mp3) > 10_000

  mp3
end

# Render every catalogue progression into one demo.wav (resumable), then encode
# the tracked demo.mp3 beside it.
# Usage: ruby dilla.rb demo-all [bars] [out.wav]
#   DEMO_FORCE=1 re-render even if part exists
#   DEMO_CREATIVE=1 (default) rotate pads/leads/MIDI/analog + sparse rap so chords read
#   DEMO_TRACK_TIMEOUT=300 max seconds per track (creative stacks need headroom)
#   DEMO_RAP_EVERY=4 rap only every Nth track (0 = never; 1 = always)
#   DEMO_CATALOG=stream restrict to the stream rotation; DEMO_CURATED_ONLY=1 the
#     curated head only. Sizes are in demo_catalog_sizes -- do not write them here,
#     the two that used to live in this file drifted to 4x wrong.
#   DEMO_MP3=0 skip the mp3; DEMO_MP3_BITRATE=192k
# One file per track instead of one 48-minute concat.
#
# The parts already existed -- demo_all has always rendered each track separately
# and then glued them together -- but they landed in scratch/ under a name nobody
# would look for, as WAV, and DEMO_FORCE deleted them. Culling a catalogue means
# playing a track, deciding, and deleting the file, and that needs the files to
# be findable, small, and named after the track.
#
# So: demos/NN_slug.mp3, kept, resumable, no concat. Delete the ones that miss
# and re-run -- the survivors are skipped and only the gaps re-render.
def demo_each? = ENV["DEMO_EACH"] == "1"

# The dilla root, beside dilla.rb, not a subfolder. Same argument the scratch/
# note in .gitignore already makes: generated audio should be findable by anyone
# looking at the tree. Only the mp3s land here -- order.txt, catalog.txt and the
# run log stay in scratch, because those are bookkeeping and this directory is
# meant to be a listening queue.
DEMO_EACH_DIR = ROOT
DEMO_EACH_MANIFEST = File.join(ROOT, "demo_manifest.tsv")

# Each track gets its own pinned seed, written into the manifest beside it.
#
# This is what makes "weed out the bad seeds" a real operation rather than a
# figure of speech: a track you like has a number next to it, and a track you
# do not can be re-rolled by bumping only that number. DEMO_SEED sets the base.
#
# Read the caveat in the manifest header before trusting a recorded seed to
# reproduce a take. Pinning is necessary here and is not yet sufficient: two
# renders with RENDER_SEED fixed are still not bit-identical, so a seed narrows
# a take down rather than reconstructing it.
def demo_each_seed(idx) = (ENV["DEMO_SEED"] || "4242").to_i + idx

# Our own titles.
#
# The internal names describe the harmony -- two_chord_hypnosis, dorian_iv_loop
# -- and a fair few were taken from the records the progression was studied
# from. Those are somebody else's titles on our tracks, so the files that come
# out of here get names of their own.
#
# Deterministic, not random at render time: the same track gets the same title
# every run, so a file you kept still matches its row in the manifest after a
# re-render. The manifest carries both names, because the internal slug is still
# how you render the thing again.
DEMO_TITLE_FIRST = %w[
  amber ash blue brass cedar clay copper dusk ember fern flint glass grain
  gravel harbour hollow indigo iron ivory lantern linen marrow mercury moss
  nickel ochre onyx paper pewter quartz river rust saffron salt shale silt
  slate smoke solder stone tallow tide tin umber velvet vellum willow
].freeze
DEMO_TITLE_SECOND = %w[
  arc bloom braid channel circuit corridor current drift ferry field figure
  gate ghost harvest hinge hour ladder lantern letter margin meridian mile
  motion orbit parlour passage pattern pier quarter relay ribbon room season
  shelf signal span station stitch switch table thread tower turn valley
  wander watch weather window
].freeze

# Is this slot a techno track or a hip-hop one?
#
# The engine has two renderers now and a demo that only ever shows one of them
# is only half a demo. Which slot gets which is decided by a coin flip -- but a
# SEEDED one, keyed on the track name and the demo seed, so the same catalogue
# comes out the same way twice and a file you kept still matches its manifest
# row. Random at render time would mean re-running the demo silently reshuffled
# what you had already listened to.
#
# DEMO_TECHNO_SHARE is the proportion, defaulting to a third: enough that a run
# of eight lands two or three of them, few enough that the demo still reads as a
# catalogue of the progressions rather than a techno set with interruptions.
# 0 renders everything as hip-hop, 1 as techno.
def demo_techno_share = ENV.fetch("DEMO_TECHNO_SHARE", "0.34").to_f.clamp(0.0, 1.0)

# Does slot idx carry a rapper?
#
# DEMO_RAP_EVERY only reaches "every slot" (1) or "every other" (2) and has
# nothing between them, so a demo that wants a rapper on most tracks and the
# harmony naked on a few could not be asked for at all.
# DEMO_INSTRUMENTAL_EVERY holds every Nth slot back on top of whatever
# rap_every decided.
#
# Off by default (0), so no existing demo changes. The instrumental lands at the
# END of each group of N, not the start, so slot 0 still opens with a voice.
def demo_rap_slot?(idx, rap_every)
  return false unless rap_every.positive?
  return false unless (idx % rap_every).zero?

  every = ENV.fetch("DEMO_INSTRUMENTAL_EVERY", "0").to_i
  return true unless every.positive?

  (idx % every) != every - 1
end

def demo_techno_slot?(idx, slug)
  share = demo_techno_share
  return false if share <= 0.0

  # A track carrying a sampled bed is a techno slot only when techno can carry
  # the bed.
  #
  # render_hate_techno used to build its arrangement from scratch and never call
  # sample_loop_for, so reassigning one of these handed back a techno piece with
  # the record silently absent -- at the 0.34 default, a third of every hand-cut
  # and chopped loop, with nothing in the log to distinguish a dropped sample
  # from a played one. It now takes the bed as a layer under TECHNO_HARMONY, so
  # the exemption is scoped to the case that still loses it rather than left
  # standing as a permanent rule. That is the whole point: a sampled record
  # SHOULD be able to become a techno track.
  #
  # Checked before the share >= 1.0 shortcut, so DEMO_TECHNO_SHARE=1 still means
  # "every slot that CAN be techno", not "lose every sample".
  unless techno_harmony_enabled?
    key = slug.to_s.downcase.tr("-", "_").to_sym
    return false if TRACK_SAMPLE_LOOPS.key?(TRACK_SAMPLE_LOOP_ALIASES.fetch(key, key))
  end

  return true if share >= 1.0

  seed = stable_hash("techno:#{slug}") + (ENV["DEMO_SEED"] || "4242").to_i + idx
  (seed % 1000) < (share * 1000).round
end

def demo_title(slug, idx)
  # Two independently salted hashes, not one hash divided.
  #
  # Taking the second word from `seed / FIRST.length` ties it to the first: djb2
  # over near-identical inputs returns near-identical values, so a run of slugs
  # that differ by one character lands in the same quotient bucket. Rendering
  # the eight Sheger chops produced shale_mile, slate_mile, solder_mile,
  # tallow_mile, tin_mile, velvet_mile, willow_mile -- seven titles, one word.
  # Salting the two draws differently decorrelates them.
  base = "#{slug}:#{ENV['DEMO_SEED'] || '4242'}:#{idx}"
  first = DEMO_TITLE_FIRST[stable_hash("first:#{base}") % DEMO_TITLE_FIRST.length]
  second = DEMO_TITLE_SECOND[stable_hash("second:#{base}") % DEMO_TITLE_SECOND.length]
  "#{first}_#{second}"
end

# True when every part carries the same codec, which is the one thing the concat
# demuxer requires and the one thing it will not check. It probes the FIRST input
# only and assumes the rest match, so a single odd part is copied through as if it
# were the format of part 1.
# Level every part to one target before the demo is assembled. On by default.
#
# The demo was not loud in the wrong places, it was TWO RECORDS. Measured across
# 42 rendered parts: the hip-hop slots sit at -18.7 LUFS with about 9 LU of range
# and -8 dBFS peaks, and the techno slots at -12.5 LUFS with 24 LU of range and
# -2.2 dBFS peaks. 6.2 dB apart, alternating, for 71 minutes. The hip-hop tracks
# were already tightly levelled against each other -- the entire spread was that
# one seam.
#
# DEMO_ALBUM_NORM does not fix this and cannot. It normalises the finished
# concatenation, which moves the whole thing together and preserves every gap
# inside it. That is the right behaviour for an album, where the quiet track is
# quiet on purpose, and the wrong layer entirely for a catalogue demo where the
# difference between two tracks is an artefact of which renderer drew them.
# Levelling has to happen per part, before they are joined.
#
# normalize_track_loudness! is reused rather than reinvented: its LRA=11 ceiling
# is the half that matters most here, because the techno slots' problem is as
# much the 24 LU range as the level, and a gain change alone would leave that.
def demo_level_parts?
  ENV.fetch("DEMO_LEVEL", "1") != "0"
end

# Normalised copies, in a temp directory -- the cached parts in out_dir are never
# touched. Two reasons, and the second is the one that bites: demo-all is
# resumable, so mutating parts in place would re-level an already-levelled part
# on every resume, and levelling is not quite idempotent (each pass re-measures
# and re-limits). Copies also mean a failed run leaves the expensive renders
# intact.
#
# Decoding each part separately is what makes this safe for mixed codecs too, so
# this path needs no uniformity check -- it IS the uniformity fix.
# Measure what "ok" never looked at: is there audio in the file, and is it as
# long as its neighbours. Returns the suspects; the caller decides.
#
# Both thresholds are relative to the median of the parts themselves. An absolute
# floor would be wrong twice over -- it would fire on a demo that is quiet by
# choice, and it would miss a whole render that came out uniformly thin. What is
# never intentional is one track sitting 25 dB under the ones beside it.
#
# Median and not mean, because the failure this exists to catch put 28 silent
# parts into 86. A mean would have been dragged down toward them; the median of
# that set was still a healthy -21 dB.
def demo_suspect_parts(parts)
  measured = parts.filter_map do |p|
    next unless File.file?(p)
    out = Open3.capture2e("ffmpeg", "-hide_banner", "-i", p, "-af",
                          "astats=metadata=1:reset=0", "-f", "null", "-").first
    # astats prints "-inf" for a digitally silent file, and the obvious
    # /(-?[\d.]+)/ does not match it -- so the first version of this returned nil
    # there and `next if rms.nil?` dropped the file from the set entirely. A
    # check for silence that skips anything perfectly silent. Caught by feeding
    # it an anullsrc probe, which it passed clean.
    raw = out[/RMS level dB:\s*(-?(?:[\d.]+|inf))/, 1]
    next if raw.nil?
    rms = raw == "-inf" ? -120.0 : raw.to_f
    dur = Open3.capture2e("ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", p).first.to_f
    { path: p, rms: rms, dur: dur }
  end
  return [] if measured.length < 3

  mid = lambda { |vals| s = vals.sort; s[s.length / 2] }
  med_rms = mid.call(measured.map { |m| m[:rms] })
  med_dur = mid.call(measured.map { |m| m[:dur] })
  measured.filter_map do |m|
    quiet = m[:rms] < med_rms - 20
    short = med_dur.positive? && m[:dur] < med_dur * 0.4
    next unless quiet || short
    reason = [quiet ? "#{m[:rms].round(1)}dB vs median #{med_rms.round(1)}" : nil,
              short ? "#{m[:dur].round(1)}s vs median #{med_dur.round(1)}" : nil].compact.join(", ")
    { path: m[:path], reason: reason }
  end
end

# Absolute, not relative: a file whose peak never leaves the noise floor carries
# no signal at any playback level, so no demo can want it. -70 dBFS peak is two
# orders of magnitude below the quietest real part measured here (-7.5 dB peak
# on a retry-minimal render) and comfortably above a true digital zero's -91.0,
# so it separates dead from merely quiet without judgement.
DEAD_PART_PEAK_DBFS = -70.0

def demo_part_dead?(path)
  out, status = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-i", path,
                                "-af", "volumedetect", "-f", "null", "-")
  # A file ffmpeg cannot measure is not provably dead, and this runs after hours
  # of rendering: keep it and let demo_report_suspect_parts name it instead.
  return false unless status.success?

  peak = out[/max_volume:\s*(-?\d+(?:\.\d+)?)\s*dB/, 1]
  return false if peak.nil?

  peak.to_f <= DEAD_PART_PEAK_DBFS
end

def demo_reject_dead_parts(parts)
  dead, alive = parts.partition { |p| demo_part_dead?(p) }
  return parts if dead.empty?

  dmesg_warn("join: dropping #{dead.length} dead part(s) — no signal above #{DEAD_PART_PEAK_DBFS} dBFS")
  dead.each { |p| dmesg_warn("  #{File.basename(p)}") }
  # Never hand back an empty list: joining nothing writes a zero-length file that
  # every downstream step accepts. If they are all dead, that is the fault, and
  # the caller should fail loudly on the join rather than silently on the output.
  alive.empty? ? parts : alive
end

# Name them in the log and in the closing summary. Deliberately a warning and not
# an abort: this runs after hours of rendering, and killing the run would throw
# away 80 good parts to punish six bad ones. Deleting the named files and
# re-running fills exactly those gaps, which is what the resume is for.
def demo_report_suspect_parts(parts)
  suspects = demo_suspect_parts(parts)
  return suspects if suspects.empty?

  dmesg_warn("verify: #{suspects.length}/#{parts.length} parts look wrong — delete these and re-run to refill")
  suspects.each { |s| dmesg_warn("  #{File.basename(s[:path])}: #{s[:reason]}") }
  suspects
end

def demo_parts_uniform?(parts)
  codecs = parts.map do |p|
    out, status = Open3.capture2e("ffprobe", "-v", "error", "-select_streams", "a:0",
                                  "-show_entries", "stream=codec_name",
                                  "-of", "default=nw=1:nk=1", p)
    status.success? ? out.strip : "unknown"
  end
  codecs.uniq.length <= 1
end

# Join the parts into one wav. `-c copy` is worth keeping -- it is near-instant on
# 84 tracks where a re-encode is minutes -- but it cannot be trusted on its own,
# because on a codec mismatch it does not fail. It writes the wrong stream into a
# WAV container and exits 0, so the rescue that used to guard this never fired and
# the demo shipped a file that opens nowhere. Check the parts first, then copy.
# Crossfade the parts into one piece rather than butting them together.
#
# The concat demuxer joins sample to sample. That is right for one recording cut
# into parts and wrong for eighty-six separate pieces in eighty-six keys: every
# join is a hard edge, and a demo meant to be listened through end to end reads
# as a folder of clips instead.
#
# This is album_stitch's graph applied to the demo's parts -- the same 1.5s
# tri/tri curves and the same limiter ceiling, for the same reason. A crossfade
# sums two tracks, so the overlap peaks above whatever either part reached alone.
#
# DEMO_CROSSFADE=0 restores the butt-splice.
def demo_crossfade_parts!(parts, out, seconds)
  graph = +""
  previous = "[0:a]"
  (1...parts.length).each do |i|
    label = i == parts.length - 1 ? "[x]" : "[a#{i}]"
    graph << "#{previous}[#{i}:a]acrossfade=d=#{seconds}:c1=tri:c2=tri#{label};"
    previous = label
  end
  ceiling = 10**((ALBUM_TARGET_TP - ALBUM_ENCODER_HEADROOM) / 20.0)
  graph << "[x]alimiter=limit=#{ceiling}:level=disabled[out]"

  # A script file, not an argument: eighty-five chained filters is tens of
  # kilobytes of graph, and it is the one argument that grows with the catalogue.
  script = File.join(Dir.tmpdir, "demo_graph_#{Process.pid}.txt")
  File.write(script, graph)
  begin
    sh! "ffmpeg", "-y", "-loglevel", "error", *parts.flat_map { |p| ["-i", p] },
        "-filter_complex_script", script, "-map", "[out]",
        "-c:a", "pcm_s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "2", out
  ensure
    FileUtils.rm_f(script)
  end
  dmesg("join: #{parts.length} parts, #{seconds}s crossfades", unit: "demo0", parent: "dilla0")
  DillaProvenance.record_assembly!(
    out, parts:,
    how: "#{seconds}s tri crossfades, limited to #{(ALBUM_TARGET_TP - ALBUM_ENCODER_HEADROOM).round(2)} dBTP",
  )
  out
end

def demo_join_parts!(parts, list, out)
  level = demo_level_parts?
  xfade = ENV.fetch("DEMO_CROSSFADE", ALBUM_XFADE.to_s).to_f
  return demo_crossfade_parts!(parts, out, xfade) if xfade.positive? && parts.length > 1

  # The fast path, and the only one that avoids touching 86 files: hand the
  # caller's list straight to the concat demuxer and copy. It is legal only when
  # nothing needs per-part work AND the parts already agree on a codec, because
  # the demuxer probes part 1 and applies that decoder to every later part --
  # one mp3 among the wavs and it copies mp3 packets into a WAV container and
  # exits 0. Both conditions, or decode each part on its own below.
  if !level && demo_parts_uniform?(parts)
    sh! "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", out
    DillaProvenance.record_assembly!(out, parts:, how: "concat demuxer, stream copy, no levelling")
    return out
  end

  # One body for both remaining reasons to walk the parts -- levelling them, and
  # rescuing a codec mismatch -- because they were the same fifteen lines twice,
  # differing by the normalize call. Re-encoding through the concat demuxer does
  # NOT rescue a mismatch, which is the trap worth naming: the demuxer still
  # probes part 1, so a pcm part read as mp3 yields "Header missing" per packet
  # and silence where the audio was. Measured, not assumed.
  target = ENV.fetch("DEMO_LEVEL_LUFS", "-16.5").to_f
  if level
    dmesg("level: #{parts.length} parts -> #{target} LUFS", unit: "demo0", parent: "dilla0")
  else
    dmesg_warn("concat: parts are not one codec, decoding #{parts.length} before joining")
  end
  Dir.mktmpdir("dilla_join") do |tmp_dir|
    prepared = parts.each_with_index.map do |p, i|
      dst = File.join(tmp_dir, format("%03d.wav", i))
      sh! "ffmpeg", "-y", "-loglevel", "error", "-i", p,
          "-c:a", "pcm_s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "2", dst
      normalize_track_loudness!(dst, lufs: target) if level
      dst
    end
    joined = File.join(tmp_dir, "concat.txt")
    File.write(joined, prepared.map { |p| "file '#{p}'" }.join("\n") + "\n")
    sh! "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", joined, "-c", "copy", out
  end
  # The ORIGINAL parts, not the levelled temporaries -- those live in a tmpdir
  # that is gone by the time anyone reads this, and naming them would record a
  # tracklist of paths that never existed outside one process. The levelling is
  # in `how` instead, which is the part worth knowing.
  DillaProvenance.record_assembly!(
    out, parts:,
    how: level ? "decoded per part, levelled to #{target} LUFS, then concat" : "decoded per part, then concat"
  )
  out
end
