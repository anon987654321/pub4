# frozen_string_literal: true
#
# Patch lookup, arp modes, and the morph voice/patch choices per chord.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


def synth_patch_by_id(id)
  SYNTH_PATCH_BY_ID[id]
end

def galaxy_ep_available?
  File.exist?(patch_sf2_path(:galaxy))
end

GALAXY_EP_SUBSTITUTES = %i[
  rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_cafe_warm
  rhodes_vintage_tape rhodes_bleeding_edge rhodes_dx_blend
].freeze

# Presets that name a specific instrument on purpose — the substitution below
# would defeat the reason they exist.
GALAXY_EP_EXEMPT_VOICES = %i[rhodes_solo pad_madlib].freeze

def prefer_galaxy_ep(patch)
  return patch unless patch && galaxy_ep_available?
  # Patches already bound to :galaxy keep their bank/program; only GM-default
  # Rhodes ids get promoted to galaxy_ep1 when the bank is present.
  return patch if patch[:sf2] == :galaxy
  return patch unless GALAXY_EP_SUBSTITUTES.include?(patch[:id])
  # An explicitly chosen pad voice keeps the EP it names.
  #
  # This swap fires whenever the Galaxy soundfont is installed, so
  # PAD_VOICE=prophet (rhodes_mark1) and PAD_VOICE=rhodes silently rendered
  # galaxy_ep1 instead. Fine as a default upgrade; not fine as an override of
  # what was asked for — and fatal for pad_madlib, whose entire content is
  # "a Fender Rhodes Stage 73 and nothing else".
  return patch if GALAXY_EP_EXEMPT_VOICES.include?(ENV["PAD_VOICE"]&.downcase&.to_sym)
  return patch if USER_PINNED_ENV.key?("PAD_VOICE") && ENV["PAD_VOICE"] == USER_PINNED_ENV["PAD_VOICE"]

  synth_patch_by_id(:galaxy_ep1)
end

def pad_texture_enabled?
  # Style DNA defaults PAD_TEXTURE on; fetch default matches BEST/STYLE tables.
  ENV.fetch("PAD_TEXTURE", "1") == "1"
end

def experimental_leads_enabled?
  ENV.fetch("EXPERIMENTAL_LEADS", "1") != "0"
end

# Arp figure presets — PAD_ARP_MODE selects the lead-arp character; chord pads
# (EP/warm) always render held. Former per-layer routing (arp on Rhodes/Moog
# pads) moved to lead_arp.wav so pads stay lush and the figure sits up top.
PAD_ARP_LAYER_MODES = {
  held:   { ep: :held,    warm: :held },
  shimmer: { ep: :shimmer, warm: :held },
  pulse:  { ep: :held,    warm: :arp },
  blend:  { ep: :shimmer, warm: :arp },
  duo:    { ep: :arp,     warm: :arp },
  wash:   { ep: :held,    warm: :arp },
  figure: { ep: :arp,     warm: :held },
}.freeze

PAD_ARP_PRESETS = {
  ep_shimmer: { style: :skip_up, subdiv: 8, gate: 0.78, vel: 0.16,
                arp_styles: %i[skip_up euclidean quint_spread] },
  ep_figure:  { style: :fibonacci, subdiv: 6, gate: 0.74, vel: 0.22,
                arp_styles: %i[fibonacci spiral major_third_cycle_full] },
  warm_pulse: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24,
                arp_styles: %i[updown pingpong] },
  warm_wash:  { style: :pingpong, subdiv: 3, gate: 0.9, vel: 0.28,
                arp_styles: %i[pingpong major_third_cycle_full quint_spread] },
  warm_moog:  { style: :up, subdiv: 4, gate: 0.88, vel: 0.26,
                arp_styles: %i[up downup quint_spread] },
}.freeze

# NO_ARP=1 wins over everything, including a preset.
#
# PAD_ARP was only ever a fallback: this reads ENV["PAD_ARP_MODE"] first, which
# is what the style presets write, so setting PAD_ARP=held did nothing on the 48
# of 53 presets that name a mode — wash on 25, shimmer on 9, pulse on 6, figure
# and duo on 3 each. Only 5 are held. An operator asking for no arpeggiators was
# being overruled by the table, silently, on almost every track.
#
# Forcing :held here also stops the lead arp: lead_arp_mode is
# PAD_TO_LEAD_ARP[pad_arp_mode], and lead_arp_preset_key only reaches the legacy
# path when pad_arp_mode != :held. One switch, both layers, which is what "stop
# using arpeggiators" has to mean.
# Default ON. This was added when arpeggiators were asked to stop and then
# left opt-in, which meant the 48 presets that write PAD_ARP_MODE went
# straight back to arpeggiating. NO_ARP=0 restores them.
def no_arp? = ENV.fetch("NO_ARP", "1") != "0"

