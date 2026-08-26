# frozen_string_literal: true
#
# The stream loop itself.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def stream(bars_count = STREAM_BARS_COUNT)
  require_playback_tool!
  # Non-stop outer supervisor: any exit except Ctrl-C restarts stream (agent + interactive).
  if ENV.fetch("STREAM_CONTINUOUS", "1") != "0" && ENV["DILLA_STREAM_SUPERVISOR"] != "1"
    stream_log = File.join(SCRATCH_DIR, "stream.log")
    # Read from USER_PINNED_ENV, not ENV.
    #
    # This list is built after apply_best_defaults! has already run, so every
    # key it names is populated whether or not the caller asked for it. Passing
    # ENV's value forwarded the engine's own defaults to the child as if the
    # user had typed them — and in the child they land in USER_PINNED_ENV, where
    # force_env! and the per-track sync both treat them as untouchable. That is
    # how `STREAM_TRACK=slum_village_players_documented` ended up locked to
    # pedal_e_descent's chords: PROGRESSION was "pinned" to a default nobody
    # chose. USER_PINNED_ENV holds what the command line actually said.
    #
    # PAD_VOICE / PAD_LAYERS / LEAD_* are here because a pinned pad or lead was
    # silently dropped at the supervisor boundary before: PAD_VOL made the list
    # but PAD_VOICE did not, so `PAD_VOICE=prophet ruby dilla.rb stream` played
    # whatever the soul profile chose.
    env_pass = %w[
      RENDER_MODE STREAM_SOUL STREAM_COMFORT STREAM_PUNCH DILLA_COMFORT SPEAK RAP_VOCAL
      STREAM_DEMO STREAM_TRACK STREAM_LOCK
      FLYLO_TOP_MIX FLYLO_SUB_MIX FLYLO_MERGE_BOOST FLYLO_OVERLAY_GAIN FLYLO_DRUM_OVERLAY
      DRUM_BUS_VOL DRUM_BUS_GAIN DRUM_MIX_WEIGHT DRUM_AIR_DB DRUM_PRESENCE_DB
      KICK_GAIN FLYLO_KICK_GAIN POCKET_KICKS FLYLO_DRUMS_ONLY PAD_VOL STREAM_LUFS
      STREAM_ROTATE_LEAD STREAM_ROTATE_SYNTH STREAM_DRUM_ROTATE THEORY_RUNTIME THEORY_BACH
      PAD_VOICE PAD_ARP_MODE PAD_LAYERS LEAD_VOICE LEAD_ARP_MODE PROGRESSION SECTION_CYCLE
      DRUM_PRESET FM_DRUMS SWING BPM DRUM_FADE_IN
      LEAD_ARP SCALE_LEAD HARMONY_LEAD CREATIVE_LEAD EXPERIMENTAL_LEADS
      SYNTH_CYCLE SYNTH_MORPH LEAD_MORPH ANALOG_CHAIN SONITEX VINYL
    ].filter_map do |k|
      v = USER_PINNED_ENV[k]
      v.nil? || v.empty? ? nil : "#{k}=#{Shellwords.escape(v)}"
    end.join(" ")
    # The env_pass prefix above is additive, not exclusive: this command runs
    # through a shell that inherits this process's whole environment, including
    # everything apply_best_defaults! wrote. Naming only the pinned keys in the
    # prefix therefore did nothing to stop PROGRESSION=pedal_e_descent reaching
    # the child, where it read as a user pin and became unoverridable. The child
    # needs to be told which keys are real, so declare them.
    pinned_keys = dilla_pinned_keys_decl
    cmd = "cd #{Shellwords.escape(ROOT)} && while true; do " \
          "DILLA_STREAM_LAUNCHED=1 DILLA_STREAM_SUPERVISOR=1 " \
          "DILLA_USER_PINNED_KEYS=#{Shellwords.escape(pinned_keys)} #{env_pass} " \
          "ruby #{Shellwords.escape(ENGINE_FILE)} stream #{bars_count.to_i} 2>&1 | tee -a #{Shellwords.escape(stream_log)}; " \
          "c=$?; [ $c -eq 130 ] && break; " \
          "echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) stream exited $c — restart in 2s\" | tee -a #{Shellwords.escape(stream_log)}; " \
          "sleep 2; done"
    if darwin? && ENV["DILLA_STREAM_LAUNCHED"] != "1" &&
       (ENV["GROK_AGENT"] == "1" || !$stdout.tty? || ENV["DILLA_FORCE_TERMINAL"] == "1")
      dmesg("agent shell — open terminal for continuous stream", unit: "stream0", parent: "dilla0")
      DillaDmesg.emit("exec0", "osascript terminal stream", parent: "dilla0") if DillaDmesg.verbose?
      system("osascript", "-e", %(tell application "Terminal" to do script "#{cmd.gsub('"', '\\"')}"))
      system("osascript", "-e", 'tell application "Terminal" to activate')
      return
    end
    # In-process continuous loop (agent already has a shell / non-Terminal path).
    exec("zsh", "-c", cmd)
  end
  $stdout.sync = true
  $stderr.sync = true
  acquire_stream_lock!
  prev_track = ENV["TRACK"]
  # USER_PINNED_ENV, not ENV. This is the last of the guards that inferred the
  # operator's intent from "is the key set", and it is the one that cost the most.
  #
  # In a supervisor child every one of these keys arrives populated -- PAD_VOICE
  # and LEAD_VOICE come from DILLA_BEST_DEFAULTS before the first render -- so both
  # flags were true whether or not anybody asked for a pad or a lead. That made
  # apply_track_soul_profile! run with force: false, where style_env_write!
  # refuses to overwrite a key that already has a value, so no track's
  # TRACK_SOUL_PAD/LEAD profile ever landed; and it skipped
  # stream_rotate_voices_and_arps! outright. Measured over one stream's log: 126
  # consecutive renders on pad=stack_soul/held lead=soul_prophet/flylo_spiral,
  # every track in the cycle, which is what "it all sounds like one song" is.
  #
  # Same fix as sync_progression_to_track! got for PROGRESSION, on the pad/lead
  # half of the same guard.
  user_pad_locked = %w[PAD_VOICE PAD_ARP_MODE].any? { |k| !USER_PINNED_ENV[k].to_s.empty? }
  user_lead_locked = %w[LEAD_VOICE LEAD_ARP_MODE].any? { |k| !USER_PINNED_ENV[k].to_s.empty? }
  @stream_user_pad_locked = user_pad_locked
  @stream_user_lead_locked = user_lead_locked
  apply_stream_listenability_defaults!
  order = stream_track_order
  # Ruby can't safely reload this file in-process (the CLI dispatch at the
  # bottom runs unconditionally, so a mid-run `load` would re-trigger it —
  # risk of recursion). exec-ing a fresh process instead is safe: it fully
  # replaces this process with a new one that reads the file from disk
  # again, so edits since the last track take effect automatically between
  # tracks without needing a manual kill+relaunch.
  #
  # The newest of ALL the engine's sources, not dilla.rb's own: since the split
  # nearly every edit lands in lib/engine/, and watching only the entry script
  # would mean a stream that never picks up a change while looking like it does.
  self_mtime = engine_mtime
  mode = if stream_deep?
           "deep+QC"
         elsif stream_iterate_enabled?
           "fast+iterate"
         else
           "fast"
         end
  DillaDmesg.boot!(mode: ENV["RENDER_MODE"] || DEFAULT_RENDER_MODE, cmd: "stream")
  DillaDmesg.stream!(mode:, bars: bars_count, order_n: order.length)
  dmesg("cycle #{order.first(8).join(',')}#{order.length > 8 ? '…' : ''} (ctrl-c stop)", unit: "stream0", parent: "dilla0")
  dmesg("iterate log #{File.basename(STREAM_ITERATE_LOG.to_s)}", unit: "stream0", parent: "dilla0") if stream_iterate_enabled?
  loop do
    order.each_with_index do |item, idx|
      if engine_mtime > self_mtime
        dmesg("engine mtime changed — exec restart", unit: "stream0", parent: "dilla0")
        ENV["DILLA_STREAM_SUPERVISOR"] = "1"
        ENV["DILLA_STREAM_LAUNCHED"] = "1"
        # Carry the real pin set across the restart. Without this the child
        # reads the defaults this process wrote as user intent — see
        # USER_PINNED_ENV's comment.
        ENV["DILLA_USER_PINNED_KEYS"] = dilla_pinned_keys_decl
        exec(Gem.ruby, ENGINE_FILE, "stream", bars_count.to_s)
      end
      track = item.to_s
      apply_track_soul_profile!(track, force: !user_pad_locked && !user_lead_locked)
      stream_rotate_voices_and_arps!(idx) unless user_lead_locked
      restore_explicit_stream_env!
      reassert_pad_lead_locks! unless user_pad_locked
      ENV["TRACK"] = track
      sync_progression_to_track!(track)
      stream_rotate_drums!(idx)
      reassert_dilla_style_locks! if dilla_style? && ENV["STREAM_LOCK"] == "1"
      if radio_bergen_stream_enabled? && rand < 0.38 && (rb = pick_radio_bergen_stream_track!)
        track = rb
        apply_track_soul_profile!(track, force: !user_pad_locked && !user_lead_locked)
        stream_rotate_voices_and_arps!(idx) unless user_lead_locked
        restore_explicit_stream_env!
        reassert_pad_lead_locks! unless user_pad_locked
        ENV["TRACK"] = track
        sync_progression_to_track!(track)
        stream_rotate_drums!(idx)
        stream_track_banner("← playlist.brgen.no")
      else
        stream_track_banner
      end
      begin
        stream_play_track!(bars_count)
      rescue SystemExit, Interrupt
        raise
      rescue Timeout::Error
        warn "stream: #{ENV['TRACK'] || track} timed out after #{stream_track_timeout_sec}s — skipping"
        sleep 1.0
      rescue Exception => e # scan: intentional — track supervisor; SystemExit and Interrupt re-raised above
        warn "stream: #{ENV['TRACK'] || track} failed (#{e.class}) — #{e.message}"
        sleep 1.0
      end
      gap = (ENV["STREAM_GAP"] || "0.55").to_f
      xfade = (ENV["STREAM_CROSSFADE"] || "0.12").to_f
      # Soft silence between tracks (crossfade is intentional gap, not sample morph).
      sleep DillaSeeds.drift_sleep([gap + xfade, 0.05].max) if gap.positive? || xfade.positive?
    end
  end
ensure
  prev_track ? ENV["TRACK"] = prev_track : ENV.delete("TRACK")
end

# Instantly play a modulating bass tone — good for local audio system check.
def bass(root_hz = 55.0)
  require_tools! "ffplay"
  # Warbling sub bass: fundamental + slow pitch LFO + low harmonic content.
  # Models J Dilla's low-end: not a clean sine, has movement and weight.
  lfo_hz = 0.18
  lfo_amt = root_hz * 0.04
  expr_l = "0.45*sin(2*PI*(#{root_hz}+#{lfo_amt}*sin(2*PI*#{lfo_hz}*t))*t)" \
             "+0.08*sin(2*PI*#{(root_hz * 2).round(2)}*t)" \
             "+0.03*sin(2*PI*#{(root_hz * 3).round(2)}*t)"
  filter = "aeval=exprs='#{expr_l}:#{expr_l}',equalizer=f=80:width_type=o:width=2:g=4,lowpass=f=200"
  puts "playing bass #{root_hz}Hz (Ctrl-C to stop)"
  exec "ffplay", "-f", "lavfi", "-i", "aevalsrc=0", "-nodisp", "-af", filter
rescue SystemCallError => e
  abort "ffplay failed: #{e.message}"
end
