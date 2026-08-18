# frozen_string_literal: true
#
# Drum kits: generating them, external kits, chopping them.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# kick.wav deliberately excluded: it's a 4-layer synthesis (sample + sub
# drop + body punch + click transient via layered_kick_sample) tuned
# across many iterations — swapping its base sample for a random external
# one-shot and re-layering synthesis on top produced an unpredictable,
# bad-sounding result ("that stupid kickdrum sound" — direct feedback).
DRUM_SAMPLE_SUBDIR = {
  "snare.wav" => "snares", "hat.wav" => "hi-hats",
  "open_hat.wav" => "open-hats", "ghost.wav" => "claps", "bass_43.wav" => "808s",
}.freeze
EXTERNAL_DRUM_KITS = %w[01-hard-trap 02-bounce 03-soulful-vintage].freeze

# One choice per render (called once at the top of render_dilla, not per
# sample), matching how EP/warm-pad/lead voices already vary per render
# rather than per hit — a real drum kit doesn't swap character mid-hit.
# pick_synth_patches! caches its choices in @render_*_patch and guards them
# with `||=` / `&& !@render_*`, so nothing re-rolls a voice while the cache is
# populated. That invariant used to live in the callers: stream_rotate_voices_
# and_arps! cleared the cache by hand, but play's quality-gate retry loop and
# default_render!'s retry did not -- so a rejected render was retried with a new
# seed but the *same* synth patches, i.e. the largest timbral lever was the one
# thing that couldn't change. Clearing here ties "new render identity" to "new
# voices" in one place, so no future caller has to remember.
def reset_render_patches!
  @render_ep_patch = @render_warm_patch = @render_lead_patch = nil
  @render_scale_lead_patch = @render_texture_patch = @render_native_patch = nil
  @render_arp_style = @render_scale_arp_style = nil
end

def pick_render_seed!
  DillaSeeds.apply!
  @render_seed = DillaSeeds.render_seed
  reset_render_patches!
  # Bridge into ENV so lib modules (DillaGroove) that don't share this
  # top-level instance variable can still vary their per-bar phrase/pattern
  # choices by render instead of being purely a function of bar number.
  ENV["DILLA_RENDER_SEED"] = @render_seed.to_s
end

def pick_external_drum_kit!
  @current_external_kit = nil
  return unless ensure_external_assets_lazy!
  if (kit = ENV["EXTERNAL_KIT"]) && !kit.empty?
    kit_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit)
    if Dir.exist?(kit_dir)
      @current_external_kit = kit
      return
    end
  end
  track = (ENV["TRACK"] || "").to_s
  soul = DillaHarmony.soul_profile?(track) || ENV["DILLA_STREAMING"] == "1"
  roll = render_rand("external_kit_roll")
  @current_external_kit = if soul
                            if roll < 0.72
                              "03-soulful-vintage"
                            elsif roll < 0.88
                              "02-bounce"
                            else
                              render_pick(EXTERNAL_DRUM_KITS, "external_kit_soul")
                            end
                          elsif roll < 0.35
                            render_pick(EXTERNAL_DRUM_KITS, "external_kit_plain")
                          end
end

# Hats/snares/claps synthesized from a bandpassed noise burst (generate_drum_kit!)
# are thin/harsh by construction — pure noise decaying in ~20ms has no body.
# pick_external_drum_kit! rolls a real-sample kit only 35-88% of the time
# (track-dependent); these three roles matter enough to the drum sound that
# they should reach for real samples whenever the (already-fetched) kit
# cache exists, not just when the roll happened to land on it.
ALWAYS_SAMPLED_DRUM_ROLES = %w[hat.wav open_hat.wav snare.wav ghost.wav].freeze

