# frozen_string_literal: true
#
# demo-all: render every style and join the parts.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# One demo-all at a time, for the same reason stream() takes a lock.
#
# Two of them share scratch/all_tracks_demo and they do not share it politely.
# Each part is written through an intermediate and renamed into place, so while
# one run is rewriting a part the other sees that path not exist -- and the join
# reads all 86 paths at once, so it only has to lose the race on one of them to
# die after hours of rendering. That happened twice tonight. It presents as a
# file that "vanished": ffmpeg reports no such file, and by the time anyone looks
# the part is back, because the other process finished its rename.
#
# It also produces the subtler version. A part read while it is half-written is a
# valid, playable, TRUNCATED wav -- one came out at 20.9s against its neighbours'
# 53.0s and passed every check, because `ok` only asks whether the file is bigger
# than 50 kB.
#
# Same shape as acquire_stream_lock!, and mirrored deliberately rather than
# generalised: the two locks guard different directories and there is no third
# caller to justify the abstraction yet.
DEMO_LOCK_PATH = scratch_path("dilla_demo.lock").freeze

def acquire_demo_lock!
  if File.exist?(DEMO_LOCK_PATH)
    holder = File.read(DEMO_LOCK_PATH).strip.to_i
    if holder.positive?
      begin
        Process.kill(0, holder)
        dmesg_warn("demo-all already running as pid #{holder} — exit (DEMO_NO_LOCK=1 to override)")
        exit 0
      rescue Errno::ESRCH
        FileUtils.rm_f(DEMO_LOCK_PATH)
      end
    end
  end
  File.write(DEMO_LOCK_PATH, Process.pid.to_s)
  at_exit do
    FileUtils.rm_f(DEMO_LOCK_PATH) if File.exist?(DEMO_LOCK_PATH) &&
                                      File.read(DEMO_LOCK_PATH).strip.to_i == Process.pid
  rescue StandardError
    nil
  end
end

def demo_all(bars_count = 12, destination = nil)
  acquire_demo_lock! unless ENV["DEMO_NO_LOCK"] == "1"
  bars_count = bars_count.to_i
  bars_count = 12 unless bars_count.positive?
  dest = destination.to_s
  dest = File.join(ROOT, "demo.wav") if dest.empty?
  # each-mode writes its mp3s to the dilla root and its transient wav straight
  # into SCRATCH_DIR, so it creates no directory of its own.
  out_dir = demo_each? ? SCRATCH_DIR : File.join(SCRATCH_DIR, "all_tracks_demo")
  FileUtils.mkdir_p(out_dir)
  log_path = File.join(out_dir, "demo_all.log")
  catalog_path = File.join(out_dir, "catalog.txt")
  track_timeout = (ENV["DEMO_TRACK_TIMEOUT"] || ENV["STREAM_TRACK_TIMEOUT"] || "300").to_i
  track_timeout = 300 unless track_timeout.positive?
  force = ENV["DEMO_FORCE"] == "1"
  creative = ENV.fetch("DEMO_CREATIVE", "1") != "0"
  # No vocals in the demo. The demo exists to show the engine's harmony, groove
  # and tone across 84 pieces; a voice on top is the loudest thing in the mix and
  # it masks exactly what is being demonstrated. Set DEMO_RAP_EVERY=4 to put the
  # old every-fourth-track rap back.
  # Every other slot carries a rapper, by default.
  #
  # This defaulted to 0 -- no vocals anywhere -- on the reasoning that a voice is
  # the loudest thing in the mix and masks the harmony the demo exists to show.
  # That is true of a demo for an engine and wrong for a demo of a hiphop
  # engine: the tool makes records for rappers, and a beat tape with no rapper
  # on it does not demonstrate the thing it is for. Operator direction
  # 2026-08-09: "make it include rap vocals".
  #
  # 2, not 1: alternating slots still leave every other track instrumental, so
  # the harmony is audible on its own somewhere in the run.
  rap_every = (ENV["DEMO_RAP_EVERY"] || "2").to_i

