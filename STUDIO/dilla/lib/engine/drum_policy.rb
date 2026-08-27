# frozen_string_literal: true
#
# Which drums play at all: kick gates, halftime, Wonky overlays and grids.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def extended_drum_kit(base_kit)
  base_kit.merge(
    rim: synth_rim_sample,
    clap: synth_clap_sample,
    tabla: synth_tabla_sample,
    tambourine: synth_tambourine_sample,
    woodblock: synth_woodblock_sample,
    agogo: synth_agogo_sample,
    ind_kick: load_mono_sample(drum_sample_path("ind_kick.wav")),
    ind_clap: load_mono_sample(drum_sample_path("ind_clap.wav")),
    ind_hat: load_mono_sample(drum_sample_path("ind_hat.wav")),
    ind_stab: load_mono_sample(drum_sample_path("ind_stab.wav")),
  )
rescue StandardError
  base_kit
end

def wonky_primary_drums?
  camel_mode? && wonky_drum_overlay_enabled?
end

# Under Camel/Wonky primary, default to Wonky grid ONLY.
# Hybrid pocket+overlay doubled kicks/snares (~10 kicks + ~9 snares/bar) and
# sounded like broken machine-gun drums — set WONKY_DRUMS_ONLY=0 to re-enable pocket.
def wonky_drums_only?
  # Default OFF — hybrid double-kit was the #1 "drums suck" failure mode.
  wonky_primary_drums? && ENV.fetch("WONKY_DRUMS_ONLY", "0") == "1"
end

def dilla_pocket_drums_enabled?
  !wonky_drums_only?
end

def kicks_enabled?
  # Pocket kit kicks when overlay-only is off. Prefer POCKET_KICKS;
  # KICKS=1 alone does not force pocket when WONKY_DRUMS_ONLY=1.
  return false if wonky_drums_only?
  return ENV.fetch("POCKET_KICKS", "1") != "0" if ENV.key?("POCKET_KICKS")
  ENV.fetch("KICKS", "1") != "0"
end

def kick_velocity_scale
  # Non-wonky default was cut from ~0.9 to 0.68 chasing a Wonky-only
  # "drums too hard" complaint, but this default is shared by every
  # non-wonky track (pedal_e_descent included) and compounds with
  # dilla_role_velocity's already-lower kick_anchor/kick_sync bases --
  # real listening feedback was "absent proper kick drums." Restored
  # toward the pre-cut value; wonky's own 0.78 is untouched.
  default = wonky_primary_drums? ? "0.78" : "0.88"
  ENV.fetch("KICK_GAIN", default).to_f.clamp(0.08, 1.35)
end

def wonky_kick_velocity_scale
  ENV.fetch("WONKY_KICK_GAIN", wonky_primary_drums? ? "1.15" : "0.85").to_f.clamp(0.2, 2.0)
end

def halftime?
  ENV.fetch("HALFTIME", "0") == "1"
end

# A semitone either side, as ratios. Approaching from below is the default
# because a leading tone rising into the root is the stronger pull; from above
# when the next chord is lower, so the line keeps descending rather than
# doubling back to climb into it.
APPROACH_BELOW = 0.9438743126816935   # 2 ** (-1/12.0)
APPROACH_ABOVE = 1.0594630943592953   # 2 ** ( 1/12.0)

# The bass stays low. A fifth above a root already near the top of the register
# lands in the pads' territory and stops reading as bass at all.
BASS_REGISTER_TOP = 130.0

def bass_line_enabled? = ENV.fetch("BASS_LINE", "1") != "0"

def bass_slide_enabled?
  ENV.fetch("BASS_SLIDE", "1") != "0"
end

def backbeat_clap_enabled?
  ENV.fetch("BACKBEAT_CLAP", "1") != "0"
end

def wonky_drum_overlay_enabled?
  ENV.fetch("WONKY_DRUM_OVERLAY", ENV["STREAM_SOUL"] == "1" ? "1" : "0") != "0"
end

def wonky_overlay_rotate_steps(steps, rot)
  Array(steps).map { |s| (s + rot) % 16 }.uniq.sort
end

def wonky_overlay_grids_for(section)
  @wonky_overlay_grid_cache ||= {}
  bias = ENV.fetch("WONKY_GRID_BIAS", section.to_s).to_sym
  cache_key = [section, bias, @render_seed || 0]
  return @wonky_overlay_grid_cache[cache_key] if @wonky_overlay_grid_cache.key?(cache_key)
  base = DillaLofiMachine::DRUM_PRESETS[:wonky_abstract]
  shift = WONKY_OVERLAY_SECTION_SHIFT.fetch(section, 2)
  grids = WONKY_OVERLAY_GRID_COUNT.times.map do |variant|
    rot = shift + variant
    {
      kicks: wonky_overlay_rotate_steps(base[:kicks], rot),
      snares: wonky_overlay_rotate_steps(base[:snares], rot * 2),
      hats: wonky_overlay_rotate_steps(base[:hats], rot + variant),
      perc: wonky_overlay_rotate_steps(base[:perc], rot + 1),
    }
  end
  @wonky_overlay_grid_cache[cache_key] = grids
