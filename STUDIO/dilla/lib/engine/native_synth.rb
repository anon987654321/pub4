# frozen_string_literal: true
#
# The native Ruby synthesiser: waveforms, FM, pad rendering.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


STREAM_CHUNK_SECONDS = 4
PAD_RENDER_SAMPLE_RATE = 22_050

def soft_clip_sample(sample, knee: 0.85)
  magnitude = sample.abs
  return sample if magnitude <= knee

  sample.negative? ? -(knee + (1.0 - knee) * Math.tanh((magnitude - knee) / (1.0 - knee))) :
                     knee + (1.0 - knee) * Math.tanh((magnitude - knee) / (1.0 - knee))
end

def soft_clip_stereo_chunk!(left, right)
  left.map! { |sample| soft_clip_sample(sample) }
  right.map! { |sample| soft_clip_sample(sample) }
end

# Write long buses incrementally. At 44.1 kHz a five-minute stereo Float array
# can exceed a gigabyte in Ruby; fixed-size chunks keep the render bounded while
# preserving oscillator phase and one-shot tails across chunk boundaries.
def write_stereo_chunks(path, duration, chunk_seconds: STREAM_CHUNK_SECONDS)
  total_frames = (duration * SAMPLE_RATE).ceil
  chunk_frames = [(chunk_seconds * SAMPLE_RATE).to_i, 1].max
  stdin, stdout, stderr, wait = Open3.popen3(
    "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", SAMPLE_RATE.to_s,
    "-ac", "2", "-i", "-", "-c:a", "pcm_s16le", path
  )
  out_reader = Thread.new { stdout.read }
  err_reader = Thread.new { stderr.read }
  chunk_start = 0
  while chunk_start < total_frames
    count = [chunk_frames, total_frames - chunk_start].min
    left = Array.new(count, 0.0)
    right = Array.new(count, 0.0)
    yield chunk_start, count, left, right
    # A fixed transfer curve is invariant across chunk boundaries; per-chunk
    # normalization would audibly pump a sustained pad every four seconds.
    soft_clip_stereo_chunk!(left, right)
    interleaved = Array.new(count * 2)
    count.times do |i|
      interleaved[i * 2] = left[i]
      interleaved[i * 2 + 1] = right[i]
    end
    stdin.write(interleaved.pack("e*"))
    chunk_start += count
  end
  stdin.close
  status = wait.value
  out_reader.value
  error = err_reader.value
  abort "wav stream failed: #{error}" unless status.success?
  path
ensure
  stdin&.close unless stdin&.closed?
end

def overlap_window(event_frame, event_frames, chunk_start, chunk_frames)
  overlap_start = [event_frame, chunk_start].max
  overlap_end = [event_frame + event_frames, chunk_start + chunk_frames].min
  return if overlap_end <= overlap_start

  [overlap_start - chunk_start, overlap_start - event_frame, overlap_end - overlap_start]
end

def fm_native_enabled?
  return false if ENV["FM_NATIVE"] == "0"
  return true if ENV["FM_NATIVE"] == "1"
  synth_morph_enabled? || lead_morph_enabled?
end

def fm_ratio_for_chord(event_idx)
  FM_RATIO_POOL[event_idx % FM_RATIO_POOL.length]
end

def fm_mod_ratio_expr(m_start, m_end, sustain, irrational:)
  return m_start.round(4).to_s unless irrational && m_start != m_end
  s = [sustain, 0.01].max.round(4)
  ms = m_start.round(4)
  me = m_end.round(4)
  "#{ms}+(#{me}-#{ms})*min(1,t/#{s})"
end

def fm_index_from_velocity(velocity, base_index:, role: :pad)
  vel = velocity.to_f.clamp(0.05, 1.0)
  scale = role == :xlead ? FM_INDEX_VEL_SCALE : (FM_INDEX_VEL_SCALE * 0.75)
  (base_index * (0.45 + vel * scale * 0.18)).round(3)
end