def drum_sample_path(name)
  # Explicit opt-in beats the passive custom-dir cache -- FM_DRUMS=1 is a
  # deliberate whole-kit choice, not a per-role override.
  if fm_drums_enabled?
    fm = File.join(FM_DRUM_DIR, name)
    return fm if File.exist?(fm)
  end

  custom = File.join(CUSTOM_DRUM_DIR, name)
  return custom if File.exist?(custom)

  subdir = DRUM_SAMPLE_SUBDIR[name]
  if subdir
    kit = @current_external_kit
    kit ||= "03-soulful-vintage" if ALWAYS_SAMPLED_DRUM_ROLES.include?(name) && Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
    if kit
      kit_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit, subdir)
      # .sort first: Dir.glob order is not guaranteed across filesystems, so an
      # index into an unsorted list is only stable on the machine that made it.
      picked = render_pick(Dir.glob(File.join(kit_dir, "*.wav")).sort, "kit:#{kit}:#{name}")
      return picked if picked
    end
  end

  File.join(DRUM_DIR, name)
end

def generate_drum_kit!
  require_tools! "ffmpeg"
  FileUtils.mkdir_p(DRUM_DIR)
  FileUtils.mkdir_p(CUSTOM_DRUM_DIR)
  force = ENV["FORCE_KIT"] == "1"
  sr = SAMPLE_RATE
  recipes = [
    ["kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.9*exp(-t*7.5)*sin(2*PI*(48+210*exp(-t*28))*t)+0.55*exp(-t*95)*sin(2*PI*3200*t)*between(t,0,0.006)':d=0.55:s=#{sr}"],
     "lowpass=f=180,acrusher=bits=12:samples=2:mix=0.42,equalizer=f=55:t=o:w=0.8:g=4,acompressor=threshold=-20dB:ratio=3:attack=3:release=50"],
    ["snare.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.32:color=white:amplitude=0.95:seed=#{noise_seed(2)}", "-f", "lavfi", "-i", "sine=f=195:d=0.32"],
     "[0:a]asplit=2[n][n2];[n]highpass=f=1200,lowpass=f=7000,aeval=exprs='val(0)*exp(-t*32)'[crack];" \
     "[n2]bandpass=f=350:w=500,aeval=exprs='val(0)*exp(-t*18)'[rattle];[1:a]aeval=exprs='val(0)*exp(-t*22)'[body];" \
     "[crack][rattle][body]amix=inputs=3:weights=0.75 0.35 0.45,acrusher=bits=10:samples=2:mix=0.38"],
    ["ghost.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.14:color=pink:amplitude=0.7:seed=#{noise_seed(3)}"],
     "highpass=f=900,lowpass=f=5500,aeval=exprs='val(0)*exp(-t*48)',volume=0.55"],
    ["hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.07:color=white:amplitude=1:seed=#{noise_seed(4)}"],
     "highpass=f=7500,lowpass=f=15000,aeval=exprs='val(0)*exp(-t*140)',acrusher=bits=8:samples=1:mix=0.55"],
    ["open_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.42:color=white:amplitude=0.85:seed=#{noise_seed(5)}"],
     "highpass=f=6000,bandpass=f=9000:w=5000,aeval=exprs='val(0)*exp(-t*9)'"],
    ["bass_43.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.75*exp(-t*1.1)*sin(2*PI*(43+5*sin(2*PI*0.28*t))*t)':d=1.35:s=#{sr}"],
     "lowpass=f=120,equalizer=f=50:t=o:w=1:g=6"],
    ["ind_kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.95*exp(-t*5.5)*sin(2*PI*(50+520*exp(-t*45))*t)':d=0.65:s=#{sr}"],
     "aeval=exprs='tanh(5.5*val(0))/tanh(5.5)',lowpass=f=140,equalizer=f=52:t=o:w=0.6:g=9,acompressor=threshold=-16dB:ratio=10:attack=1:release=35"],
    ["ind_clap.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.22:color=white:amplitude=1:seed=#{noise_seed(6)}"],
     "[0:a]asplit=3[a][b][c];[a]adelay=0|3,highpass=f=1400,aeval=exprs='val(0)*exp(-t*24)'[c1];" \
     "[b]adelay=12|15,highpass=f=1800,aeval=exprs='val(0)*exp(-(t-0.012)*30)'[c2];[c]bandpass=f=900:w=1800,aeval=exprs='val(0)*exp(-t*20)'[c3];" \
     "[c1][c2][c3]amix=inputs=3,acompressor=threshold=-14dB:ratio=6:attack=1:release=25"],
    ["ind_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.05:color=white:amplitude=1:seed=#{noise_seed(7)}"],
     "highpass=f=9000,aeval=exprs='val(0)*exp(-t*160)',equalizer=f=12000:t=o:w=2:g=4"],
    ["ind_bass_e.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(41.2*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_bass_bb.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(58.27*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_stab.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.35:color=white:amplitude=0.9:seed=#{noise_seed(8)}", "-f", "lavfi", "-i", "sine=f=164.81:d=0.35"],
     "[0:a]bandpass=f=280:w=900,aeval=exprs='val(0)*exp(-t*14)'[m];[1:a]aeval=exprs='val(0)*exp(-t*11)'[t];" \
     "[m][t]amix=inputs=2:weights=0.7 0.35,lowpass=f=2800"],
  ]
  recipes.each do |name, inputs, chain|
    dest = File.join(DRUM_DIR, name)
    next if File.exist?(dest) && !force
    if chain.include?("[") || chain.include?(";")
      sh! "ffmpeg", "-y", *inputs, "-filter_complex", chain, "-ar", SAMPLE_RATE.to_s, dest
    else
      sh! "ffmpeg", "-y", *inputs, "-af", chain, "-ar", SAMPLE_RATE.to_s, dest
    end
    puts "kit: #{name}"
  end