end

def wonky_overlay_grid_pick(bar, section, role)
  grids = wonky_overlay_grids_for(section)
  seed = (@render_seed || 0) + stable_hash(section)
  idx = (bar + seed + (bar / 4)) % grids.length
  Array(grids[idx].fetch(role, [])).dup
end

def wonky_drum_grid_for(track)
  t = track.to_s
  return if t.empty?
  eng = load_learned_engine
  alias_key = eng.dig("track_aliases", t)
  eng.dig("drum_grids", t) ||
    (alias_key && eng.dig("drum_grids", alias_key)) ||
    BUILTIN_LEARNED_ENGINE.dig("drum_grids", t) ||
    (alias_key && BUILTIN_LEARNED_ENGINE.dig("drum_grids", alias_key))
end

def wonky_overlay_grid_hash
  # Camel/dilla style always uses the hip-hop pocket reduction of the Camel stem.
  # Project JSON may supply per-track grids when not in camel/dilla mode.
  grid = if camel_mode?
           POLY_TEMPORAL_DRUM_GRID
         else
           wonky_drum_grid_for(ENV["TRACK"] || "")
         end
  grid = POLY_TEMPORAL_DRUM_GRID if (grid.nil? || !grid.is_a?(Hash)) && wonky_drum_overlay_enabled?
  grid.is_a?(Hash) ? grid : nil
end

# Learned grids on disk predate the rename and still key their steps flylo_*.
# Renaming the reader without accepting the old spelling does not fail -- it
# falls through to the bare key, finds nothing, and plays an empty grid, so a
# learned pattern silently becomes silence. Read both, write only the new one.
WONKY_GRID_LEGACY_PREFIX = "flylo_"
def wonky_grid_steps(grid, name)
  Array(grid["wonky_#{name}"] ||
        grid["#{WONKY_GRID_LEGACY_PREFIX}#{name}"] ||
        grid[name] || grid[name.to_sym] || [])
end

def learned_wonky_overlay_steps(role)
  grid = wonky_overlay_grid_hash
  return unless grid
  case role
  when :kicks then wonky_grid_steps(grid, "kicks")
  when :snares then wonky_grid_steps(grid, "snares")
  when :ghost_snares then wonky_grid_steps(grid, "ghost_snares")
  when :hats then wonky_grid_steps(grid, "hats")
  when :hat_ghosts then wonky_grid_steps(grid, "hat_ghosts")
  when :perc then wonky_grid_steps(grid, "perc")
  when :claps then wonky_grid_steps(grid, "claps")
  end
end

def wonky_chord_change_duck(bar, chord_bars)
  return 1.0 unless bar.positive? && chord_bars.positive? && (bar % chord_bars).zero?
  ENV.fetch("WONKY_CHORD_DUCK", "0.72").to_f.clamp(0.45, 1.0)
end

def camel_drum_lock?
  camel_mode? && ENV.fetch("CAMEL_DRUM_LOCK", "1") != "0"
end

def wonky_overlay_density(bar, n_bars, chord_bars:, pad_chords: nil, chord_phases: nil, phrase_bars: nil)
  # Camel lock: always full kit — section density (intro 0.42 × form 0.55 ≈ 0.23)
  # was the main reason the grid felt "missing" / wrong vs Camel.
  return ENV.fetch("WONKY_OVERLAY_GAIN", "1.2").to_f.clamp(0.9, 1.45) if camel_drum_lock?

  section = dilla_section(bar, n_bars)
  form = form_section_at(bar, n_bars)
  base = WONKY_OVERLAY_SECTION_DENSITY.fetch(section, 0.85)
  form_mul = form ? WONKY_OVERLAY_FORM_MUL.fetch(form, 1.0) : 1.0
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars:)
  phase_mul = phase ? phase_gain_multiplier(phase) : 1.0
  duck = wonky_chord_change_duck(bar, chord_bars)
  gain = ENV.fetch("WONKY_OVERLAY_GAIN", wonky_primary_drums? ? "1.12" : "0.55").to_f
  (base * form_mul * phase_mul * duck * gain).clamp(0.12, 1.45)
end

# Split roles — snare was on BOTH buses and hit twice (muddy / flammed).
def wonky_sub_bus_mapping
  { wonky_kick: :kick, wonky_perc: :cowbell }
end

def wonky_top_bus_mapping
  { wonky_hat: :hat, wonky_quint: :hat, wonky_snare: :snare, wonky_rim: :rim, wonky_glitch: :ind_stab }
end
