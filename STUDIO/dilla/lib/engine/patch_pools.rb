# frozen_string_literal: true
#
# Patch pools and the timbre filters that keep flutes, choirs and metal out.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# GM chromatic percussion is struck metal — celesta, glockenspiel, music box,
# vibraphone, marimba, xylophone, tubular bells — and 94 is literally "metallic
# pad", 98 "crystal", 103 "FX 8 (sci-fi)". None of them belong in a Rhodes /
# Moog / Prophet record.
#
# 16 is deliberately absent: that is the drawbar organ, and a Hammond is not
# what anyone means by metallic. Excluding it would have cost stevie_organ_lead
# for no reason.
METALLIC_PROGRAMS = [9, 10, 11, 12, 13, 14, 15, 94, 98, 99, 103].freeze

def smooth_analog? = ENV.fetch("SMOOTH_ANALOG", "1") != "0"

def metallic_patch?(patch) = patch && METALLIC_PROGRAMS.include?(patch[:program])

# The GM pipe family: flute, recorder, pan flute, blown bottle, shakuhachi,
# whistle, ocarina. Operator, 2026-08-11: no flutes, skip those parts of the
# song -- so this rejects the whole family rather than the two patches whose
# names happen to say flute. ethnic_flute is a pan flute at 75 and would have
# survived an id-based list, and so would anything added later that is a flute
# without being called one.
PIPE_GM_PROGRAMS = (72..79).freeze

def flutes_allowed? = ENV["FLUTES"] == "1"

def flute_patch?(patch) = patch && PIPE_GM_PROGRAMS.include?(patch[:program])

# Same rule as reject_choral above: filter, but never down to an empty pool.
def reject_flutes(pool)
  return pool if flutes_allowed? || pool.empty?

  grounded = pool.reject { |p| flute_patch?(p) }
  grounded.empty? ? pool : grounded
end

# The backstop, at the only point that cannot be routed around: the byte that
# becomes a MIDI program change. Every FluidSynth voice in this engine passes
# through one of the three 0xC0 sites, so a flute that survives every pool
# filter still cannot reach the soundfont.
#
# This exists because filtering the pools was not enough twice. There are nine
# pipe-family patches and only three say flute in their name -- jazz_ballad_lead
# is program 73, and so are whistle_hook, piccolo_spark, shakuhachi_breath and
# ocarina_folk in their own registers. mellotron_flute_pad is also referenced
# directly as a texture rather than drawn from a pool, so no pool filter would
# ever have seen it.
#
# 89 is Pad 2 (warm), already in WARM_PAD_GM_PROGRAMS. A pipe patch is usually
# doing something soft and high, and a warm pad is the substitution least likely
# to turn into a harsh stab where a breathy line used to be.
NONFLUTE_SUBSTITUTE_PROGRAM = 89

def nonflute_program(program)
  prog = program.to_i
  return prog if flutes_allowed? || !PIPE_GM_PROGRAMS.include?(prog)

  @flute_substitutions = (@flute_substitutions || 0) + 1
  NONFLUTE_SUBSTITUTE_PROGRAM
end

def pick_patch_from_pool(pool, seed: 0)
  ids = Array(pool).compact.uniq
  return if ids.empty?

  # Filtered, but never to nothing. A pool that is entirely metallic still has
  # to return a patch — dropping to nil here would silence the voice rather than
  # change its colour, which is a worse outcome than one bright preset.
  if smooth_analog?
    warm = ids.reject { |i| metallic_patch?(synth_patch_by_id(i)) }
    ids = warm unless warm.empty?
  end
  unless choral_pads_allowed?
    grounded = ids.reject { |i| choral_patch?(synth_patch_by_id(i) || {}) }
    ids = grounded unless grounded.empty?
  end
  unless flutes_allowed?
    unpiped = ids.reject { |i| flute_patch?(synth_patch_by_id(i) || {}) }
    ids = unpiped unless unpiped.empty?
  end

  rng = Random.new(patch_cycle_seed(seed))
  synth_patch_by_id(ids[rng.rand(ids.length)])
end

