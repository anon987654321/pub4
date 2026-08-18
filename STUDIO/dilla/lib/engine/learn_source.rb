# frozen_string_literal: true
#
# Learning from a source or a whole playlist.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def learn_source!(src, apply: false, deep: false, start_sec: nil, meta: nil)
  DillaMusicGems.bootstrap! if defined?(DillaMusicGems)
  audio_path = if File.exist?(src.to_s)
                 File.expand_path(src)
               else
                 demux_fetch_audio(src, start_sec:)
               end
  stem_dir = demux_six(audio_path)
  demux_deep_bands!(stem_dir) if deep
  stem_analysis = {}
  Dir[File.join(stem_dir, "*.wav")].sort.each do |wav|
    name = File.basename(wav)
    stem_analysis[name] = analyze_stem_for_learn(wav, name)
  end
  full_analysis = RadioBergenStudy::DeepAudio.analyze(audio_path)
  report = DillaSourceLearn.compose_report(
    source: src,
    stem_dir:,
    stem_analysis:,
    full_analysis:,
  )
  report = report.merge(meta) if meta.is_a?(Hash)
  if meta.is_a?(Hash) && meta[:id]
    learn_register_texture_stems!(stem_dir, meta[:id], bpm: report[:bpm_estimate])
  end
  paths = DillaSourceLearn.save_report!(report)
  puts JSON.pretty_generate(report.merge(saved: paths))
  if apply
    applied = DillaSourceLearn.apply_hints_to_env!(report[:engine_hints])
    ENV["STREAM_LEARN_BIAS"] = "1"
    puts "applied: #{applied.join(', ')}"
  end
  report
end

def learn_playlist_row!(row, deep: true, force: false)
  key = playlist_row_key(row)
  return if key.empty?

  slug = RadioBergenStudy.slug(row[:artist], row[:title])
  state = DillaSourceLearn.load_batch_state
  return :skipped if !force && Array(state["completed_ids"]).include?(key)

  aff = RadioBergenStudy.affinity_for(row[:artist])
  dossier = RadioBergenStudy.dossier_for(slug)
  meta = { id: slug, artist: row[:artist], title: row[:title], source: "playlist.brgen.no",
           affinity: aff, dossier: }

  if row[:source] == "local_mp3"
    path = RadioBergenStudy.resolve_local_path(row)
    unless path && File.file?(path)
      warn "learn-playlist: local missing — #{row[:artist]} — #{row[:title]} (#{row[:src]})"
      return
    end
    puts "learn-playlist: [local] #{row[:artist]} — #{row[:title]}"
    report = learn_source!(path, deep:, meta: meta.merge(local_src: row[:src], audio_path: path))
  else
    id = row[:youtube_id].to_s
    return if id.empty?
    url = youtube_watch_url(id, start: row[:start])
    puts "learn-playlist: [youtube] #{row[:artist]} — #{row[:title]} (#{id})"
    report = learn_source!(url, deep:, start_sec: row[:start],
                           meta: meta.merge(youtube_id: id, url:))
  end

  entry = report.merge(id: slug, artist: row[:artist], title: row[:title],
                       youtube_id: row[:youtube_id], learned_at: Time.now.utc.iso8601)
  DillaSourceLearn.save_playlist_entry!(entry)
  learn_register_texture_stems!(report[:stem_dir], slug, bpm: report[:bpm_estimate])
  state["completed_ids"] = (Array(state["completed_ids"]) + [key]).uniq
  state["failed"] ||= {}
  state["failed"].delete(key)
  state["last_completed"] = { key:, slug:, at: Time.now.utc.iso8601 }
  DillaSourceLearn.save_batch_state!(state)
  entry
rescue StandardError => e
  state = DillaSourceLearn.load_batch_state
  state["failed"] ||= {}
  state["failed"][key] = { error: e.message, at: Time.now.utc.iso8601 }
  DillaSourceLearn.save_batch_state!(state)
  warn "learn-playlist: #{row[:artist]} — #{row[:title]} failed: #{e.message}"
  nil
end

def learn_register_texture_stems!(stem_dir, slug, bpm: nil)
  return unless stem_dir && File.directory?(stem_dir)
  stems_register("learn_#{slug}", stem_dir, bpm:, source: "playlist.brgen.no/#{slug}")
rescue StandardError => e
  warn "stem register: #{e.message}"
end

def learn_playlist_batch!(youtube_only: true, deep: true, resume: true, limit: nil, force: false,
                          promote: true, calibrate: true)
  DillaSourceLearn.ensure_dir!
  rows = RadioBergenStudy.catalog_rows
  if youtube_only
    rows = rows.select { |r| r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? }
  else
    rows = rows.select do |r|
      r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? ||
        (r[:source] == "local_mp3" && RadioBergenStudy.resolve_local_path(r))
    end
  end
  if resume && !force
    state = DillaSourceLearn.load_batch_state
    done = Array(state["completed_ids"])
    rows = rows.reject { |r| done.include?(playlist_row_key(r)) }
  end
  rows = rows.first(limit.to_i) if limit

  puts "learn-playlist: #{rows.length} track(s) — demucs=#{demucs_available? ? 'yes' : 'NO'} deep=#{deep}"
  results = rows.map { |row| learn_playlist_row!(row, deep:, force:) }
  ok = results.count { |r| r.is_a?(Hash) }
  skipped = results.count { |r| r == :skipped }
  learn_promote! if promote && ok.positive?
  learn_calibrate! if calibrate
  learn_diff_dossiers!
  puts "learn-playlist: done #{ok} ok, #{skipped} skipped, #{rows.length - ok - skipped} failed"
  puts "catalog -> #{DillaSourceLearn::PLAYLIST_CATALOG_PATH}"
  { ok:, skipped:, failed: rows.length - ok - skipped, catalog: DillaSourceLearn::PLAYLIST_CATALOG_PATH }