end

# True FM (operator modulates operator's frequency at audio rate), not the
# default kit's pitch-swept-sine/filtered-noise approach. Near-1:1 carrier
# ratio on the kick keeps it punchy/tonal; inharmonic (non-integer) ratios
# on hat/open_hat are the classic FM technique for bell/cymbal-like metallic
# timbre. A decaying mod index (index * exp(-t*k)) gives the bright-transient-
# collapsing-to-pure-tone character distinctive of FM percussion.
def generate_fm_drum_kit!
  require_tools! "ffmpeg"
  FileUtils.mkdir_p(FM_DRUM_DIR)
  force = ENV["FORCE_KIT"] == "1"
  sr = SAMPLE_RATE
  recipes = [
    ["kick.wav",
     # FM operator for the punch/click transient, plus a plain sub sine
     # (42Hz, slower decay) for body -- the FM element alone decays too
     # fast to carry real low-end weight now that this is the sole kick,
     # not a niche alternate. Gentle tanh saturation adds analog warmth.
     # A very low-level noise floor under the whole hit (not a burst)
     # keeps it from sounding too digitally clean for a kit modeled on
     # dusty analog hardware.
     ["-f", "lavfi", "-i", "aevalsrc='0.85*exp(-t*6)*sin(2*PI*55*t+6*exp(-t*30)*sin(2*PI*58*t))+0.35*exp(-t*9)*sin(2*PI*42*t)':d=0.6:s=#{sr}",
      "-f", "lavfi", "-i", "anoisesrc=d=0.6:color=pink:amplitude=0.02:seed=#{noise_seed(9)}"],
     "[0:a]aeval=exprs='tanh(1.8*val(0))/tanh(1.8)',lowpass=f=240[voice];" \
     "[1:a]lowpass=f=2500[floor];" \
     "[voice][floor]amix=inputs=2:duration=first,acompressor=threshold=-18dB:ratio=3:attack=2:release=45"],
    # Alternate kick voice for the kick/ind_kick alternation cycle
    # (KICK_SAMPLE_CYCLE) -- this was missing for the FM kit entirely, so
    # 1 in 4 kicks silently fell back to the old analog kit's ind_kick.wav
    # even with FM_DRUMS=1. Different carrier:modulator ratio (60:46 vs
    # 55:58) and slightly punchier decay for real per-alternation contrast.
    ["ind_kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.85*exp(-t*7)*sin(2*PI*60*t+7*exp(-t*34)*sin(2*PI*46*t))+0.32*exp(-t*10)*sin(2*PI*44*t)':d=0.55:s=#{sr}",
      "-f", "lavfi", "-i", "anoisesrc=d=0.55:color=pink:amplitude=0.02:seed=#{noise_seed(10)}"],
     "[0:a]aeval=exprs='tanh(2.0*val(0))/tanh(2.0)',lowpass=f=250[voice];" \
     "[1:a]lowpass=f=2500[floor];" \
     "[voice][floor]amix=inputs=2:duration=first,acompressor=threshold=-17dB:ratio=3.5:attack=2:release=40"],
    ["snare.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.8*exp(-t*18)*sin(2*PI*200*t+7*exp(-t*35)*sin(2*PI*330*t))':d=0.3:s=#{sr}",
      "-f", "lavfi", "-i", "anoisesrc=d=0.3:color=white:amplitude=0.9:seed=#{noise_seed(11)}",
      "-f", "lavfi", "-i", "anoisesrc=d=0.3:color=pink:amplitude=0.015:seed=#{noise_seed(12)}"],
     "[1:a]highpass=f=1500,lowpass=f=8000,aeval=exprs='val(0)*exp(-t*30)'[crack];" \
     "[2:a]lowpass=f=3000[floor];" \
     "[0:a][crack][floor]amix=inputs=3:weights=0.65 0.68 1,acompressor=threshold=-16dB:ratio=4:attack=2:release=40"],
    # Genuinely distinct voice, not just a quieter snare -- lower mod
    # index (more sine-pure, less metallic "ring") and no crack noise at
    # all, since real ghost notes are soft finger-taps, not scaled-down
    # backbeat hits.
    ["ghost.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.4*exp(-t*40)*sin(2*PI*190*t+2.5*exp(-t*45)*sin(2*PI*260*t))':d=0.13:s=#{sr}"],
     "highpass=f=600,lowpass=f=3500"],
    ["hat.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.85*exp(-t*90)*sin(2*PI*900*t+5*sin(2*PI*3150*t))':d=0.12:s=#{sr}"],
     "highpass=f=4000"],
    ["open_hat.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.75*exp(-t*10)*sin(2*PI*900*t+5*sin(2*PI*3150*t))':d=0.42:s=#{sr}"],
     "highpass=f=3500"],
  ]
  recipes.each do |name, inputs, chain|
    dest = File.join(FM_DRUM_DIR, name)
    next if File.exist?(dest) && !force
    if chain.include?("[") || chain.include?(";")
      sh! "ffmpeg", "-y", *inputs, "-filter_complex", chain, "-ar", SAMPLE_RATE.to_s, dest
    else
      sh! "ffmpeg", "-y", *inputs, "-af", chain, "-ar", SAMPLE_RATE.to_s, dest
    end
    puts "fm kit: #{name}"
  end