def lush_synth_pools?
  ENV.fetch("LUSH_SYNTH", "1") != "0"
end

def ep_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_EP[voice] || PATCH_CYCLE_EP[voice]) : PATCH_CYCLE_EP[voice]
end

def warm_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_WARM[voice] || PATCH_CYCLE_WARM[voice]) : PATCH_CYCLE_WARM[voice]
end

def lead_patch_pool(voice)
  lush_synth_pools? ? (LUSH_LEAD_VOICE_POOLS[voice] || LEAD_VOICE_POOLS[voice]) : LEAD_VOICE_POOLS[voice]
end

def apply_lead_voice_preset!(seed: 0)
  voice = ENV["LEAD_VOICE"]&.downcase&.to_sym
  return unless voice
  if synth_cycle_enabled? && lead_patch_pool(voice)
    @render_lead_patch = pick_patch_from_pool(lead_patch_pool(voice), seed: seed + 41) ||
                        synth_patch_by_id(LEAD_VOICE_PRESETS[voice])
  else
    id = LEAD_VOICE_PRESETS[voice]
    @render_lead_patch = synth_patch_by_id(id) if id
  end
end

def apply_pad_voice_preset!(seed: 0)
  voice = ENV["PAD_VOICE"]&.downcase&.to_sym
  # Multi-layer stacks pin patches from PAD_LAYER_STACKS (rendered together).
  if voice && PAD_LAYER_STACKS[voice] && ENV.fetch("PAD_LAYERS", "1") != "0"
    stack = PAD_LAYER_STACKS[voice]
    @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(stack[0][:id])) if stack[0]
    @render_warm_patch = synth_patch_by_id(stack[1][:id]) if stack[1]
    @render_warm2_patch = synth_patch_by_id(stack[2][:id]) if stack[2]
    @render_texture_patch = synth_patch_by_id(stack[3][:id]) if stack[3]
    @render_skip_warm_pad = false
    return
  end
  if voice && PAD_VOICE_PRESETS[voice]
    preset = PAD_VOICE_PRESETS[voice]
    if pad_synth_cycle_enabled? && !PAD_LAYER_STACKS.key?(voice)
      ep_pool = ep_patch_pool(voice)
      warm_pool = warm_patch_pool(voice)
      if ep_pool&.any?
        @render_ep_patch = prefer_galaxy_ep(pick_patch_from_pool(ep_pool, seed:) ||
                                            synth_patch_by_id(preset[:ep]))
      elsif preset[:ep]
        @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep]))
      end
      if warm_pool&.any?
        @render_warm_patch = pick_patch_from_pool(warm_pool, seed: seed + 17)
        @render_skip_warm_pad = @render_warm_patch.nil?
      elsif preset[:warm]
        @render_warm_patch = synth_patch_by_id(preset[:warm])
        @render_skip_warm_pad = false
      else
        @render_skip_warm_pad = true
      end
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
    else
      @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep])) if preset[:ep]
      @render_warm_patch = synth_patch_by_id(preset[:warm]) if preset[:warm]
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
      @render_skip_warm_pad = preset[:warm].nil?
    end
    return
  end
  # Soul defaults: Rhodes + Moog + Prophet stack
  return if ENV["CREEPY_PATCHES"] == "1"
  @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(:rhodes_cafe_warm))
  @render_warm_patch = synth_patch_by_id(:moog_model_d)
  @render_warm2_patch = synth_patch_by_id(:prophet_5_pad)
  @render_skip_warm_pad = false
end

# Soulful EP/pad palette — no voices, supersaws, music boxes, or horror textures.
BEAUTIFUL_PATCH_IDS = {
  ep: PATCH_CYCLE_EP.values.flatten.uniq,
  warm: PATCH_CYCLE_WARM.values.flatten.uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD,
  lead: LEAD_VOICE_POOLS.values.flatten.uniq,
  texture: PATCH_CYCLE_TEXTURE,
  native: %i[
    native_rhodes native_rhodes_bleeding native_juno native_prophet native_moog
    native_fm_glass native_organ native_warm_pad native_string native_pwm
  ],
}.freeze

