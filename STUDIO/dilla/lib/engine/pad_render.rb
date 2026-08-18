# frozen_string_literal: true
#
# Rendering pads through fluidsynth.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# RMS the pad bus is normalised to. Was -17.5, which only balanced against the
# ~-38 dB drum bus because warm_dilla_pad_post immediately took ~19 dB back off
# via its aecho/chorus in_gain bug -- the two errors cancelled. With that fixed
# the level has to be honest here instead: pads land just under the kit, which
# is what "kit-forward" in DILLA_STYLE_DEFAULTS asks for.
PAD_TARGET_RMS_DB = (ENV["PAD_TARGET_RMS_DB"] || -39.0).to_f

# Lazily, silently fetches EXTERNAL_SOUNDFONTS/EXTERNAL_DRUM_KIT_REPO on
# first use so nothing needs to be typed/remembered — but any network
# hiccup (offline, GitHub down) must never break a render, hence the
# broad rescue (fetch_assets! can raise SystemExit via abort on a missing
# curl/git, not just StandardError).
def ensure_external_assets_lazy!
  return @external_assets_checked if defined?(@external_assets_checked)
  @external_assets_checked =
    begin
      sf_dir = File.expand_path("~/.cache/dilla-soundfonts")
      have_all = EXTERNAL_SOUNDFONTS.keys.all? { |n| File.exist?(File.join(sf_dir, n)) } &&
                 Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
      fetch_assets! unless have_all
      true
    rescue StandardError, SystemExit
      false
    end
end