# The lead stack is a sprinkle, not a layer.
#
# VOICE_STACK renders every lead twice, and on a 451-part demo that measured
# 0.54 parts/min against 2.31 without it -- 4.3x, or thirteen hours against
# three. Paying that on every single track also misrepresents the feature:
# the operator's word for it was "sprinkled on top", and a doubling that is
# always present is not a sprinkle, it is the sound.
#
# Every third track, so it is heard as a colour that comes and goes and the
# demo still finishes overnight. DEMO_VOICE_STACK_EVERY=1 puts it on all of
# them, 0 turns it off entirely.
voice_stack_every = (ENV["DEMO_VOICE_STACK_EVERY"] || "3").to_i

  # Captured ONCE, before the loop, because the loop assigns ENV["RAP_VOCAL"]
  # on every iteration -- reading it inside would return the previous slot's
  # value ("0" on most of them) instead of what the operator asked for.
  #
  # Comma-separated, so a demo can rotate rappers. A single voice repeated over
  # twenty-six slots is its own kind of monotony, and the catalogue has six.
  demo_rap_slugs = ENV["RAP_VOCAL"].to_s.split(",").map(&:strip)
                                    .reject { |s| s.empty? || s == "0" }
  demo_rap_slugs = DEMO_RAP_ROTATION.dup if demo_rap_slugs.empty?
  # Never ship a slug the catalogue cannot resolve: rap_vocal_resolve returns
  # nil and the slot renders instrumental while the log still says rap=<slug>,
  # which reads as the vocal having played.
  demo_rap_slugs = demo_rap_slugs.select { |s| rap_vocal_resolve(s) }
  demo_rap_slugs = [RAP_VOCAL_SOURCE] if demo_rap_slugs.empty?

  # A demo shows the house sound, not the whole kit shelf. Set
  # DRUM_ROTATE_CURATED=0 to walk all 62 presets again.
  ENV["DRUM_ROTATE_CURATED"] ||= "1"
  ENV["SPEAK"] ||= "0"
  ENV["STREAM_CONTINUOUS"] = "0"
  ENV["DILLA_STREAMING"] = "1"
  ENV["STREAM_LEAD_MIDI_RICH"] = "1"

  # Steady mode: hold the synthesis still so the WRITING is what varies.
  #
  # demo-all was built to show range, and it does that by moving every knob it
  # has: STREAM_ROTATE_LEAD and STREAM_ROTATE_SYNTH give each track a different
  # lead voice and arp mode, then SYNTH_MORPH / LEAD_MORPH / SYNTH_CYCLE move
  # the voice again WITHIN the track, and creative mode adds EXPERIMENTAL_LEADS,
  # STREAM_CREATIVE_FREEDOM and STREAM_ANALOG_WILD on top. Five consecutive
  # tracks came out as
  #
  #   lead=soul_prophet/wonky_spiral  lead=wonky/neo_quartal  lead=moog/soul_wash
  #   lead=prophet/moog_funk          lead=neo_pluck/prophet_glass
  #
  # -- a different instrument playing a different arp every time, each morphing
  # as it goes. That is a showcase of the synthesis, and it is the wrong
  # instrument for judging material: everything sounds restless, and a
  # progression cannot be blamed or credited for what the randomiser did over
  # it. The tempo was not the problem -- those takes measured 82-89 BPM, inside
  # the idiom -- the note motion was.
  #
  # So demo-each defaults to steady and demo-all keeps its old behaviour. Set
  # DEMO_STEADY=0 to get the showcase back, DEMO_STEADY=1 to hold demo-all still.
  steady = ENV.fetch("DEMO_STEADY", demo_each? ? "1" : "0") != "0"
  unless steady
    ENV["STREAM_ROTATE_LEAD"] = "1"
    ENV["STREAM_ROTATE_SYNTH"] = "1"
    ENV["SYNTH_MORPH"] = "1"
    ENV["LEAD_MORPH"] = "1"
    ENV["SYNTH_CYCLE"] = "1"
    if creative
      ENV["STREAM_ANALOG_WILD"] = "1"
      ENV["STREAM_CREATIVE_FREEDOM"] = "1"
      ENV["EXPERIMENTAL_LEADS"] = "1"
      ENV["FM_NATIVE"] = "1"
    end
  end
  apply_best_defaults!
  apply_dilla_style!(force: true)
  force_env!(STREAM_STYLE_SAFE, label: "STREAM_STYLE_SAFE")

  # Steady has to be applied HERE, after the three calls above, not before them.
  #
  # It was written above them and did nothing at all. apply_best_defaults! sets
  # MELODIC_LEAD=0 and STREAM_STYLE_SAFE sets STREAM_ROTATE_LEAD=1, so every key
  # steady had just cleared was put straight back, and eight tracks rendered
  # with the old rotating arps while the log said steady mode was on. The
  # operator heard it immediately -- "they all sound the same as the old demo"
  # -- which is what a silent no-op sounds like.
  #
  # MELODIC_LEAD=1 is set explicitly rather than left to its default, because
  # the default is only reached when nothing else has written the key, and by
  # this point something always has.
  if steady
    %w[STREAM_ROTATE_LEAD STREAM_ROTATE_SYNTH SYNTH_MORPH LEAD_MORPH SYNTH_CYCLE
       EXPERIMENTAL_LEADS STREAM_CREATIVE_FREEDOM STREAM_ANALOG_WILD
       LEAD_FORCE_ARP SCALE_LEAD CREATIVE_LEAD].each { |k| ENV[k] = "0" }
    ENV["MELODIC_LEAD"] = "1"
  end

  # Unlock pad/lead so per-slot rotation is not pinned back to stack_soul/held.
  %w[PAD_VOICE PAD_ARP_MODE LEAD_VOICE LEAD_ARP_MODE TRACK PROGRESSION].each { |k| ENV.delete(k) }

  order = demo_all_order
  # order.txt and catalog.txt record what the manifest already records, so
  # each-mode writes neither.
  unless demo_each?
    File.write(File.join(out_dir, "order.txt"), order.map(&:to_s).join("\n") + "\n")
    # Truncate only when there is nothing to lose. The catalogue is appended one
    # line per track from inside the render loop, and a resumed track takes the
    # `next` above that line -- so a run that resumes every part writes no lines
    # at all. Truncating unconditionally then meant the join run, which is
    # exactly the run that resumes everything, erased the record of the demo it
    # was assembling: 86 pieces joined and a 0-byte catalogue saying which pad,
    # lead, voicing and drum preset each one used.
    #
    # Same rule the manifest below already follows: the file is a ledger across
    # runs, not an artifact of the last one, so only --force starts it over.
    File.write(catalog_path, "") if force || !File.file?(catalog_path)
  end
  if demo_each?
    manifest = DEMO_EACH_MANIFEST
    unless File.file?(manifest) && !force
      File.write(manifest, <<~HEAD)
        # idx  title  slug  seed  bars  pad  lead  drums  pocket  kb
        # title is ours and names the file. slug is the engine's internal name
        # for the progression -- pass it to TRACK= to render that piece again.
        # seed is the RENDER_SEED this take was rendered with. Re-roll a track by
        # deleting its mp3 and re-running with a different DEMO_SEED.
        #
        # CAVEAT: a recorded seed narrows a take down, it does not reconstruct it.
        # Two renders with RENDER_SEED pinned are still not bit-identical -- see
        # the note above noise_seed. Treat this column as a lead, not a guarantee.
      HEAD
    end
  end
  dmesg("demo-all tracks=#{order.length} bars=#{bars_count} creative=#{creative ? 1 : 0} → #{dest}",
        unit: "demo0", parent: "dilla0")

  parts = []
  order.each_with_index do |track, idx|
    slug = track.to_s
    part = File.join(out_dir, format("%02d_%s.wav", idx, slug))
    # Our title on the file; the engine's slug lives in the manifest, since that
    # is what you pass back to TRACK= to render it again.
    keep_mp3 = File.join(DEMO_EACH_DIR, format("%02d_%s.mp3", idx, demo_title(slug, idx)))
    # In each-mode the mp3 is the artifact, so that is what resume looks for.
    # Checking the wav instead would re-render every track that had already been
    # encoded and cleaned up, which is every track.
    if demo_each? && !force && File.file?(keep_mp3) && File.size(keep_mp3) > 20_000
      dmesg("keep #{File.basename(keep_mp3)}", unit: "demo0", parent: "dilla0")
      parts << keep_mp3
      next
    end
    if !demo_each? && !force && File.file?(part) && File.size(part) > 100_000 && !part.end_with?("_SILENCE.wav")
      # Reject silence leftovers from prior failed runs.
      dmesg("skip #{File.basename(part)}", unit: "demo0", parent: "dilla0")
      parts << part
      next
    end
    # Per-track pin, set before any of the rotation helpers below run so they
    # draw from it too.
    ENV["RENDER_SEED"] = demo_each_seed(idx).to_s if demo_each?
    FileUtils.rm_f(part)
    FileUtils.rm_f(File.join(out_dir, format("%02d_%s_SILENCE.wav", idx, slug)))

    ENV["TRACK"] = slug
    ENV["PROGRESSION"] = slug
    ENV["BARS"] = bars_count.to_s
    ENV["LINEAR_CHORD_INDEX"] = "1"
    ENV["LA_BEAT_PROGRESSION"] = "0"
    ENV["STREAM_LOCK"] = "0"
    # Distinct kit + pocket per slot. Kept in steady mode: the drums changing
    # per track is idiom, not restlessness, and it does not move under the
    # progression the way a rotating lead does.
    stream_rotate_drums!(idx)
    # Distinct leads / MIDI arps / synth morph per slot (clears patch cache).
    # Skipped in steady mode -- this and the second call below are what give
    # every track its own instrument, which is the thing being held still.
    stream_rotate_voices_and_arps!(idx) unless steady
    # Stronger pad identity than stream defaults (avoid every slot = stack_soul
    # held), written through the pin rule instead of straight into ENV.
    #
    # A restore_explicit_stream_env! call used to sit above these lines, and the
    # lines then overwrote the very keys it exists to protect on the next
    # statement -- so `PAD_VOICE=prophet ruby dilla.rb demo_all` rendered the
    # rotation's voice in every slot and the restore bought nothing. force_env!
    # goes through style_env_write!, which beats the defaults and loses to an
    # operator pin: the order that was intended.
    force_env!(demo_slot_pad_env(idx), label: "demo_all[#{idx}]")
    # Track-specific soul pad/lead overlays (force so they win).
    apply_track_soul_profile!(slug, force: true)
    # Re-apply rotation after soul profile so lead/pad keep moving.
    stream_rotate_voices_and_arps!(idx) unless steady
    force_env!(demo_slot_pad_env(idx), label: "demo_all[#{idx}]") unless steady
    # The rotation above writes ENV directly and turns nine layers back ON:
    # LEAD_ARP, SCALE_LEAD, HARMONY_LEAD, CREATIVE_LEAD, MELODIC_LEAD,
    # EXPERIMENTAL_LEADS, LEAD_MORPH, SYNTH_MORPH, PAD_TEXTURE -- exactly nine
    # of the twenty-one knobs a TRACK_LAYER_PROFILES entry set to "0" two lines
    # earlier. So a sampled bed whose profile exists to let the record carry the
    # harmony gets every stripped layer back before it renders, and only the
    # twelve mix-balance knobs (PAD_VOL, HARM_MIX_WEIGHT, SAMPLE_LOOP_VOL and
    # WEIGHT, ...) survive into a demo. kembara_rindu and semua_untuk_mu have
    # carried profiles all along and have never once rendered lean here.
    #
    # That was tried and reverted. An apply_track_layer_profile!(slug,
    # force: true) here does work -- production complexity drops 4.04 -> 3.81 on
    # kembara_rindu and 3.92 -> 3.67 on lo_borges, so the layers do come
    # off -- but content enjoyment goes DOWN by 0.09 on both tracks, three seeds
    # each (audiobox-aesthetics; control sd 0.01-0.18). Neither delta clears its
    # own error bar alone, but they agree in sign and to two decimals, and
    # nothing measured got better. It changed rendered sound on four tracks and
    # bought nothing, so it is not carried.
    #
    # Do not re-add it without a number. The obvious next question is whether
    # the profile's own values are wrong for a demo rather than the ordering.
    # Sparse rap so chord cycles are audible (a vocal on every slot masked
    # variety). gunnhild is the only vocal source now.
    # One branch, not three. The rap_every > 1 branch used to hardcode
    # "gunnhild" and so discarded an explicit RAP_VOCAL entirely: asking for
    # store_p with DEMO_RAP_EVERY=3 rendered gunnhild on every third slot and
    # said so in the log, which reads as the request having been honoured.
    if rap_every <= 0
      ENV["RAP_VOCAL"] = "0"
    else
      on = demo_rap_slot?(idx, rap_every)
      # Index by how many vocal slots have gone by, not by idx, or a rotation
      # of 2 voices at rap_every 2 would land on the same voice every time.
      ENV["RAP_VOCAL"] = on ? demo_rap_slugs[(idx / rap_every) % demo_rap_slugs.length] : "0"
    end
    # Same slot arithmetic as the vocal above, offset so the two do not always
    # coincide: a track carrying both a rapper and a doubled lead every time
    # would make the pair sound like one feature.
    ENV["VOICE_STACK"] = if voice_stack_every.positive? && ((idx + 1) % voice_stack_every).zero?
                           "2"
                         else
                           "1"
                         end

    # Per-slot pocket, opt-in.
    #
    # performer and groove_dna drive the microtiming offsets in dilla_timing_ms,
    # so they ARE the pocket. Left alone the whole demo inherits one identity
    # from project/session.json -- measured, 18 of 18 non-techno parts came out
    # questlove/cosmogramma, and questlove is the tightest profile in the table
    # (kick_lag 2ms, hat_late 6ms) while yancey, the Dilla one, is 8 and 22.
    # A Dilla engine demonstrated itself in the least Dilla pocket it owns.
    #
    # On by default as of 2026-08-09, on operator direction to codify it. Set
    # DEMO_VARY_POCKET=0 for the old single-pocket behaviour.
    if ENV.fetch("DEMO_VARY_POCKET", "1") == "1"
      performers = DillaComposition::PERFORMERS.keys
      grooves = DillaComposition::GROOVE_DNA.keys
      # Indexed off the slug, not idx, so a track keeps its pocket when the
      # running order changes and two demos stay comparable.
      h = slug.to_s.each_char.sum(&:ord)
      force_env!({ "PERFORMER" => performers[h % performers.length].to_s,
                   "GROOVE_DNA" => grooves[(h / 7) % grooves.length].to_s },
                 label: "demo_all[#{idx}] pocket")
    end
    # This read as "choir on every third creative slot", but the fallback was
    # "1" — so the other two thirds got a choir too, and the condition only
    # decided which branch turned it on. Choir is a vocal; the demo has none.
    ENV["CHOIR_VOX"] = ENV.fetch("CHOIR_VOX", "0")

    dmesg(
      "render #{idx + 1}/#{order.length} #{slug} " \
      "pad=#{ENV['PAD_VOICE']}/#{ENV['PAD_ARP_MODE']} " \
      "lead=#{ENV['LEAD_VOICE']}/#{ENV['LEAD_ARP_MODE']} " \
      "vox=#{ENV['VOICING']} drums=#{ENV['DRUM_PRESET']}/#{ENV['POCKET_SET']} " \
      "rap=#{ENV['RAP_VOCAL']}",
      unit: "demo0", parent: "dilla0",
    )
    unless demo_each?
      File.open(catalog_path, "a") do |f|
        f.puts format(
          "%02d %s pad=%s/%s lead=%s/%s voicing=%s drums=%s/%s rap=%s",
          idx, slug, ENV["PAD_VOICE"], ENV["PAD_ARP_MODE"],
          ENV["LEAD_VOICE"], ENV["LEAD_ARP_MODE"], ENV["VOICING"],
          ENV["DRUM_PRESET"], ENV["POCKET_SET"], ENV["RAP_VOCAL"]
        )
      end
    end

    ok = false
    begin
      Timeout.timeout(track_timeout) do
        if demo_techno_slot?(idx, slug)
          # Techno slots go through the industrial renderer instead. Length is
          # matched to what the hip-hop track would have run to, so the two
          # sit side by side in a demo rather than one being twice the other.
          prev = ENV["HATE_MIN"]
          prev_blocks = ENV["HATE_MIN_BLOCKS"]
          prev_arrived = ENV["HATE_ARRIVED"]
          ENV["HATE_MIN"] = ((bars_count * 4 * (60.0 / HATE_BPM)) / 60.0).round(2).to_s
          # A demo slot is a sample, not a set: one block is a legitimate length
          # here even though it is not one for a standalone techno render. Without
          # this the renderer's own floor doubles the slot back and the length
          # matching on the line above is discarded a second time.
          ENV["HATE_MIN_BLOCKS"] = "1"
          # ...and a sample is of the music, not of the way in to it. The arc's
          # only resolution is the block, so a slot short enough to be two blocks
          # puts the listener at position 0.0 for the whole first half -- three of
          # eighteen layers, -50.5 dB against the second half's -14.3. Every
          # techno slot in the demo had that shape, identical to 0.1 dB across all
          # 27, because a dead block carries no progression to tell them apart.
          ENV["HATE_ARRIVED"] = "1"
          begin
            dmesg("slot #{idx} -> techno", unit: "demo0", parent: "dilla0")
            techno_mp3 = part.sub(/\.wav\z/, ".mp3")
            render_hate_techno(techno_mp3)
            # Decode, do not rename. The techno renderer writes an mp3, and
            # moving it onto the .wav path gave the part an extension that lied
            # about its contents -- every other slot here is pcm_s16le. That
            # matters at the end of this method, where the parts are joined with
            # `-c copy`: the concat demuxer probes only the FIRST input and
            # applies that codec to all of them, so one mp3 in slot 1 makes
            # ffmpeg copy mp3 packets into a WAV container and exit 0. Nothing
            # raises, so the re-encode rescue below never fires; the file
            # does not open (afplay: "AudioFileOpen failed ('dta?')") and
            # ffprobe reports a duration read from a header that does not
            # describe the data -- 14.2 minutes for 5.3 minutes of audio.
            sh! "ffmpeg", "-y", "-loglevel", "error", "-i", techno_mp3,
                "-c:a", "pcm_s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "2", part
            FileUtils.rm_f(techno_mp3)
          ensure
            prev ? ENV["HATE_MIN"] = prev : ENV.delete("HATE_MIN")
            prev_blocks ? ENV["HATE_MIN_BLOCKS"] = prev_blocks : ENV.delete("HATE_MIN_BLOCKS")
            prev_arrived ? ENV["HATE_ARRIVED"] = prev_arrived : ENV.delete("HATE_ARRIVED")
          end
        else
          render_dilla(part, bars_count)
        end
      end
      ok = File.file?(part) && File.size(part) > 50_000
    rescue Timeout::Error
      dmesg_warn("timeout #{slug} after #{track_timeout}s")
      FileUtils.rm_f(part)
    rescue StandardError => e
      dmesg_warn("fail #{slug}: #{e.message}")
      File.open(log_path, "a") { |f| f.puts "#{Time.now.utc.iso8601} FAIL #{slug}: #{e.message}" }
      FileUtils.rm_f(part)
    end

    unless ok
      dmesg("retry minimal #{slug}", unit: "demo0", parent: "dilla0")
      saved = %w[RAP_VOCAL CHOIR_VOX LEAD_MORPH SYNTH_MORPH SELF_SAMPLE VINYL
                 LEAD_ARP HARMONY_LEAD SCALE_LEAD CREATIVE_LEAD].to_h { |k| [k, ENV[k]] }
      ENV["RAP_VOCAL"] = "0"
      ENV["CHOIR_VOX"] = "0"
      ENV["LEAD_MORPH"] = "0"
      ENV["SYNTH_MORPH"] = "0"
      ENV["SELF_SAMPLE"] = "0"
      ENV["VINYL"] = "0"
      ENV["LEAD_ARP"] = "1"
      ENV["HARMONY_LEAD"] = "0"
      ENV["SCALE_LEAD"] = "0"
      ENV["CREATIVE_LEAD"] = "0"
      begin
        Timeout.timeout(track_timeout) do
          render_dilla(part, [bars_count, 8].min)
        end
        ok = File.file?(part) && File.size(part) > 50_000
      rescue StandardError, Timeout::Error => e
        dmesg_warn("retry fail #{slug}: #{e.message}")
        FileUtils.rm_f(part)
      ensure
        saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end

    if ok && demo_each?
      # Encode and drop the wav. 86 WAVs is ~500 MB of a directory meant to be
      # browsed and pruned; the same catalogue as mp3 is a few tens of MB.
      # demo_encode_mp3 derives its output path from the wav's, so the mp3 lands
      # beside the wav in scratch and has to be moved. Encoding to scratch and
      # moving, rather than encoding straight to the root, means a half-written
      # mp3 from an interrupted run never appears in the listening queue where it
      # would look like a finished take.
      mp3 = demo_encode_mp3(part)
      if mp3
        FileUtils.mv(mp3, keep_mp3)
        mp3 = keep_mp3
        FileUtils.rm_f(part)
        parts << mp3
        File.open(DEMO_EACH_MANIFEST, "a") do |f|
          f.puts [format("%02d", idx), demo_title(slug, idx), slug, demo_each_seed(idx), bars_count,
                  ENV["PAD_VOICE"], ENV["LEAD_VOICE"], ENV["DRUM_PRESET"],
                  ENV["POCKET_SET"], (File.size(mp3) / 1024)].join("\t")
        end
        dmesg("ok #{slug} seed=#{demo_each_seed(idx)} #{(File.size(mp3) / 1_000_000.0).round(2)}MB",
              unit: "demo0", parent: "dilla0")
      else
        parts << part
        dmesg_warn("mp3 encode failed #{slug} — keeping wav")
      end
    elsif ok
      parts << part
      dmesg("ok #{slug} #{(File.size(part) / 1_000_000.0).round(2)}MB", unit: "demo0", parent: "dilla0")
    else
      sil = File.join(out_dir, format("%02d_%s_SILENCE.wav", idx, slug))
      beat_p = 60.0 / (ENV["BPM"] || "92").to_f
      sec = ([bars_count, 8].min * 4 * beat_p).round(3)
      begin
        sh! "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=#{SAMPLE_RATE}:cl=stereo",
            "-t", sec.to_s, "-c:a", "pcm_s16le", sil
        parts << sil if File.file?(sil)
        dmesg_warn("silence placeholder #{slug}")
      rescue StandardError
        dmesg_warn("skip #{slug} (no audio)")
      end
    end
    # PID-scoped, via the helper that already exists for exactly this. The glob
    # here was ".dilla_*" with no pid in it, so a demo-all run deleted the
    # scratch files of every OTHER dilla process in the directory, once per
    # track. A concurrent render then fails in a way that looks like anything
    # but this: its layer files pass File.exist? in mix_harmonic_wav_stems and
    # are gone by the time ffmpeg opens them, so the render dies on "No such
    # file or directory" for a file it just checked for. Every render in this
    # working copy failed for the ~40 minutes a catalogue demo was running.
    cleanup_render_scratch!
  end

  abort "demo-all: no parts rendered" if parts.empty?

  # Look inside the parts before joining them.
  #
  # 28 of the 86 tracks in the demo committed at c0d00f488 were silence -- the
  # techno slots, at -47.7 dB overall with no low end at all -- and every check
  # between rendering them and publishing them passed. `ok` gates on
  # File.size > 50_000, which a silent WAV satisfies easily. The lengths were
  # measured and matched the arithmetic exactly. The concat succeeded. The
  # loudness of the FINISHED record looked correct, because 58 healthy tracks
  # carry an integrated figure past 28 quiet ones. It was rendered, joined,
  # encoded, committed and played twice before anyone measured a part.
  #
  # So this measures the two things that were not being measured, per part, and
  # says so out loud. Silence and truncation are the two failures this engine
  # produces without raising -- a stage that emits nothing still writes a valid
  # file, and a render cut short still writes a playable one.
  #
  # Thresholds are relative to the parts themselves, not absolutes: a demo that
  # is quiet on purpose should not trip this, but one track 25 dB under its
  # neighbours is never intentional. Median, not mean, so a handful of bad parts
  # cannot drag the reference down to meet them.
  demo_report_suspect_parts(parts)

  if demo_each?
    dmesg("demo-each: #{parts.length} files in the dilla root", unit: "demo0", parent: "dilla0")
    puts "#{parts.length} tracks -> #{DEMO_EACH_DIR.sub("#{File.dirname(ROOT)}/", '')}/"
    puts "delete the ones that miss, then re-run: the survivors are skipped and only the gaps re-render"
    puts "re-roll one: DEMO_SEED=<n> ruby dilla.rb demo-each   (or delete just that file first)"
    return parts
  end

  # Drop parts that are digitally dead before joining, not after.
  #
  # demo_report_suspect_parts below already names quiet and short parts, and it
  # is deliberately a warning -- one bad part should not throw away eighty good
  # ones. But it runs AFTER this join, so a part carrying nothing was warned
  # about only once it was already inside demo.wav and demo.mp3. Measured twice
  # now: a *_SILENCE placeholder at -91.0 dB joined into a shipped demo, and the
  # log line that mentioned it read as a note rather than a fault.
  #
  # This is narrower than the suspect heuristic on purpose. It does not touch
  # "quiet relative to its neighbours", which can be a legitimate take; it drops
  # only files with no signal at all, which never can be. The part stays on
  # disk, so deleting nothing and re-running still refills the gap.
  parts = demo_reject_dead_parts(parts)
  list = File.join(out_dir, "concat.txt")
  File.write(list, parts.map { |p| "file '#{p}'" }.join("\n") + "\n")
  tmp = "#{dest}.concat.wav"
  demo_join_parts!(parts, list, tmp)
  FileUtils.mv(tmp, dest)
  # Optional album-level loudnorm (off by default — long concats exceed sh timeout).
  if ENV.fetch("DEMO_ALBUM_NORM", "0") == "1"
    prev_to = ENV["DILLA_SH_TIMEOUT"]
    ENV["DILLA_SH_TIMEOUT"] = (ENV["DEMO_NORM_TIMEOUT"] || "600").to_s
    begin
      normalize_track_loudness!(dest)
    ensure
      prev_to ? ENV["DILLA_SH_TIMEOUT"] = prev_to : ENV.delete("DILLA_SH_TIMEOUT")
    end
  end
  # Re-recorded against `dest`, because demo_join_parts! wrote its manifest
  # beside the temporary and the mv above left it there. Working out what was in
  # a 44-minute master by fingerprinting every file still on disk is what this
  # exists to prevent; a tracklist filed under a filename that no longer exists
  # would prevent nothing.
  DillaProvenance.record_assembly!(
    dest, parts:,
    how: "demo concat of #{parts.length} part(s)" +
         (ENV.fetch("DEMO_ALBUM_NORM", "0") == "1" ? ", then album loudnorm" : "")
  )
  FileUtils.rm_f("#{tmp}#{DillaProvenance::MANIFEST_EXT}")
  dur = 0.0
  begin
    out, = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=noprint_wrappers=1:nokey=1", dest)
    dur = out.to_s.strip.to_f
  rescue StandardError
    nil
  end
  mp3 = demo_encode_mp3(dest)
  # The mp3 gets its own sidecar, not just the wav.
  #
  # record_assembly! above files the tracklist under `dest`, which is demo.wav —
  # and demo.wav, demo.wav.dilla and demo.mp3 are all gitignored, so the only
  # one of the three that reliably survives on disk is the mp3. It is the file
  # this code calls the tracked artifact two lines down, it is the one that gets
  # played and sent to people, and it was the one with no record of how it was
  # made. On 2026-08-27 a 36:57 master finished with its provenance filed under a
  # wav that no longer existed and a session.json five hours older than the
  # render, so what made it could not be recovered at all. Seeds rotate per run;
  # an unreproducible master with no manifest is simply lost.
  if mp3
    DillaProvenance.record_assembly!(
      mp3, parts:,
      how: "demo concat of #{parts.length} part(s), encoded to mp3" +
           (ENV.fetch("DEMO_ALBUM_NORM", "0") == "1" ? ", after album loudnorm" : "")
    )
  end
  dmesg("wrote #{dest} parts=#{parts.length}/#{order.length} #{(File.size(dest) / 1_000_000.0).round(1)}MB #{dur.round(1)}s",
        unit: "demo0", parent: "dilla0")
  puts "ok: #{dest} (#{parts.length}/#{order.length} tracks, #{dur.round(1)}s)"
  if mp3
    dmesg("wrote #{mp3} #{(File.size(mp3) / 1_000_000.0).round(1)}MB", unit: "demo0", parent: "dilla0")
    puts "ok: #{mp3} (#{(File.size(mp3) / 1_000_000.0).round(1)}MB, tracked artifact)"
  end
  dest
end