# Experimental but musical leads — Flylo/Prophet/Moog/FM; not horror/novelty.
EXPERIMENTAL_LEAD_IDS = {
  lead: (LEAD_VOICE_POOLS.values.flatten + %i[
    jupiter_superlead obxr_sync_lead cs80_brass_lead mono_poly_lead dx7_glass_arp
    fifths_lead saw_lead supersaw_1 supersaw_2 prophet_bleeding_lead tame_wobble_lead
  ]).uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD,
}.freeze

CREEPY_PATCH_IDS = %i[
  space_voice reverse_pad_ghost voice_lead whistle_hook charang_bite supersaw_1 supersaw_2
  supersaw_3 scale_arp_supersaw scale_arp_prophet prophet_bleeding_lead music_box fm_lead_bell
  dist_guitar banjo_pluck koto_pluck brass_synth square_lead ethnic_flute kalimba_dust
  choir_aahs voice_oohs bowed_glass harpsi_pluck
].freeze

def lead_patch_allowlist(role)
  return if ENV["CREEPY_PATCHES"] == "1"
  base = BEAUTIFUL_PATCH_IDS[role] || []
  if experimental_leads_enabled? && EXPERIMENTAL_LEAD_IDS[role]
    (base + EXPERIMENTAL_LEAD_IDS[role]).uniq
  else
    base
  end
end

# The General MIDI programs that are a CHOIR. Not strings, not horns.
#
# The first version of this list ran from 44 to 62 and took the string
# ensembles, the harp and the french horn out with the choirs. That was an
# overcorrection and it cost the thing it was protecting: strings are how a
# chord becomes beautiful, and removing them left the pads with nothing to be
# lush with. The complaint that followed -- no more beautiful chords -- was
# caused by this line.
#
# What actually made the tracks sound like a church was two things together: a
# literal Choir Aahs patch, and a nine-hundred-millisecond attack swelling under
# it. The envelope was the larger half. With that fixed, strings are welcome.
#
# So the list is now only the voices: Choir Aahs, Voice Oohs, Synth Voice, and
# the named choir patches caught by the same programs. Set CHORAL_PADS=1 to
# allow even those.
CHORAL_GM_PROGRAMS = [52, 53, 54].freeze

def choral_patch?(patch)
  CHORAL_GM_PROGRAMS.include?(patch[:program])
end

def choral_pads_allowed?
  ENV["CHORAL_PADS"] == "1"
end

# Filters a pool of patches, never down to nothing -- the same rule the other
# filters here follow, because an empty pool is a crash and a slightly wrong
# patch is a Tuesday.
def reject_choral(pool)
  return pool if choral_pads_allowed? || pool.empty?

  grounded = pool.reject { |p| choral_patch?(p) }
  grounded.empty? ? pool : grounded
end

def weighted_patch_pick(role, seed: nil, soulful: true)
  pool = SYNTH_PATCH_BY_ROLE.fetch(role, [])
  return if pool.empty?
  if soulful && ENV["CREEPY_PATCHES"] != "1"
    allowed = %i[lead scale_lead].include?(role) ? lead_patch_allowlist(role) : BEAUTIFUL_PATCH_IDS[role]
    if allowed&.any?
      pool = pool.select { |p| allowed.include?(p[:id]) }
      pool = SYNTH_PATCH_BY_ROLE.fetch(role, []).select { |p| allowed.include?(p[:id]) } if pool.empty?
    end
    pool = pool.reject { |p| CREEPY_PATCH_IDS.include?(p[:id]) }
  end
  # The metallic filter has to be here too, not only in pick_patch_from_pool.
  # This is a second, independent selection path — it is how crystal_scale_lead
  # kept being chosen after the pool filter went in. Same fallback rule: filter,
  # but never down to an empty pool.
  if smooth_analog?
    warm = pool.reject { |p| metallic_patch?(p) }
    pool = warm unless warm.empty?
  end
  # Both selection paths, for the reason the comment above gives: a filter
  # applied to only one of them is a filter that does not work.
  pool = reject_choral(pool)
  pool = reject_flutes(pool)
  return if pool.empty?
  rng = Random.new(seed || @render_seed || rand(1_000_000))
  total = pool.sum { |p| p[:weight] || 1.0 }
  roll = rng.rand * total
  pool.each do |patch|
    roll -= (patch[:weight] || 1.0)
    return patch if roll <= 0
  end
  pool.last