end

def fm_drums_enabled?
  ENV.fetch("FM_DRUMS", "1") != "0"
end

def ensure_fm_drum_kit!
  needed = %w[kick.wav snare.wav hat.wav ghost.wav open_hat.wav ind_kick.wav]
  generate_fm_drum_kit! unless needed.all? { |n| File.exist?(File.join(FM_DRUM_DIR, n)) }
end

def ensure_drum_kit!
  generate_drum_kit! unless drum_kit_ready?
  ensure_fm_drum_kit! if fm_drums_enabled?
end

# Optional one-shots sliced from demucs drums (path under samples/) for DRUM_CHOPS=1.
DRUM_CHOP_SOURCE = "samples/demux/htdemucs_6s/flylo_camel_source/drums.wav"
DRUM_CHOP_DIR = "samples/drums/custom/grid_chops"
DRUM_CHOP_BPM = 86.0

def ensure_drum_chops!
  dest = File.join(ROOT, DRUM_CHOP_DIR)
  return dest if %w[kick.wav snare.wav hat.wav].all? { |n| File.file?(File.join(dest, n)) }
  src = File.join(ROOT, DRUM_CHOP_SOURCE)
  return unless File.file?(src)
  FileUtils.mkdir_p(dest)
  step = 60.0 / DRUM_CHOP_BPM / 4.0
  bar8 = 8 * 4 * step
  { "kick.wav" => 0, "snare.wav" => 4, "hat.wav" => 2 }.each do |name, step_i|
    # A real chop rarely lands exactly on the transient -- a few ms of
    # deterministic slop (seeded by name, not random-per-run, so the same
    # source always chops the same way) instead of an always-exact cut
    # point is closer to how sample-chopping actually sounds.
    slop = (Random.new(stable_hash(name)).rand(-0.012..0.012)).round(4)
    t0 = (bar8 + step_i * step + 0.5 + slop).clamp(0.0, Float::INFINITY).round(3)
    dur = if name.start_with?("kick")
