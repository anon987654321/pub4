# frozen_string_literal: true
#
# The industrial techno renderer.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def industrial_techno_section(bar)
  case bar
  when 0..7   then :intro
  when 8..31  then :groove
  when 32..39 then :breakdown
  when 40..47 then :build
  when 48..111 then :main
  when 112..119 then :peak
  else :outro
  end
end

# Arranged industrial techno: intro → groove → breakdown → build → main → peak → outro.
def industrial_techno_schedule(n_bars, beat_p, roots = nil)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (bar_p / 16.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }

  n_bars.times do |bar|
    base    = bar * bar_p
    section = industrial_techno_section(bar)

    case section
    when :intro
      events[:kick] << [base, 0.82] if bar % 4 == 0
      events[:kick] << [base + step_p * 8, 0.55] if bar >= 4
    when :breakdown
      events[:kick] << [base, 0.65] if bar.even?
      events[:kick] << [base + step_p * 8, 0.45] if bar >= 36
    else
      [0, 4, 8, 12].each do |step|
        vel = section == :peak ? 1.0 : 0.9
        events[:kick] << [base + step * step_p, vel]
      end
      events[:kick] << [base + step_p * 14, 0.62] if section == :peak && bar.odd?
      events[:kick] << [base + step_p * 15, 0.48] if section == :build && bar >= 44
    end

    unless section == :intro && bar < 2
      clap_vel = section == :peak ? 0.78 : 0.62
      events[:clap] << [base + step_p * 4, clap_vel * 0.85] unless section == :breakdown && bar < 36
      events[:clap] << [base + step_p * 12, clap_vel]
      events[:clap] << [base + step_p * 14, 0.42] if section == :peak && bar % 2 == 1
    end

    hat_active = !(section == :breakdown && bar >= 34)
    16.times do |step|
      next unless hat_active
      seed = (bar * 97) + (step * 31)
      next if section == :groove && step.even? && seed % 9 == 0
      next if section == :main && step % 4 == 0 && seed % 11 == 0
      accent = step.odd? ? 1.08 : 1.0
      vel = (0.16 + (seed % 11) * 0.022) * accent
      vel *= 1.25 if section == :peak
      events[:hat] << [base + step * step_p, vel]
    end

    if hat_active && [1, 3, 5, 7].include?(bar % 8) && section != :intro
      events[:open] << [base + step_p * 6, section == :peak ? 0.42 : 0.32]
      events[:open] << [base + step_p * 14, 0.28] if section == :main || section == :peak
    end

    bass_active = section != :breakdown || bar < 35
    if bass_active
      acid_steps = section == :intro ? [0, 8] : [0, 2, 3, 5, 8, 10, 11, 14]
      acid_steps.each do |step|
        # With a progression to follow, the hit carries a target FREQUENCY and
        # render_sample_bus_wav resamples ind_bass_e to it. Without one it
        # carries a sample key and alternates E against Bb on bar arithmetic --
        # a fixed tritone, in every key, forever. That alternation is this
        # renderer's signature and is kept as the default; it is simply no
        # longer the only thing available.
        note = if roots
                 roots[(bar / 2) % roots.length]
               elsif ((bar / 2 + step) % 4) >= 2
                 :ind_bass_bb
               else
                 :ind_bass_e
               end
        vel  = section == :peak ? 0.82 : 0.68
        vel *= 0.5 if section == :intro
        events[:bass] << [base + step * step_p, vel, note]
      end
    end

    if section != :breakdown && bar % 8 == 7
      events[:stab] << [base + step_p * 4, 0.52]
      events[:stab] << [base + step_p * 12, 0.38] if section == :peak
    end
  end
  events
end