end

def learn_playlist_agent!(foreground: false)
  DillaSourceLearn.ensure_dir!
  log_path = DillaSourceLearn::PLAYLIST_BATCH_LOG
  unless foreground || ENV["DILLA_AGENT_LAUNCHED"] == "1"
    cmd = "cd #{Shellwords.escape(ROOT)} && DILLA_AGENT_LAUNCHED=1 DILLA_RAW=1 #{Shellwords.escape(Gem.ruby)} " \
          "#{Shellwords.escape(ENGINE_FILE)} learn-playlist-agent foreground"
    pid = Process.spawn(cmd, out: log_path, err: log_path)
    Process.detach(pid)
    puts "learn-playlist-agent: background pid=#{pid} log=#{log_path}"
    return pid
  end
  ensure_demucs_ready!
  loop do
    rows = RadioBergenStudy.catalog_rows.select do |r|
      r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? ||
        (r[:source] == "local_mp3" && RadioBergenStudy.resolve_local_path(r))
    end
    done = Array(DillaSourceLearn.load_batch_state["completed_ids"])
    pending = rows.reject { |r| done.include?(playlist_row_key(r)) }
    break if pending.empty?
    learn_playlist_batch!(youtube_only: false, deep: true, resume: true, promote: true, calibrate: true)
    sleep 120
  end
end

def ensure_demucs_ready!
  return if demucs_available?
  venv = DEMUX_VENV_DIR
  unless File.directory?(venv)
    sh! "python3", "-m", "venv", venv
  end
  pip = File.join(venv, "bin", "pip")
  demucs_py = File.join(venv, "bin", "python")
  unless system(demucs_py, "-m", "demucs", "--help", out: File::NULL, err: File::NULL)
    sh! pip, "install", "-q", "numpy", "demucs"
  end
  ENV["PATH"] = "#{File.join(venv, 'bin')}:#{ENV['PATH']}"
  abort "demucs install failed — run: #{pip} install numpy demucs" unless demucs_available?
end

# =============================================================================
# LIVESET (long-form stem rack WAV)
# =============================================================================

def liveset_filter(count, periods: LIVESET_PERIODS)
  per_input = (0...count).map do |i|
    p = periods[i % periods.size]; phase = (i * 1.7).round(3); base = (0.55 + (i % 3) * 0.05).round(2)
    "[#{i}:a]aformat=sample_rates=44100:channel_layouts=stereo," \
      "volume='#{base}*(0.55+0.45*sin(2*PI*(t+#{phase})/#{p}))':eval=frame[s#{i}]"
  end
  taps = (0...count).map { |i| "[s#{i}]" }.join
  master = <<~F.tr("\n", " ").strip
    [mix]acompressor=threshold=-20dB:ratio=4:attack=30:release=300:makeup=2,
    highpass=f=30:width_type=q:width=1.2,equalizer=f=55:t=o:w=0.8:g=2,
    acrusher=bits=12:samples=1.69:level_in=1:level_out=1:mix=0.35,
    equalizer=f=2200:t=o:w=0.6:g=-2,
    aphaser=in_gain=0.4:out_gain=0.7:delay=2:decay=0.3:speed=0.12:type=sinusoidal,
    aeval='(tanh((val(0)+0.05)*1.6)-0.0798)/0.853|(tanh((val(1)+0.05)*1.6)-0.0798)/0.853',
    alimiter=level_in=1.0:level_out=0.95:limit=0.95:attack=5:release=80[out]
  F
  "#{per_input.join(';')};#{taps}amix=inputs=#{count}:weights=#{'1 ' * count}:duration=longest[mix];#{master}"
end

def render_liveset(name = "default", minutes: LIVESET_MIN)
  require_tools! "ffmpeg"
  m = stems_load_manifest
  set = m["sets"][name] || m["sets"][m["active"]] or abort "liveset: no stem set '#{name}'"
  # `dir` is relative to ROOT: the stems live under samples/demux, not in
  # STEM_DIR, which does not exist in the tree at all. Joining against STEM_DIR
  # built a path below a missing directory, so every set resolved to nothing.
  base_dir = File.expand_path(set["dir"] || ".", ROOT)
  files = set["files"]
  abort "liveset: empty set" if files.nil? || files.empty?
  inputs = files.flat_map { |f| ["-stream_loop", "-1", "-i", File.join(base_dir, f)] }
  out = File.join(OUTPUT_DIR, "liveset_#{name}_#{minutes}m.wav")
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", liveset_filter(files.size),
      "-map", "[out]", "-t", (minutes * 60).to_s, "-ar", "44100", "-c:a", "pcm_s16le", out
  puts "liveset -> #{out}"
end