def fm_mod_envelope(role: :pad, atk: nil, decay: nil, sustain_level: nil)
  case role
  when :xlead
    a = (atk || 0.004).round(4)
    d = (decay || 0.28).round(4)
    s = (sustain_level || 0.35).round(3)
  else
    a = ((atk || 0.004) * 2.5).round(4)
    d = ((decay || 0.28) * 0.55).round(4)
    s = ((sustain_level || 0.35) * 0.9).round(3)
  end
  "min(1,pow(t/#{[a, 0.001].max},0.9))*((1-#{s})*exp(-t*#{d})+#{s})"
end

def native_fm_waveform_body(frequency, index_expr:, bloom: 0.2, drift: "1", detune: 0.004,
                            feedback: 0.0, phase_seed: 0.0, mod_ratio_expr: "1")
  f = frequency.round(4)
  det_up = (frequency * (1.0 + detune)).round(4)
  f_m = "(#{f}*(#{mod_ratio_expr}))"
  mod = "sin(2*PI*#{f_m}*#{drift}*t+#{phase_seed.round(3)})"
  phase_arg = "2*PI*#{f}*#{drift}*t+(#{index_expr})*#{mod}"
  fb = feedback.to_f.round(3)
  phase_arg = "#{phase_arg}+#{fb}*sin(#{phase_arg})" if fb.positive?
  carrier = "sin(#{phase_arg})"
  "0.70*#{carrier}+#{bloom.round(3)}*sin(2*PI*#{f}*#{drift}*t)+0.12*sin(2*PI*#{det_up}*#{drift}*t)"
end

# Additive (band-limited) sawtooth as an ffmpeg expression: sum sin(2*PI*n*f*t)/n
# for n = 1..N. Every other saw in native_waveform_body is the naive
# 2*mod(f*t,1)-1, whose instantaneous phase reset generates harmonics all the way
# up and folds everything above Nyquist back down as inharmonic grit -- audible
# as fizz on sustained pads. Summing partials instead is anti-aliased by
# construction: N is capped so N*f stays under Nyquist, so high notes simply get
# fewer partials. (PolyBLEP would be the usual fix, but it is a per-sample
# technique and this path emits an expression string for aevalsrc, not a Ruby
# sample loop -- see archive/hiphop_techno_experiment.rb for the sample-loop
# version.) HARMONIC_CAP keeps the expression from exploding: a chord is ~5
# voices x 3 detuned oscillators x N terms, per event.
SAW_HARMONIC_CAP = (ENV["SAW_HARMONICS"] || 8).to_i.clamp(2, 24)

def band_limited_saw_expr(frequency, drift)
  nyquist = SAMPLE_RATE / 2.0
  n_max = [(nyquist / frequency).floor, SAW_HARMONIC_CAP].min
  n_max = 1 if n_max < 1
  (1..n_max).map do |n|
    "#{(1.0 / n).round(4)}*sin(2*PI*#{(frequency * n).round(4)}*#{drift}*t)"
  end.join("+")
end