0.28
else
(name.start_with?("snare") ? 0.22 : 0.12)
end
    out = File.join(dest, name)
    ok = system("ffmpeg", "-y", "-ss", t0.to_s, "-t", dur.to_s, "-i", src,
                "-af", "aformat=sample_rates=44100:channel_layouts=mono,highpass=f=30,alimiter=limit=0.95",
                "-c:a", "pcm_s16le", out, out: File::NULL, err: File::NULL)
    FileUtils.rm_f(out) unless ok
  end
  File.file?(File.join(dest, "kick.wav")) ? dest : nil
end

def wav_sample_rate(path)
  out, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "stream=sample_rate",
                        "-of", "default=noprint_wrappers=1:nokey=1", path)
  out.to_s.strip.to_i
rescue StandardError
  0
end

def load_kit_wav(path)
  return unless path && File.file?(path)
  # DillaMusicGems.read_mono_wav (wavefile gem) decodes raw samples with NO
  # resample — fine for our own kit (already SAMPLE_RATE-native), wrong for
  # external samples at a different native rate (free-drum-samples ships
  # 22050Hz). Loaded at the wrong rate, a hit plays back half-speed and an
  # octave low — this was making the whole external-kit drum sound "horrible".
  # ffprobe first; only take the no-resample fast path when the rate already
  # matches, otherwise force the ffmpeg fallback below which does resample.
  if defined?(DillaMusicGems) && DillaMusicGems.respond_to?(:read_mono_wav) && wav_sample_rate(path) == SAMPLE_RATE
    samples = DillaMusicGems.read_mono_wav(path)
    return samples if samples && !samples.empty?
  end
  # ffmpeg fallback — resamples to SAMPLE_RATE, no wavefile gem required
  raw, = Open3.capture2("ffmpeg", "-v", "error", "-i", path,
                        "-f", "f32le", "-ac", "1", "-ar", SAMPLE_RATE.to_s, "pipe:1")
  return if raw.nil? || raw.empty?
  raw.unpack("e*")
rescue StandardError
  nil
end

# True if drum_sample_path(name) resolved to a real sample (custom dir,
# the external free-drum-samples kit, or the FM kit) rather than the plain
# synthesized fallback directly in DRUM_DIR -- used to stop the camel/grid
# one-shot chops below from silently clobbering a better sample that
# already won. FM_DRUM_DIR is a DRUM_DIR subdirectory, so it needs its own
# check -- a plain start_with?(DRUM_DIR) would treat it as unresolved and
# let the chops overwrite it, the same bug fixed earlier for external kits.
def external_sample_used?(name)
  path = drum_sample_path(name)
  return true if path.start_with?(FM_DRUM_DIR)

  !path.start_with?(DRUM_DIR)
end

def apply_drum_chops_to_kit!(kit)
  # Prefer pre-cut Camel oneshots, then grid_chops from demucs stem — but
  # only for roles that didn't already resolve to a real external-kit
  # sample. These one-shots are all sliced from a single FlyLo Camel
  # render (camel_chops and grid_chops are literally byte-identical files),
  # so they were unconditionally overwriting the hat/snare fix above with
  # the same narrow, zero-variety source every render.
  dirs = [
    File.join(CUSTOM_DRUM_DIR, "camel_chops"),
    File.join(ROOT, DRUM_CHOP_DIR),
    ensure_drum_chops!,
  ].compact.uniq
  roles = { kick: "kick.wav", snare: "snare.wav", hat: "hat.wav" }
           .reject { |_, file| external_sample_used?(file) }
  return kit if roles.empty?
  dirs.each do |dest|
    next unless dest && Dir.exist?(dest)
    roles.each do |role, file|
      path = File.join(dest, file)
      samples = load_kit_wav(path)
      kit[role] = samples if samples && !samples.empty?
    end
    # Keep a second kick body for alternation (MPC two-kick habit).
    if roles.key?(:kick)
      alt = load_kit_wav(File.join(dest, "kick.wav"))
      kit[:ind_kick] = alt if alt && !alt.empty? && kit[:ind_kick].nil?
    end
    break if (!roles.key?(:kick) || kit[:kick]) && (!roles.key?(:snare) || kit[:snare])
  end
  kit
end