def resolve_ep_voice
  if ENV["DILLA_PAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: PAD_GM_PROGRAM, patch: nil }
  end
  patch_voice_for(@render_ep_patch) || begin
    program = render_pick(EP_GM_PROGRAMS, "ep_program")
    { sf2: pad_soundfont_path, bank: 0, program:, patch: nil }
  end
end

# Lead voice from SYNTH_PATCH_CATALOG — supersaw, prophet, FM bell, etc.
def resolve_lead_voice
  if ENV["DILLA_LEAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: ENV["DILLA_LEAD_PROGRAM"].to_i, patch: @render_lead_patch }
  end
  patch_voice_for(@render_lead_patch) || { sf2: pad_soundfont_path, bank: 0, program: render_pick(LEAD_GM_PROGRAMS, "lead_program"), patch: nil }
end

def resolve_texture_voice
  patch_voice_for(@render_texture_patch)
end

# Rhodes alone (GM 4) is Dilla's half of the research (Rhodes/Wurlitzer);
# blending in a warm analog pad voice covers the other half — both artists'
# keyboards used real analog synths (Minimoog Voyager, Prophet 6/5, Yamaha
# CS-60) alongside the electric piano, not instead of it. A different pair
# picked per render rather than always the same two programs. The EP voice
# also has a 40% chance of pulling from the fetched Galaxy Electric Pianos
# soundfont instead of GeneralUser-GS's single Rhodes patch.
def render_pad_morph_fluidsynth(path, pad_events, duration)
  @render_used_fluidsynth_pad = true
  ep_path = "#{path}.ep.wav"
  warm_path = "#{path}.warm.wav"
  texture_path = "#{path}.texture.wav"
  ep_mix = 1.0
  warm_mix = 0.68
  # Use the actual patch SF2 (Galaxy EP / Supersaw Prophet), not always GeneralUser.
  ep_voice = patch_voice_for(prefer_galaxy_ep(@render_ep_patch || synth_patch_by_id(:rhodes_mark1))) ||
             { sf2: pad_soundfont_path, bank: 0, program: PAD_GM_PROGRAM, patch: nil }
  warm_voice = patch_voice_for(@render_warm_patch || synth_patch_by_id(:prophet_5_pad)) ||
               { sf2: pad_soundfont_path, bank: 0, program: 89, patch: nil }
  ep_midi = "#{ep_path}.smf.mid"
  _, ep_anchor = write_smf_morph(ep_midi, pad_events, duration:, role: :ep,
                                midi_fx: midi_fx_specs_for_role(:ep, ep_voice[:patch]))
  ep_mix = ep_anchor&.fetch(:mix, ep_voice[:patch]&.fetch(:mix, 1.2) || 1.2) || 1.2
  fluidsynth_render!(ep_path, ep_voice[:sf2], ep_midi,
                     gain: ep_anchor&.fetch(:fs_gain, ep_voice[:patch]&.fetch(:fs_gain, 1.7) || 1.7) || 1.7)
  FileUtils.rm_f(ep_midi)

  warm_midi = "#{warm_path}.smf.mid"
  _, warm_anchor = write_smf_morph(warm_midi, pad_events, duration:, role: :warm,
                                   midi_fx: midi_fx_specs_for_role(:warm, warm_voice[:patch]))
  warm_mix = warm_anchor&.fetch(:mix, warm_voice[:patch]&.fetch(:mix, 0.9) || 0.9) || 0.9
  fluidsynth_render!(warm_path, warm_voice[:sf2], warm_midi,
                     gain: warm_anchor&.fetch(:fs_gain, warm_voice[:patch]&.fetch(:fs_gain, 1.55) || 1.55) || 1.55)
  FileUtils.rm_f(warm_midi)

  texture_voice = resolve_texture_voice
  if texture_voice
    texture_midi = "#{texture_path}.smf.mid"
    write_pad_smf(texture_midi, pad_events, program: texture_voice[:program], bank: texture_voice[:bank],
                  duration:, patch: texture_voice[:patch], role: :texture)
    fluidsynth_render!(texture_path, texture_voice[:sf2], texture_midi,
                       gain: texture_voice[:patch]&.fetch(:fs_gain, 1.2) || 1.2)
    FileUtils.rm_f(texture_midi)
  end

  inputs = ["-i", ep_path, "-i", warm_path]
  filt = "[0:a]apad=whole_dur=#{duration}[ep];" \
         "[1:a]apad=whole_dur=#{duration}[warmsrc];" \
         "[warmsrc]asplit=2[w1][w2];" \
         "[w1]asetrate=44100*1.0022,aresample=44100[wup];" \
         "[w2]asetrate=44100*0.9978,aresample=44100[wdown];" \
         "[wup][wdown]amix=inputs=2:weights=0.52 0.52:duration=first:normalize=0[wdetuned];" \
         "[ep][wdetuned]amix=inputs=2:weights=#{ep_mix} #{warm_mix}:duration=first:normalize=0[blend]"
  map_label = "[blend]"
  if texture_voice && File.exist?(texture_path)
    filt += ";[2:a]apad=whole_dur=#{duration}[tex];[blend][tex]amix=inputs=2:weights=1.0 #{texture_voice[:patch]&.fetch(:mix, 0.15) || 0.15}:duration=first:normalize=0[blend2]"
    map_label = "[blend2]"
    inputs << "-i" << texture_path
  end
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", map_label, "-c:a", "pcm_s16le", path
  FileUtils.rm_f(ep_path)
  FileUtils.rm_f(warm_path)
  FileUtils.rm_f(texture_path)
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(-24.0, 18.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=280:t=o:w=1:g=1.2,equalizer=f=1800:t=h:w=1200:g=0.7," \
      "volume=#{boost_db.round(2)}dB,alimiter=limit=0.95:level_out=0.96",
      "-c:a", "pcm_s16le", "#{path}.pad.wav"
  FileUtils.mv("#{path}.pad.wav", path)
  path
end

def pad_layer_specs_for_voice(voice)
  stack = PAD_LAYER_STACKS[voice]
  return stack if stack && ENV.fetch("PAD_LAYERS", "1") != "0"
  preset = PAD_VOICE_PRESETS[voice] || PAD_VOICE_PRESETS[:stack_soul]
  layers = []
  layers << { id: preset[:ep], mix: 1.15, role: :ep } if preset[:ep]
  layers << { id: preset[:warm], mix: 0.85, role: :warm } if preset[:warm]
  layers << { id: preset[:warm2], mix: 0.55, role: :warm } if preset[:warm2]
  layers << { id: preset[:texture], mix: 0.3, role: :texture } if preset[:texture]
  layers
end

def render_one_pad_layer!(voice_path, pad_events, duration, voice, role)
  if voice[:patch]&.dig(:native) && native_fm_layers_enabled?
    return render_native_pad_layer!(voice_path, pad_events, duration, voice[:patch])
  end
  midi_path = "#{voice_path}.smf.mid"
  write_pad_smf(midi_path, pad_events, program: voice[:program], bank: voice[:bank],
                duration:, patch: voice[:patch], role:)
  fs_gain = voice[:patch]&.fetch(:fs_gain, 1.5) || 1.5
  fluidsynth_render!(voice_path, voice[:sf2], midi_path, gain: fs_gain)
  FileUtils.rm_f(midi_path)
  return unless voice[:patch]&.dig(:fx) && tool_available?("ffmpeg")
  fx_tmp = "#{voice_path}.fx.wav"
  begin
    sh! "ffmpeg", "-y", "-i", voice_path, "-af", voice[:patch][:fx], "-c:a", "pcm_s16le", fx_tmp
    FileUtils.mv(fx_tmp, voice_path)
  rescue StandardError => e
    warn "patch fx skipped (#{voice[:patch][:id]}): #{e.message}"
    FileUtils.rm_f(fx_tmp)
  end
end

def render_pad_via_fluidsynth(path, pad_events, duration)
  # Morph path is opt-in only — multi-layer stack is the quality default.
  return render_pad_morph_fluidsynth(path, pad_events, duration) if synth_morph_enabled? && ENV["PAD_LAYERS"] == "0"
  @render_used_fluidsynth_pad = true
  voice_key = ENV["PAD_VOICE"]&.downcase&.to_sym
  specs = pad_layer_specs_for_voice(voice_key)
  if specs.nil? || specs.empty?
    # Fallback: Rhodes front, Prophet bed (not Moog-heavy).
    specs = [
      { id: :rhodes_mark1, mix: 1.4, role: :ep },
      { id: :prophet_5_pad, mix: 1.0, role: :warm },
      { id: :prophet_6_warm, mix: 0.65, role: :warm },
    ]
  end
  # Always force at least EP + two warm beds when stack requested.
  if ENV.fetch("PAD_LAYERS", "1") != "0" && specs.length < 3
    specs = PAD_LAYER_STACKS[:stack_soul]
  end

  rendered = []
  specs.each_with_index do |spec, i|
    patch = synth_patch_by_id(spec[:id])
    next unless patch
    # EP layers: Galaxy bank when available. Warm layers keep their own sf2
    # (Prophet → supersaw, Moog → default GM, …).
    patch = prefer_galaxy_ep(patch) if (spec[:role] || :warm) == :ep
    voice = patch_voice_for(patch) || resolve_ep_voice
    voice = voice.merge(patch:) if voice[:patch].nil?
    layer_path = "#{path}.L#{i}.wav"
    render_one_pad_layer!(layer_path, pad_events, duration, voice, spec[:role] || :warm)
    next unless File.file?(layer_path)
    # Unison detune on warm layers only (width without mush).
    if spec[:role] == :warm && i.positive?
      det = "#{layer_path}.det.wav"
      sh! "ffmpeg", "-y", "-i", layer_path, "-filter_complex",
          "[0:a]asplit=2[a][b];[a]asetrate=#{SAMPLE_RATE}*1.0018,aresample=#{SAMPLE_RATE}[u];" \
          "[b]asetrate=#{SAMPLE_RATE}*0.9982,aresample=#{SAMPLE_RATE}[d];" \
          "[u][d]amix=inputs=2:weights=0.5 0.5:normalize=0",
          "-c:a", "pcm_s16le", det
      FileUtils.mv(det, layer_path) if File.file?(det)
    end
    rendered << [layer_path, spec[:mix].to_f]
  end
  if rendered.empty?
    return render_native_pad_wav(path, pad_events, duration)
  end
  if rendered.length == 1
    FileUtils.mv(rendered[0][0], path)
  else
    inputs = rendered.flat_map { |(p, _)| ["-i", p] }
    labels = rendered.each_index.map { |i| "p#{i}" }
    filt_parts = rendered.each_with_index.map do |(_, mix), i|
      "[#{i}:a]apad=whole_dur=#{duration},volume=#{mix}[#{labels[i]}]"
    end
    weights = rendered.map { |(_, m)| m }.join(" ")
    filt = "#{filt_parts.join(';')};" \
           "#{labels.map { |l| "[#{l}]" }.join}amix=inputs=#{rendered.length}:weights=#{weights}:" \
           "duration=first:normalize=0[blend]"
    sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", "[blend]", "-c:a", "pcm_s16le", path
    rendered.each { |(p, _)| FileUtils.rm_f(p) }
  end
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(-24.0, 20.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=280:t=o:w=1:g=1.6,equalizer=f=900:t=o:w=1.2:g=0.8," \
      "equalizer=f=2200:t=h:w=1400:g=1.0,volume=#{boost_db.round(2)}dB," \
      "alimiter=limit=0.95:level_out=0.97",
      "-c:a", "pcm_s16le", "#{path}.pad.wav"
  FileUtils.mv("#{path}.pad.wav", path)
  path
end