end

def pick_synth_patches!(cfg, bar: 0, n_bars: nil)
  seed = (stable_hash(cfg[:track].to_s) % 100_000) + (@render_seed || 0) +
         (pad_synth_cycle_enabled? ? (@stream_iterate_count || 0) * 997 + bar * 13 : 0)
  @render_skip_warm_pad = false
  roles = nil
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    section = @composition_session.section_at(bar)
    roles = @composition_session.ensemble_roles(section)
  end
  pick_role = ->(role) { roles.nil? || roles.include?(role) }
  if pick_role.call(:ep) || pick_role.call(:warm)
    apply_pad_voice_preset!(seed:)
  end
  unless ENV["PAD_VOICE"] || ENV["CREEPY_PATCHES"] == "1"
    @render_ep_patch = weighted_patch_pick(:ep, seed:) if pick_role.call(:ep) && !@render_ep_patch
    @render_warm_patch = weighted_patch_pick(:warm, seed: seed + 17) if pick_role.call(:warm) && !@render_warm_patch
  end
  @render_texture_patch = nil
  if pad_texture_enabled? && pick_role.call(:texture)
    @render_texture_patch = weighted_patch_pick(:texture, seed: seed + 29)
  end
  apply_lead_voice_preset!(seed:) if ENV["LEAD_VOICE"] && !ENV["LEAD_VOICE"].empty?
  @render_lead_patch = weighted_patch_pick(:lead, seed: seed + 41) if pick_role.call(:lead) && !@render_lead_patch
  if pick_role.call(:scale_lead)
    @render_scale_lead_patch = weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  end
  voice = ENV["PAD_VOICE"]&.downcase
  native_id = case voice
              when "moog" then :native_moog
              when "prophet" then :native_prophet
              when "rhodes", "blend", nil then :native_rhodes
              else nil
              end
  @render_native_patch = (native_id && synth_patch_by_id(native_id)) ||
                         weighted_patch_pick(:native, seed: seed + 53)
  @render_ep_patch ||= weighted_patch_pick(:ep, seed:)
  @render_warm_patch ||= weighted_patch_pick(:warm, seed: seed + 17)
  @render_lead_patch ||= weighted_patch_pick(:lead, seed: seed + 41)
  @render_scale_lead_patch ||= weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  @render_arp_style = (@render_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 67))
  @render_scale_arp_style = (@render_scale_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 83))
end

def patch_sf2_path(sf2_key)
  cache = File.expand_path("~/.cache/dilla-soundfonts")
  case sf2_key
  when :galaxy
    File.join(cache, "galaxy-electric-pianos.sf2")
  when :supersaw
    File.join(cache, "supersaw-collection.sf2")
  when :giga_fm
    File.join(cache, "giga-hq-fm-gm.sf2")
  when :yamaha
    File.join(cache, "yamaha-grand-lite.sf2")
  when :vintage_dreams
    # Prefer a copy under the dilla cache (symlinked by fetch_assets!); else
    # fluid-synth's Homebrew-bundled test bank (public domain-ish demo SF2).
    cached = File.join(cache, "VintageDreamsWaves-v2.sf2")
    return cached if File.exist?(cached)

    Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first ||
      Dir.glob("/usr/local/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first ||
      cached
  else
    pad_soundfont_path
  end
end

EXTERNAL_SF2_KEYS = %i[galaxy supersaw giga_fm yamaha vintage_dreams].freeze

def patch_voice_for(patch)
  return unless patch
  sf2 = patch[:sf2]
  path = if EXTERNAL_SF2_KEYS.include?(sf2)
           p = patch_sf2_path(sf2)
           File.exist?(p) ? p : pad_soundfont_path
         else
           pad_soundfont_path
         end
  { sf2: path, bank: patch[:bank], program: patch[:program], patch: }
end