def native_waveform_body(frequency, wave:, bloom: 0.2, drift: "1", detune: 0.004, phase_seed: 0.0,
                         fm_index_expr: nil, mod_ratio_expr: nil, fm_feedback: 0.0)
  f = frequency.round(4)
  det_up = (frequency * (1.0 + detune)).round(4)
  det_dn = (frequency * (1.0 - detune)).round(4)
  case wave
  when :analog_pad
    # Three-oscillator detuned saw stack, the classic warm analog pad. The
    # detune has to be in real cents to do anything: the beating between
    # oscillators IS the sound. (A proposal that suggested this used
    # [-0.03, 0, 0.03] "cents" applied as 2**(c/1200) -- 0.0000173%, so all
    # three oscillators came out bit-identical and it was just a louder saw.)
    cents = (ENV["ANALOG_PAD_DETUNE_CENTS"] || 7.0).to_f.clamp(0.0, 50.0)
    spread = ->(c) { (frequency * (2.0**(c / 1200.0))).round(4) }
    [
      "0.42*(#{band_limited_saw_expr(spread.call(-cents), drift)})",
      "0.36*(#{band_limited_saw_expr(f, drift)})",
      "0.42*(#{band_limited_saw_expr(spread.call(cents), drift)})",
      # Sub octave for body, and a touch of breath noise for analog air.
      "#{bloom.round(3)}*sin(2*PI*#{(frequency * 0.5).round(4)}*#{drift}*t)",
      "0.015*(random(0)-0.5)",
    ].join("+")
  when :saw
    "0.55*(2*mod(#{f}*#{drift}*t,1)-1)+0.22*(2*mod(#{det_up}*#{drift}*t,1)-1)+0.18*(2*mod(#{det_dn}*#{drift}*t,1)-1)"
  # :triangle and :square took a detune: and threw it away — every caller that
  # set one got a single-frequency tone with no beating, and nothing said so.
  # The detuned partial is quiet (0.18) so these keep their shape; what they
  # gain is movement.
  when :triangle
    "0.62*(2*abs(2*mod(#{f}*#{drift}*t,1)-1)-1)+0.20*sin(2*PI*#{f}*#{drift}*t)" \
      "+0.18*(2*abs(2*mod(#{det_up}*#{drift}*t,1)-1)-1)"
  when :square
    "0.48*(2*floor(2*mod(#{f}*#{drift}*t,1))-1)+0.28*sin(2*PI*#{f * 2.0}*#{drift}*t)" \
      "+0.18*(2*floor(2*mod(#{det_dn}*#{drift}*t,1))-1)"
  when :pwm
    pw = "0.35+0.15*sin(2*PI*0.4*t+#{phase_seed.round(3)})"
    "0.5*(2*floor(mod(#{f}*#{drift}*t,1)/(#{pw}))-1)+0.25*sin(2*PI*#{det_up}*#{drift}*t)"
  when :fm
    idx = fm_index_expr || "2.2"
    native_fm_waveform_body(frequency, index_expr: idx, bloom:, drift:,
                                   detune:, feedback: fm_feedback, phase_seed:,
                                   mod_ratio_expr: mod_ratio_expr || "1.5")
  when :organ
    # Detuned on the fundamental only. A drawbar organ's movement comes from
    # slightly out-of-tune tonewheels beating against each other, so the
    # detune: this took and discarded is exactly the parameter it wanted.
    "0.42*sin(2*PI*#{f}*#{drift}*t)+0.28*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.18*sin(2*PI*#{f * 3.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 4.0}*#{drift}*t)" \
      "+0.16*sin(2*PI*#{det_up}*#{drift}*t)"
  when :bowed
    "0.55*sin(2*PI*#{f}*#{drift}*t)+0.25*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 3.0}*#{drift}*t)"
  when :juno
    "0.50*sin(2*PI*#{f}*#{drift}*t)+0.30*sin(2*PI*#{det_up}*#{drift}*t)+0.20*sin(2*PI*#{det_dn}*#{drift}*t)+" \
    "#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  when :moog
    sub = (frequency * 0.5).round(4)
    f2 = (frequency * 2.0).round(4)
    # Ladder-ish: saw stack + sub octave, soft triangle body for warmth.
    "0.46*(2*mod(#{f}*#{drift}*t,1)-1)+0.20*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.14*(2*mod(#{det_dn}*#{drift}*t,1)-1)+#{bloom.round(3)}*(2*mod(#{sub}*#{drift}*t,1)-1)+" \
    "0.12*(2*abs(2*mod(#{f}*#{drift}*t,1)-1)-1)+0.08*sin(2*PI*#{f2}*#{drift}*t)"
  when :prophet
    det2 = (frequency * (1.0 + detune * 1.8)).round(4)
    det3 = (frequency * (1.0 - detune * 1.8)).round(4)
    # Prophet-5 unison: five slightly detuned saws + gentle 2nd harmonic.
    "0.30*(2*mod(#{f}*#{drift}*t,1)-1)+0.20*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.20*(2*mod(#{det_dn}*#{drift}*t,1)-1)+0.14*(2*mod(#{det2}*#{drift}*t,1)-1)+" \
    "0.12*(2*mod(#{det3}*#{drift}*t,1)-1)+#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)+" \
    "0.06*sin(2*PI*#{f}*#{drift}*t)"
  else # :rhodes default — tine fundamental + odd harmonics + stereo detune
    f3 = (frequency * 3.0).round(4)
    f5 = (frequency * 5.0).round(4)
    bell = "exp(-t*18)*sin(2*PI*#{f * 4.0}*t)"
    "0.58*sin(2*PI*#{f}*#{drift}*t)+#{bloom.round(3)}*sin(2*PI*#{f3}*#{drift}*t)+" \
    "0.06*sin(2*PI*#{f5}*#{drift}*t)+0.22*sin(2*PI*#{det_up}*#{drift}*t)+" \
    "0.22*sin(2*PI*#{det_dn}*#{drift}*t)+0.12*#{bell}"
  end