# Industrial techno: arranged 135 BPM groove, rumble sub, sidechain, dub space.
def render_industrial(destination = File.join(ROOT, "renders", "foundry_pulse.mp3"), bars_count = nil)
  require_tools! "ffmpeg"
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  ibpm     = ENV.fetch("IBPM", INDUSTRIAL_TECHNO_BPM.to_s).to_f
  beat_p   = (60.0 / ibpm).round(6)
  n_bars   = bars_count || (ENV["BARS"] ? bars : INDUSTRIAL_TECHNO_BARS)
  duration = (beat_p * 4.0 * n_bars).round(3)
  dotted_8th_ms = (3.0 * beat_p / 4.0 * 1000.0).round(1)
  # Same spine as techno: the progression's chord roots, folded into the register
  # this bass already worked in (41.2 Hz E1 to 58.27 Hz Bb1, so an octave from
  # E1 up).
  ind_roots = techno_harmony_roots(8, register: (38.0..76.0))
  dmesg("industrial harmony: bass follows #{ind_roots.uniq.length} chord root(s)",
        unit: "ind0", parent: "dilla0") if ind_roots
  events   = industrial_techno_schedule(n_bars, beat_p, ind_roots)

  kit = {
    ind_kick: load_mono_sample(drum_sample_path("ind_kick.wav")),
    ind_clap: load_mono_sample(drum_sample_path("ind_clap.wav")),
    ind_hat: load_mono_sample(drum_sample_path("ind_hat.wav")),
    open_hat: load_mono_sample(drum_sample_path("open_hat.wav")),
    ind_bass_e: load_mono_sample(drum_sample_path("ind_bass_e.wav")),
    ind_bass_bb: load_mono_sample(drum_sample_path("ind_bass_bb.wav")),
    ind_stab: load_mono_sample(drum_sample_path("ind_stab.wav")),
  }
  stab_hits = events[:stab].map { |t, v| [t, v, :ind_stab] }
  drum_tmp  = File.join(SCRATCH_DIR, "ind_drums.wav")
  render_sample_bus_wav(
    drum_tmp,
    events.merge(stab: stab_hits),
    duration,
    kit,
    kick: :ind_kick, clap: :ind_clap, hat: :ind_hat, open: :open_hat, bass: :ind_bass_e, stab: :ind_stab,
  )

  sides_path = File.join(STEM_DIR, "sides.mp3")
  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  sides_idx = nil
  if File.exist?(sides_path)
    command += ["-stream_loop", "-1", "-i", sides_path]
    sides_idx = idx
    idx += 1
  end
  command += ["-f", "lavfi", "-i", "aevalsrc='0.55*sin(2*PI*38*t)*exp(-mod(t,#{beat_p})*1.8)':d=#{duration}:s=#{SAMPLE_RATE}"]
  rumble_idx = idx
  idx += 1
  command += ["-f", "lavfi", "-i", "anoisesrc=color=white:amplitude=0.022:d=#{duration}:r=#{SAMPLE_RATE}:seed=#{noise_seed(15)}"]
  noise_idx = idx

  filt = []
  filt << "[0:a]aformat=channel_layouts=stereo,asplit=2[drums][drums_sc]"
  filt << "[#{rumble_idx}:a]aformat=channel_layouts=mono,lowpass=f=95,equalizer=f=48:t=o:w=0.8:g=8,volume=0.42[rumble]"
  if sides_idx
    filt << "[#{sides_idx}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
            "highpass=f=180,lowpass=f=8500,volume=0.18[texture]"
  end
  filt << "[#{noise_idx}:a]highpass=f=400,lowpass=f=5000,volume=0.04[noise]"
  mix_in = ["[drums]", "[rumble]"]
  mix_w  = ["1.0", "0.55"]
  if sides_idx
    mix_in << "[texture]"
    mix_w << "0.28"
  end
  mix_in << "[noise]"
  mix_w << "0.06"
  filt << "#{mix_in.join}amix=inputs=#{mix_in.length}:weights=#{mix_w.join(' ')}:duration=first[bed]"
  filt << "[bed][drums_sc]sidechaincompress=threshold=-24dB:ratio=8:attack=0.5:release=110:level_sc=0.9[pumped]"
  filt << "[pumped]asplit=2[dry][rev_send]"
  filt << "[rev_send]highpass=f=100,lowpass=f=9000,aecho=0.7:0.8:480|960|1920|3200:0.6|0.45|0.3|0.18[verb]"
  filt << "[dry][verb]amix=inputs=2:weights=0.62 0.38[with_verb]"
  filt << "[with_verb]asplit=2[dry2][dly]"
  filt << "[dly]highpass=f=280,aecho=0.55:0.65:#{dotted_8th_ms}|#{(dotted_8th_ms * 2).round(1)}|#{(dotted_8th_ms * 3).round(1)}:0.75|0.55|0.35[echo]"
  filt << "[dry2][echo]amix=inputs=2:weights=0.7 0.3[pre]"
  sat = Math.tanh(3.8).round(6)
  filt << "[pre]extrastereo=m=1.18[wide]"
  filt << "[wide]aeval=exprs='tanh(3.8*val(0))/#{sat}|tanh(3.8*val(1))/#{sat}'[satd]"
  filt << "[satd]acompressor=threshold=-14dB:ratio=10:attack=1:release=45:makeup=3.5[comp]"
  filt << "[comp]equalizer=f=52:t=o:w=0.65:g=6,equalizer=f=120:t=o:w=1:g=2,equalizer=f=9500:t=o:w=2:g=-5[eq]"
  filt << "[eq]acrusher=bits=14:samples=2:mix=0.08[pre_master]"
  filt.concat(master_bus_filters("pre_master"))

  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  mix_note = sonitex_enabled? ? sonitex_label : "dry"
  normalise_genre_master!(destination, :techno)
  puts "wrote #{destination} (#{ibpm.to_i} BPM industrial techno, #{n_bars} bars, #{mix_note})"
end