def pad_arp_mode
  return :held if no_arp?

  raw = ENV["PAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && PAD_ARP_LAYER_MODES.key?(sym)
  return :blend if ENV.fetch("PAD_CHORD_ARP", "0") != "0"
  fallback = (ENV["PAD_ARP"] || "held").to_s.downcase.to_sym
  PAD_ARP_LAYER_MODES.key?(fallback) ? fallback : :held
end

def lead_arp_mode
  raw = ENV["LEAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && LEAD_ARP_PRESETS.key?(sym)
  PAD_TO_LEAD_ARP[pad_arp_mode]
end

def lead_arp_preset_key
  lead_arp_mode ||
    (lead_arp_preset_for_pad_mode_legacy if pad_arp_mode != :held)
end

# Legacy PAD_ARP_MODE → PAD_ARP_PRESETS key (fallback when LEAD_ARP_MODE unset).
def lead_arp_preset_for_pad_mode_legacy(mode = nil)
  mode ||= pad_arp_mode
  case mode
  when :held then nil
  when :shimmer then :ep_shimmer
  when :pulse then :warm_pulse
  when :blend then :warm_pulse
  when :duo then :ep_figure
  when :wash then :warm_wash
  when :figure then :ep_figure
  else :warm_pulse
  end
end

def synth_cycle_enabled?
  ENV.fetch("SYNTH_CYCLE", "1") != "0"
end

def synth_morph_enabled?
  return false if ENV["SYNTH_MORPH"] == "0"
  return true if ENV["SYNTH_MORPH"] == "1"
  ENV["STREAM_SOUL"] == "1" || stream_iterate_enabled?
end

def pad_synth_cycle_enabled?
  synth_cycle_enabled? || synth_morph_enabled?
end

def morph_voice_at(event_idx)
  voices = PAD_VOICE_MORPH_VOICES
  base = ENV["PAD_VOICE"]&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_patch_pool(role:, voice:)
  pool = role == :ep ? ep_patch_pool(voice) : warm_patch_pool(voice)
  return pool unless role == :ep && synth_morph_enabled?
  Array(pool).reject { |id| id.to_s.start_with?("galaxy_") }
end

def morph_patch_for_chord(event_idx, role:)
  voice = morph_voice_at(event_idx)
  pool = morph_patch_pool(role:, voice:)
  preset = PAD_VOICE_PRESETS[voice] || PAD_VOICE_PRESETS[:moog]
  fallback_id = role == :ep ? preset[:ep] : preset[:warm]
  pick_patch_from_pool(pool, seed: event_idx * 311 + (role == :ep ? 0 : 17)) ||
    (fallback_id && synth_patch_by_id(fallback_id))
end

def lead_morph_enabled?
  return false if ENV["LEAD_MORPH"] == "0"
  return true if ENV["LEAD_MORPH"] == "1"
  synth_morph_enabled?
end

def morph_lead_voice_at(event_idx)
  voices = LEAD_MORPH_VOICES
  base = (ENV["LEAD_MORPH_VOICE"] || ENV["LEAD_VOICE"])&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_lead_patch_for_chord(event_idx)
  voice = morph_lead_voice_at(event_idx)
  pool = Array(MORPH_LEAD_PATCH_POOL[voice] || MORPH_LEAD_PATCH_POOL[:hard])
              .reject { |id| (p = synth_patch_by_id(id)) && p[:sf2] != :default }
  pick_patch_from_pool(pool, seed: event_idx * 503 + 91) || synth_patch_by_id(:saw_lead)
end

def morph_lead_arp_cfg_for_chord(event_idx, patch)
  preset_key = MORPH_LEAD_ARP_CYCLE[event_idx % MORPH_LEAD_ARP_CYCLE.length]
  base = EXPERIMENTAL_LEAD_ARP_PRESETS[preset_key]&.dup ||
         LEAD_ARP_PRESETS[:flylo_spiral]&.dup ||
         { style: :spiral, subdiv: 8, gate: 0.52, vel: 0.56, arp_styles: %i[spiral flylo_wobble] }
  styles = (base[:arp_styles] || []) + arp_styles_for_patch(patch, base[:style])
  base.merge(arp_styles: styles.uniq)
end

# Process.pid in the seed makes every render pick different patches, which is
# good for a stream that should not repeat itself and fatal for measurement:
# two renders differing only in one switch also differ in their entire synth
# voicing, so any A/B between them compares two variables and attributes the
# result to one. Large effects survive that noise; small ones do not, and
# several comparisons in this engine's history were probably reading patch
# variance rather than the change under test.
#
# RENDER_SEED pins it. Set it and renders are reproducible and comparable;
# leave it unset and the old per-process variation is unchanged.
def patch_cycle_seed(base = 0)
  pinned = ENV["RENDER_SEED"]
  entropy = pinned && !pinned.empty? ? pinned.to_i : Process.pid
  base + (@render_seed || 0) + (@stream_iterate_count || 0) * 7919 + entropy
end