end

def native_pad_voice_expression(hz, amp, voice_i, pan, phase_seed, native_patch: nil,
                                event_i: 0, velocity: 0.72, sustain: 8.0)
  frequency = hz.round(4)
  drift = "(1+0.0014*sin(2*PI*0.065*t+#{phase_seed.round(3)}))"
  wave = @render_pad_native_wave || DillaLofiMachine.native_wave_for_pad
  native = native_patch&.dig(:native) || @render_native_patch&.dig(:native) ||
           { wave:, detune: 0.004, bloom: 0.28 }
  pad_gain = @render_pad_gain || 1.0
  wave_sym = native[:wave] || :rhodes
  fm_index_expr = nil
  mod_ratio_expr = nil
  fm_feedback = native[:fm_feedback] || 0.0
  if wave_sym == :fm && fm_native_enabled?
    # A fixed native[:fm_ratio] lets a patch keep an authentic, unchanging
    # C:M ratio (e.g. 14:1 for an e-piano tine) instead of the rotating
    # FM_RATIO_POOL every other :fm voice shares.
    ratio = native[:fm_ratio] || fm_ratio_for_chord(event_i + voice_i)
    mod_ratio_expr = fm_mod_ratio_expr(ratio[:m], ratio[:target_m], sustain, irrational: ratio[:irrational])
    base_idx = fm_index_from_velocity(velocity, base_index: native[:fm_index] || FM_INDEX_BASE_PAD, role: :pad)
    mod_env = fm_mod_envelope(role: :pad)
    fm_index_expr = "(#{base_idx})*#{mod_env}"
    fm_feedback = native[:fm_feedback] || FM_FEEDBACK_DEFAULT * 0.65
  end
  body = native_waveform_body(frequency, wave: wave_sym, bloom: native[:bloom] || 0.2,
                              drift:, detune: native[:detune] || 0.004, phase_seed:,
                              fm_index_expr:, mod_ratio_expr:,
                              fm_feedback:)
  breathe = "(0.80+0.20*sin(2*PI*#{(0.16 + voice_i * 0.025).round(3)}*t+#{phase_seed.round(3)}))"
  atk = (@render_pad_attack_sec || 0.072).round(4)
  # native[:pad_release] lets a patch decay independently of the global pad
  # release -- a bell/tine transient needs a much faster exp(-t*rel) decay
  # than the sustained body layer it's mixed under.
  rel = (native[:pad_release] || @render_pad_release_decay || 0.07).round(4)
  env = "min(1,pow(t/#{atk},1.15))*exp(-t*#{rel})*#{breathe}"
  ["#{(amp * pad_gain).round(6)}*#{(0.5 - pan * 0.5).round(4)}*#{env}*#{body}",
   "#{(amp * pad_gain).round(6)}*#{(0.5 + pan * 0.5).round(4)}*#{env}*#{body}"]
end

def render_native_pad_wav(path, pad_events, duration)
  filters = []
  labels = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), event_i|
    next unless chord
    left_parts = []
    right_parts = []
    chord[:hz].sort.each_with_index do |hz, voice_i|
      pan = [-0.38, -0.12, 0.14, 0.36, 0.22][voice_i % 5]
      amp = velocity * (0.058 + voice_i * 0.0048)
      pair = native_pad_voice_expression(hz, amp, voice_i, pan, event_i * 0.55 + voice_i * 0.9,
                                        event_i:, velocity:, sustain:)
      left_parts << pair[0]
      right_parts << pair[1]
      next unless voice_i.zero?

      sub_pair = native_pad_voice_expression(hz * 0.5, amp * 0.42, voice_i + 5, pan, event_i * 0.61,
                                             event_i:, velocity: velocity * 0.82, sustain:)
      left_parts << sub_pair[0]
      right_parts << sub_pair[1]
    end
    delay = [(time * 1000.0).round, 0].max
    label = "pad#{event_i}"
    # The pad is low-passed below 3 kHz later, so a half-rate oscillator bed is
    # lossless for its audible band and roughly halves long-render DSP time.
    filters << "aevalsrc=exprs='#{expr_sum(left_parts)}|#{expr_sum(right_parts)}':d=#{sustain.round(4)}:s=#{PAD_RENDER_SAMPLE_RATE}," \
               "adelay=#{delay}|#{delay}[#{label}]"
    labels << "[#{label}]"
  end
  if labels.empty?
    filters << "anullsrc=r=#{PAD_RENDER_SAMPLE_RATE}:cl=stereo:d=#{duration}[pads]"
  else
    filters << "#{labels.join}amix=inputs=#{labels.length}:duration=longest:normalize=0," \
               "atrim=0:#{duration},alimiter=limit=0.95:level_out=0.96[pads]"
  end
  sh_filter_complex!(filters.join(";"), "-map", "[pads]", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path)
  path
end

# Real per-hit synthesis (see native_pad_voice_expression) for one layer of
# a PAD_LAYER_STACKS entry -- the layered-mix counterpart to
# render_native_pad_wav above, which only ever renders one voice for the
# whole pad bed. Opt-in via NATIVE_FM_PADS=1; render_one_pad_layer! decides
# whether a given layer's patch routes here or through FluidSynth.
def native_fm_layers_enabled?
  ENV.fetch("NATIVE_FM_PADS", "0") != "0"
end

def render_native_pad_layer!(voice_path, pad_events, duration, patch)
  filters = []
  labels = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), event_i|
    next unless chord
    left_parts = []
    right_parts = []
    chord[:hz].sort.each_with_index do |hz, voice_i|
      pan = [-0.38, -0.12, 0.14, 0.36, 0.22][voice_i % 5]
      amp = velocity * (0.058 + voice_i * 0.0048) * (patch[:mix] || 1.0)
      pair = native_pad_voice_expression(hz, amp, voice_i, pan, event_i * 0.55 + voice_i * 0.9,
                                        native_patch: patch, event_i:, velocity:, sustain:)
      left_parts << pair[0]
      right_parts << pair[1]
    end
    delay = [(time * 1000.0).round, 0].max
    label = "pad#{event_i}"
    filters << "aevalsrc=exprs='#{expr_sum(left_parts)}|#{expr_sum(right_parts)}':d=#{sustain.round(4)}:s=#{PAD_RENDER_SAMPLE_RATE}," \
               "adelay=#{delay}|#{delay}[#{label}]"
    labels << "[#{label}]"
  end
  if labels.empty?
    filters << "anullsrc=r=#{PAD_RENDER_SAMPLE_RATE}:cl=stereo:d=#{duration}[pads]"
  else
    filters << "#{labels.join}amix=inputs=#{labels.length}:duration=longest:normalize=0," \
               "atrim=0:#{duration},alimiter=limit=0.95:level_out=0.96[pads]"
  end
  sh_filter_complex!(filters.join(";"), "-map", "[pads]", "-c:a", "pcm_s16le", voice_path)
  voice_path
end
