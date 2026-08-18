# frozen_string_literal: true
#
# Pad, lead and morph voice presets, layer stacks and patch cycles.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Pad voice stacks — classic analog + curated experimental electronic.
# stack_soul = multi-preset layer (EP + Moog + Prophet + texture) for rich beds.
PAD_VOICE_PRESETS = {
  # True single-voice preset -- every other named preset here carries at
  # least an :ep + :warm layer, so PAD_LAYERS=0 alone never actually
  # produces one voice; this is the only entry that does.
  rhodes_solo: { ep: :rhodes_mark1 },
  # Rhodes front and center; Prophet under it, not Juno strings.
  rhodes:  { ep: :rhodes_mark1, warm: :prophet_5_pad },
  moog:    { ep: :rhodes_cafe_warm, warm: :moog_model_d },
  # Dilla's actual Voyager under his actual Rhodes.
  voyager: { ep: :rhodes_mark1, warm: :voyager_ladder_pad },
  # Flying Lotus: Rhodes and Wurlitzer in front, the Virus behind.
  virus:   { ep: :rhodes_stage73, warm: :access_virus_hyper },
  motif:   { ep: :motif_rack_ep, warm: :motif_rack_strings },
  # Double-Prophet bed under Stage 73 — the poly pad is the character.
  prophet: { ep: :rhodes_stage73, warm: :prophet_5_pad, warm2: :prophet_6_warm },
  fm:      { ep: :rhodes_cafe_warm, warm: :fm_bowed_pad },
  blend:   { ep: :rhodes_mark1, warm: :prophet_5_pad, warm2: :moog_model_d },
  glass:   { ep: :dx7_bell_ep, warm: :glass_fm_pad },
  vapor:   { ep: :rhodes_cafe_warm, warm: :vapor_supersaw },
  crystal: { ep: :galaxy_ep2, warm: :crystal_pwm },
  ice:     { ep: :rhodes_dx_blend, warm: :ice_string_pad },
  neon:    { ep: :rhodes_mark1, warm: :neon_ladder },
  pulse:   { ep: :clav_neo_funk, warm: :pwm_sweep_pad },
  # Producer-grounded presets, from what each actually played rather than from
  # what sounds lush. Researched 2026-07-30; sources in each entry.
  #
  # The point of these is subtraction. Every preset above this block layers an EP
  # under a warm pad, and stack_soul layers four voices — bigger than anything on
  # the records being imitated. Dilla's pads came out of a microKORG, Madlib's
  # chords out of one Rhodes into a Portastudio.
  #
  # Dilla: microKORG for "pads, leads and bass sounds" (Mixdown gear rundown);
  # the Minimoog Voyager Bob Moog sent him in 2002 was bass and melody, not
  # chords. His Rhodes character is sampled off vinyl, so the EP is the
  # tape-worn one and the synth layer is thin PWM, not an analog stack.
  pad_dilla: { ep: :rhodes_vintage_tape, warm: :crystal_pwm },
  # Madlib: a Fender Rhodes Stage 73, traded for the SP-1200 around 2000, and
  # essentially nothing else for chords across Yesterdays New Quintet and the
  # Shades of Blue re-recordings. One voice. No pad. rhodes_solo above is the
  # only other single-voice entry in this table.
  pad_madlib: { ep: :rhodes_stage73 },
  # Flying Lotus: names the Prophet 6 ("most versatile and approachable modern
  # analog synth") and the Yamaha CS-60/Deckard's Dream as his essentials
  # (Synth History interview), with a Wurlitzer among the keys.
  pad_flylo: { ep: :wurli_soul_bite, warm: :prophet_6_warm, warm2: :cs80_ensemble },
  # Röyksopp: the Juno-106 and MS-20 are the two they say will always be in the
  # setup; the Juno is the pad half of that pair. Solina and Mellotron stand in
  # for the PS-3100 and the Mellotron on the Melody A.M. list, and the DX-7 for
  # the EP attack.
  pad_royksopp: { ep: :dx7_bell_ep, warm: :juno_strings, warm2: :solina_ensemble,
                  texture: :mellotron_flute_pad },
  # Multi-layer stacks (rendered as 3–4 FluidSynth passes when PAD_LAYERS=1).
  # Rhodes + Prophet first; Moog is a thin undercurrent, not a competing bed.
  stack_soul: { ep: :rhodes_mark1, warm: :prophet_5_pad, warm2: :prophet_6_warm, texture: :moog_model_d },
  stack_rhodes: { ep: :rhodes_mark1, warm: :rhodes_stage73, warm2: :rhodes_cafe_warm },
  stack_prophet: { ep: :rhodes_cafe_warm, warm: :prophet_5_pad, warm2: :prophet_6_warm, texture: :prophet_pad },
  stack_glass: { ep: :dx7_bell_ep, warm: :glass_fm_pad, warm2: :prophet_6_warm, texture: :ice_string_pad },
  stack_vapor: { ep: :rhodes_mark1, warm: :vapor_supersaw, warm2: :prophet_5_pad, texture: :soft_synth_str },
  # Pure FM synthesis, no soundfont samples -- see PAD_LAYER_STACKS below.
  # Opt-in via PAD_VOICE=stack_fm_epiano + NATIVE_FM_PADS=1.
  stack_fm_epiano: { ep: :fm_epiano_body, warm: :fm_epiano_body, warm2: :fm_epiano_bell, texture: :fm_bell_pad },
  # --- External-SF2 stacks (need `ruby dilla.rb fetch-assets` for full colour) ---
  yamaha:        { ep: :yamaha_grand, warm: :tremolo_strings },
  yamaha_solo:   { ep: :yamaha_grand },
  vintage:       { ep: :vintage_dream_ep, warm: :vintage_dream_pad },
  vintage_choir: { ep: :vintage_dream_ep, warm: :vintage_dream_choir, texture: :vintage_dream_bell },
  giga_fm:       { ep: :giga_fm_ep, warm: :giga_fm_bell },
  giga_stack:    { ep: :giga_fm_ep, warm: :fm_bowed_pad, warm2: :giga_fm_choir },
  supersaw_bed:  { ep: :rhodes_cafe_warm, warm: :supersaw_pad },
  nylon_soul:    { ep: :nylon_guitar_pad, warm: :french_horn_pad },
  orchestral:    { ep: :yamaha_soft_pedal, warm: :tremolo_strings, warm2: :orchestral_harp_pad },
  harmonica:     { ep: :rhodes_vintage_tape, warm: :french_horn_pad },
  accordion:     { ep: :accordion_waltz, warm: :juno_chorus_wash },
  stack_yamaha:  { ep: :yamaha_grand, warm: :yamaha_soft_pedal, warm2: :tremolo_strings, texture: :harp_gliss },
  stack_vintage: { ep: :vintage_dream_ep, warm: :vintage_dream_pad, warm2: :vintage_dream_choir, texture: :vintage_dream_bell },
  stack_giga:    { ep: :giga_fm_ep, warm: :giga_fm_bell, warm2: :fm_bowed_pad, texture: :giga_fm_choir },
  # texture: harp dust (role:texture) — world lead colour lives in LEAD_VOICE=world/sitar
  stack_world:   { ep: :nylon_guitar_pad, warm: :french_horn_pad, warm2: :orchestral_harp_pad, texture: :harp_gliss },
}.freeze

# Explicit multi-layer pad stacks: id + amix weight. Order = mix order.
# Weights favor distinct timbres (EP attack, Moog body, Prophet air, Juno sheen).
PAD_LAYER_STACKS = {
  # The string machines, which is where this kind of beauty actually lives.
  #
  # A Rhodes carries the harmony because it has an attack and you can hear which
  # note is which; the ensembles underneath have almost none, which is the point.
  # The CS-80 and the Solina are both divide-down string machines whose whole
  # character is a slow chorused swell with no transient at all -- put a defined
  # voice on top of them and the chord reads clearly while the bed underneath
  # just widens.
  #
  # Rhodes first and loudest for that reason. CS-80 next because it has the most
  # movement. Solina under it for width. The Juno wash last and quietest -- its
  # chorus is the widest of the three and stacking it high smears the others.
  #
  # Four layers is the ceiling. A fifth ensemble adds no new information and
  # costs a FluidSynth pass, and the fourth is already at 0.5.
  stack_beauty: [
    { id: :rhodes_mark1, mix: 1.3, role: :ep },
    { id: :cs80_ensemble, mix: 1.1, role: :warm },
    { id: :solina_ensemble, mix: 0.8, role: :warm },
    { id: :juno_chorus_wash, mix: 0.5, role: :texture },
  ],
  # Mixes tuned so Rhodes tines and Prophet poly dominate; Moog is glue only.
  stack_soul: [
    { id: :rhodes_mark1, mix: 1.45, role: :ep },
    { id: :prophet_5_pad, mix: 1.05, role: :warm },
    { id: :prophet_6_warm, mix: 0.75, role: :warm },
    { id: :moog_model_d, mix: 0.38, role: :texture },
  ],
  stack_rhodes: [
    { id: :rhodes_mark1, mix: 1.4, role: :ep },
    { id: :rhodes_stage73, mix: 0.85, role: :warm },
    { id: :rhodes_cafe_warm, mix: 0.55, role: :warm },
  ],
  stack_prophet: [
    { id: :rhodes_cafe_warm, mix: 0.95, role: :ep },
    { id: :prophet_5_pad, mix: 1.35, role: :warm },
    { id: :prophet_6_warm, mix: 1.0, role: :warm },
    { id: :prophet_pad, mix: 0.55, role: :texture },
  ],
  stack_glass: [
    { id: :dx7_bell_ep, mix: 1.08, role: :ep },
    { id: :glass_fm_pad, mix: 0.95, role: :warm },
    { id: :prophet_6_warm, mix: 0.85, role: :warm },
    { id: :ice_string_pad, mix: 0.38, role: :texture },
  ],
  stack_vapor: [
    { id: :rhodes_mark1, mix: 1.2, role: :ep },
    { id: :prophet_5_pad, mix: 0.95, role: :warm },
    { id: :vapor_supersaw, mix: 0.7, role: :warm },
    { id: :soft_synth_str, mix: 0.32, role: :texture },
  ],
  # fm_epiano_body twice (roles :ep/:warm) reuses the unison-detune step
  # below (role == :warm && i.positive?) as the DX7 EPiano's "second
  # modulator-carrier pair, same ratio, only a little detuning." The bell
  # layer is the 14:1 tine-click pair, mixed low and fast-decaying.
  stack_fm_epiano: [
    { id: :fm_epiano_body, mix: 1.1, role: :ep },
    { id: :fm_epiano_body, mix: 0.8, role: :warm },
    { id: :fm_epiano_bell, mix: 0.32, role: :texture },
  ],
  stack_yamaha: [
    { id: :yamaha_grand, mix: 1.2, role: :ep },
    { id: :yamaha_soft_pedal, mix: 0.7, role: :warm },
    { id: :tremolo_strings, mix: 0.45, role: :warm },
    { id: :harp_gliss, mix: 0.22, role: :texture },
  ],
  stack_vintage: [
    { id: :vintage_dream_ep, mix: 1.1, role: :ep },
    { id: :vintage_dream_pad, mix: 0.9, role: :warm },
    { id: :vintage_dream_choir, mix: 0.4, role: :warm },
    { id: :vintage_dream_bell, mix: 0.2, role: :texture },
  ],
  stack_giga: [
    { id: :giga_fm_ep, mix: 1.12, role: :ep },
    { id: :giga_fm_bell, mix: 0.85, role: :warm },
    { id: :fm_bowed_pad, mix: 0.7, role: :warm },
    { id: :giga_fm_choir, mix: 0.35, role: :texture },
  ],
  stack_world: [
    { id: :nylon_guitar_pad, mix: 1.05, role: :ep },
    { id: :french_horn_pad, mix: 0.7, role: :warm },
    { id: :orchestral_harp_pad, mix: 0.5, role: :warm },
    { id: :harp_gliss, mix: 0.22, role: :texture },
  ],
}.freeze

# Morph rotation includes experimental families (good-sounding only).
PAD_VOICE_MORPH_VOICES = %i[moog prophet glass vapor rhodes neon crystal yamaha vintage giga_fm supersaw_bed].freeze

# Soft experimental lead morph — avoid shred/hard noise walls by default.
LEAD_MORPH_VOICES = %i[flylo prophet moog glass vapor soft yamaha vintage world steel].freeze
MORPH_LEAD_PATCH_POOL = {
  hard: %i[saw_lead square_lead dist_guitar charang_bite fm_lead_bell minimoog_lead fifths_lead overdrive_hook],
  flylo: %i[flylo_fm_shimmer fm_lead_bell glass_arp_lead flute_airy prophet_bleeding_lead giga_fm_lead],
  glitch: %i[square_lead voice_lead whistle_hook charang_bite banjo_pluck koto_pluck shamisen_pluck],
  prophet: %i[prophet_lead big_lead_prophet5 soul_prophet_arp warm_prophet_hook prophet_bleeding_lead],
  moog: %i[moog_ladder_lead minimoog_lead moog_dilla_pocket questlove_moog_lead acid_pluck_lead synth_bass_deep],
  shred: %i[dist_guitar charang_bite saw_lead square_lead brass_synth pluck_synth overdrive_hook],
  glass: %i[glass_arp_lead flylo_fm_shimmer fm_lead_bell giga_fm_bell],
  vapor: %i[vapor_lead supersaw_1 supersaw_2 supersaw_4 tame_wobble_lead],
  soft: %i[soft_synth_lead jazz_ballad_lead nord_stage_lead watermelon_glass yamaha_ballad_lead],
  yamaha: %i[yamaha_ballad_lead yamaha_scale_arp clean_jazz_guitar],
  vintage: %i[vintage_dream_lead giga_fm_lead harmonica_soul],
  world: %i[sitar_drone shamisen_pluck shakuhachi_breath steel_drums fiddle_reel],
  steel: %i[steel_string clean_jazz_guitar nylon_guitar_pad steel_drums],
}.freeze
MORPH_LEAD_ARP_CYCLE = %i[flylo_spiral prophet_saw moog_rip soul_wash glass_spin vapor_wave neo_quartal].freeze

# FM synthesis — integer C:M = musical; irrational→rational morph stabilizes metallic timbres.
FM_RATIO_POOL = [
  { m: 1.0, c: 1.0, target_m: 1.0, irrational: false },
  { m: 2.0, c: 1.0, target_m: 2.0, irrational: false },
  { m: 3.0, c: 1.0, target_m: 3.0, irrational: false },
  { m: 3.0, c: 2.0, target_m: 3.0, irrational: false },
  { m: 5.0, c: 2.0, target_m: 5.0, irrational: false },
  { m: 1.37, c: 1.0, target_m: 1.0, irrational: true },
  { m: 2.71, c: 1.0, target_m: 2.0, irrational: true },
  { m: 3.87, c: 1.0, target_m: 3.0, irrational: true },
].freeze
FM_INDEX_BASE_PAD = 1.8
FM_INDEX_BASE_XLEAD = 2.6
FM_INDEX_VEL_SCALE = 3.2
FM_FEEDBACK_DEFAULT = 0.18
FM_XLEAD_NATIVE_MIX = 0.42

# Per-track pad character — applied on stream rotation and deep renders unless
# PAD_VOICE / PAD_ARP_MODE were set on the CLI before launch.
TRACK_SOUL_PAD_PROFILES = {
  modern_quartal_stack:     { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100" },
  slow_ballad_wash:    { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  suspended_ballad:    { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3400" },
  neo_soul_pocket:     { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer" },
  quartal_west_coast:  { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  maj7_minor_cycle:    { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1050", "PAD_RELEASE" => "2800" },
  minor_iv_loop:       { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer" },
  two_chord_hypnosis:  { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  relative_major_turn: { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  minor_turnaround:    { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "blend" },
  warm_minor_arc:      { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  minor_triad_walk:    { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "figure" },
  major_lifting:       { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "blend" },
  slash_ninth_cycle:   { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "duo" },
  dorian_iv_loop:      { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  backdoor_resolve:    { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  gospel_bIII:         { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "shimmer" },
  warm_minor_vamp:        { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1000" },
  funk_sixteenth_turn:     { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  church_sus:          { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "held" },
  jazz_ballad_waltz:   { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1400" },
  slash_neo_soul:      { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "duo" },
  modal_safe:          { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  minMaj_color:        { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  electronium_loop:    { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3200" },
  electronium_classic: { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "980", "PAD_RELEASE" => "2600" },
  fourth_third_sixth_second_turn: { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1400", "PAD_RELEASE" => "3800" },
  modal_quartal_ladder: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200", "VOICING" => "quartal" },
  minor_two_five_chain:     { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "1050", "PAD_RELEASE" => "2800", "VOICING" => "bill_evans" },
  circle_fifths_descent: { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "figure", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2400", "VOICING" => "drop2" },
  walking_bass_descent: { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3000", "VOICING" => "kenny_barron" },
  timeless_authentic:  { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3600" },
  long_soul:           { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "74" },
  golden:              { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "74" },
  chromatic_mediant_drift: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  # Expansion pack — Rhodes / Prophet / Moog pairings for new progressions.
  lydian_glass_cycle:      { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3400" },
  pedal_upper_structures:  { "PAD_VOICE" => "neon", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3600" },
  bossa_major9_turn:       { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2600" },
  phrygian_gold_arc:       { "PAD_VOICE" => "vapor", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3000" },
  two_chord_luminous:      { "PAD_VOICE" => "crystal", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1600", "PAD_RELEASE" => "4200" },
  mixo_sus_loop:           { "PAD_VOICE" => "pulse", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "800", "PAD_RELEASE" => "2200" },
  common_tone_drift:       { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1150", "PAD_RELEASE" => "3200" },
  third_cycle_triads:     { "PAD_VOICE" => "ice", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1000", "PAD_RELEASE" => "2800" },
  drone_quartal_wash:      { "PAD_VOICE" => "vapor", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "VOICING" => "quartal" },
  waltz_relative_lift:     { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  half_time_gospel_plagal: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1400", "PAD_RELEASE" => "3800" },
  double_time_pocket:      { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "700", "PAD_RELEASE" => "1800" },
  whole_tone_bridge:       { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "figure", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2400" },
  upper_triad_tower:       { "PAD_VOICE" => "crystal", "PAD_ARP_MODE" => "duo", "PAD_ATTACK" => "1000", "PAD_RELEASE" => "2800" },
  minor_add9_lullaby:      { "PAD_VOICE" => "ice", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1700", "PAD_RELEASE" => "4500" },
  dominant_chain_home:     { "PAD_VOICE" => "neon", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "850", "PAD_RELEASE" => "2200" },
}.freeze

# Per-track lead voice + arp figure — pairs with TRACK_SOUL_PAD_PROFILES.
TRACK_SOUL_LEAD_PROFILES = {
  modern_quartal_stack:     { "LEAD_VOICE" => "cs", "LEAD_ARP_MODE" => "neo_quartal" },
  slow_ballad_wash:    { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  suspended_ballad:    { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "soul_wash" },
  neo_soul_pocket:     { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "moog_funk" },
  quartal_west_coast:  { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral" },
  maj7_minor_cycle:    { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "LEAD_ARP" => "1", "HARMONY_LEAD" => "1" },
  minor_iv_loop:       { "LEAD_VOICE" => "donuts", "LEAD_ARP_MODE" => "donuts_shimmer" },
  two_chord_hypnosis:  { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab" },
  relative_major_turn: { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "donuts_shimmer" },
  minor_turnaround:    { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  warm_minor_arc:      { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "soul_wash" },
  minor_triad_walk:    { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "flylo_spiral" },
  major_lifting:       { "LEAD_VOICE" => "prophet", "LEAD_ARP_MODE" => "neo_quartal" },
  slash_ninth_cycle:   { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "prophet_glass" },
  dorian_iv_loop:      { "LEAD_VOICE" => "prophet", "LEAD_ARP_MODE" => "soul_wash" },
  backdoor_resolve:    { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "moog_funk" },
  gospel_bIII:         { "LEAD_VOICE" => "gospel", "LEAD_ARP_MODE" => "gospel_lift" },
  warm_minor_vamp:        { "LEAD_VOICE" => "erykah", "LEAD_ARP_MODE" => "erykah_dust" },
  funk_sixteenth_turn:     { "LEAD_VOICE" => "watermelon", "LEAD_ARP_MODE" => "donuts_shimmer" },
  church_sus:          { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  jazz_ballad_waltz:   { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  slash_neo_soul:      { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  modal_safe:          { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab" },
  minMaj_color:        { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash" },
  electronium_loop:    { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "LEAD_ARP" => "1", "HARMONY_LEAD" => "1" },
  electronium_classic: { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  fourth_third_sixth_second_turn: { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1" },
  modal_quartal_ladder: { "LEAD_VOICE" => "cs", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1" },
  minor_two_five_chain:     { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1" },
  circle_fifths_descent: { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1" },
  walking_bass_descent: { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1" },
  timeless_authentic:  { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "prophet_glass", "HARMONY_LEAD" => "1" },
  long_soul:           { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  golden:              { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  chromatic_mediant_drift: { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  lydian_glass_cycle:      { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "glass_spin", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  pedal_upper_structures:  { "LEAD_VOICE" => "neon", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  bossa_major9_turn:       { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  phrygian_gold_arc:       { "LEAD_VOICE" => "vapor", "LEAD_ARP_MODE" => "vapor_wave", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  two_chord_luminous:      { "LEAD_VOICE" => "crystal", "LEAD_ARP_MODE" => "crystal_scatter", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  mixo_sus_loop:           { "LEAD_VOICE" => "acid", "LEAD_ARP_MODE" => "acid_run", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  common_tone_drift:       { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "glass_spin", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  third_cycle_triads:     { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  drone_quartal_wash:      { "LEAD_VOICE" => "vapor", "LEAD_ARP_MODE" => "vapor_wave", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  waltz_relative_lift:     { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  half_time_gospel_plagal: { "LEAD_VOICE" => "gospel", "LEAD_ARP_MODE" => "gospel_lift", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  double_time_pocket:      { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  whole_tone_bridge:       { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "crystal_scatter", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  upper_triad_tower:       { "LEAD_VOICE" => "crystal", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  minor_add9_lullaby:      { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  dominant_chain_home:     { "LEAD_VOICE" => "acid", "LEAD_ARP_MODE" => "acid_run", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
}.freeze

LEAD_VOICE_PRESETS = {
  # The two boxes Dilla and Flying Lotus both actually worked on. Named so
  # LEAD_VOICE=voyager reaches the patch -- a patch defined and never listed in
  # a pool is unreachable, which is exactly the state minimoog_bass is in.
  voyager: :voyager_mono_lead,
  microkorg: :microkorg_lead,
  donuts: :donuts_wurli_lead,
  soul_prophet: :soul_prophet_arp,
  prophet: :soul_prophet_arp,
  moog: :moog_dilla_pocket,
  neo_pluck: :neo_soul_pluck,
  flylo: :flylo_fm_shimmer,
  ballad: :jazz_ballad_lead,
  gospel: :gospel_brass_lead,
  erykah: :erykah_dust_lead,
  watermelon: :watermelon_glass,
  soft: :soft_synth_lead,
  cs: :cs_lead,
  minimoog: :minimoog_lead,
  pluck: :neo_soul_pluck,
  glass: :glass_arp_lead,
  vapor: :vapor_lead,
  crystal: :glass_arp_lead,
  acid: :acid_pluck_lead,
  neon: :moog_ladder_lead,
  yamaha: :yamaha_ballad_lead,
  vintage: :vintage_dream_lead,
  giga: :giga_fm_lead,
  supersaw: :supersaw_4,
  harmonica: :harmonica_soul,
  guitar: :clean_jazz_guitar,
  steel: :steel_string,
  sitar: :sitar_drone,
  world: :shakuhachi_breath,
  horn: :muted_trumpet_lead,
  brass: :trombone_soul,
  bass: :synth_bass_deep,
  steelpan: :steel_drums,
}.freeze

# Lush + experimental electronic cycles (SYNTH_CYCLE=1).
LUSH_PATCH_CYCLE_EP = {
  rhodes: %i[rhodes_mark1 rhodes_bleeding_edge rhodes_vintage_tape rhodes_cafe_warm rhodes_stage73 galaxy_ep1 yamaha_grand giga_fm_ep],
  moog: %i[rhodes_mark1 rhodes_vintage_tape rhodes_bleeding_edge galaxy_ep1 vintage_dream_ep],
  prophet: %i[rhodes_mark1 rhodes_cafe_warm rhodes_bleeding_edge galaxy_ep1 galaxy_ep2 yamaha_soft_pedal],
  blend: %i[rhodes_mark1 rhodes_bleeding_edge rhodes_vintage_tape rhodes_cafe_warm rhodes_stage73 galaxy_ep1 galaxy_ep2 yamaha_grand giga_fm_ep vintage_dream_ep],
  glass: %i[dx7_bell_ep galaxy_ep2 rhodes_dx_blend celeste_dust giga_fm_ep],
  vapor: %i[rhodes_cafe_warm galaxy_ep1 ep_mark1_dark vintage_dream_ep],
  crystal: %i[galaxy_ep2 dx_ep_glass vibes_mallet galaxy_ep3],
  ice: %i[rhodes_dx_blend galaxy_ep1 celeste_dust yamaha_soft_pedal],
  neon: %i[rhodes_mark1 clav_neo_funk giga_fm_ep],
  pulse: %i[clav_neo_funk wurli_bite dx7_bell_ep accordion_waltz],
  yamaha: %i[yamaha_grand yamaha_soft_pedal yamaha_honky soul_piano_tack],
  vintage: %i[vintage_dream_ep galaxy_ep1 rhodes_vintage_tape],
  giga_fm: %i[giga_fm_ep dx7_bell_ep galaxy_ep2],
}.freeze

LUSH_PATCH_CYCLE_WARM = {
  rhodes: %i[juno_chorus_wash prophet_6_warm tape_string_pad polysynth_soul memorymoon_pad string_orchestra tremolo_strings],
  moog: %i[moog_model_d moog_sub37_pad moog_pad moog_bleeding_edge warm_analog_duo neon_ladder],
  prophet: %i[prophet_5_pad prophet_6_warm prophet_pad polysynth_soul juno_chorus_wash cs80_ensemble supersaw_pad],
  blend: %i[prophet_5_pad moog_model_d prophet_6_warm moog_sub37_pad juno_chorus_wash polysynth_soul vintage_dream_pad giga_fm_bell],
  glass: %i[glass_fm_pad crystal_pwm ice_string_pad giga_fm_bell],
  vapor: %i[vapor_supersaw prophet_rev2_bleeding juno_chorus_wash supersaw_pad],
  crystal: %i[crystal_pwm glass_fm_pad pwm_sweep_pad],
  ice: %i[ice_string_pad solina_ensemble tape_string_pad french_horn_pad],
  neon: %i[neon_ladder moog_bleeding_edge analog_hollow],
  pulse: %i[pwm_sweep_pad crystal_pwm analog_pad1],
  yamaha: %i[tremolo_strings french_horn_pad tape_string_pad],
  vintage: %i[vintage_dream_pad vintage_dream_choir supersaw_pad],
  giga_fm: %i[giga_fm_bell fm_bowed_pad giga_fm_choir],
}.freeze

LUSH_LEAD_VOICE_POOLS = {
  donuts: %i[mark1_soul_lead rhodes_lead_comp donuts_wurli_lead yamaha_ballad_lead],
  soul_prophet: %i[soul_prophet_arp prophet_lead warm_prophet_hook big_lead_prophet5],
  prophet: %i[soul_prophet_arp prophet_lead warm_prophet_hook glasper_ep_lead],
  moog: %i[moog_dilla_pocket questlove_moog_lead minimoog_lead moog_ladder_lead synth_bass_deep],
  neo_pluck: %i[neo_soul_pluck dangelo_clav_lead rhodes_skank_lead steel_string],
  flylo: %i[flylo_fm_shimmer fm_lead_bell glass_arp_lead giga_fm_lead],
  ballad: %i[jazz_ballad_lead nord_stage_lead glasper_ep_lead soft_synth_lead yamaha_ballad_lead],
  gospel: %i[gospel_brass_lead stevie_organ_lead trombone_soul],
  erykah: %i[erykah_dust_lead rhodes_lead_comp mark1_soul_lead],
  watermelon: %i[watermelon_glass nord_stage_lead glasper_ep_lead],
  soft: %i[soft_synth_lead nord_stage_lead rhodes_lead_comp yamaha_ballad_lead],
  cs: %i[glasper_ep_lead soul_prophet_arp rhodes_lead_comp],
  minimoog: %i[minimoog_lead moog_ladder_lead questlove_moog_lead],
  pluck: %i[neo_soul_pluck dangelo_clav_lead shamisen_pluck],
  glass: %i[glass_arp_lead flylo_fm_shimmer fm_lead_bell giga_fm_lead],
  vapor: %i[vapor_lead supersaw_1 supersaw_4 tame_wobble_lead],
  crystal: %i[glass_arp_lead fm_lead_bell],
  acid: %i[acid_pluck_lead moog_ladder_lead],
  neon: %i[moog_ladder_lead minimoog_lead acid_pluck_lead],
  yamaha: %i[yamaha_ballad_lead yamaha_scale_arp clean_jazz_guitar],
  vintage: %i[vintage_dream_lead giga_fm_lead harmonica_soul],
  giga: %i[giga_fm_lead giga_fm_bass_lead flylo_fm_shimmer],
  supersaw: %i[supersaw_1 supersaw_2 supersaw_4 vapor_lead],
  harmonica: %i[harmonica_soul muted_trumpet_lead],
  guitar: %i[clean_jazz_guitar steel_string nylon_guitar_pad],
  steel: %i[steel_string steel_drums clean_jazz_guitar],
  sitar: %i[sitar_drone shamisen_pluck],
  world: %i[shakuhachi_breath sitar_drone fiddle_reel steel_drums],
  horn: %i[muted_trumpet_lead trombone_soul english_horn],
  brass: %i[trombone_soul gospel_brass_lead muted_trumpet_lead],
  bass: %i[synth_bass_deep slap_bass_lead moog_dilla_pocket],
  steelpan: %i[steel_drums vibes_mallet],
}.freeze

# Per-voice families — random cycle picks within these pools each render (SYNTH_CYCLE=1).
PATCH_CYCLE_EP = {
  rhodes: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_dx_blend rhodes_bleeding_edge
    rhodes_vintage_tape rhodes_cafe_warm wurli_soul_bite clav_neo_funk dx7_bell_ep
    galaxy_ep1 galaxy_ep2 galaxy_ep_bleeding organ_drawbar organ_perc vibes_mallet celeste_dust
  ],
  moog: %i[
    rhodes_mark1 rhodes_stage73 rhodes_vintage_tape dx7_bell_ep galaxy_ep1 ep_mark1_dark
    clav_neo_funk wurli_soul_bite
  ],
  prophet: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_cafe_warm galaxy_ep1 galaxy_ep2
    organ_drawbar dx_ep_glass vibes_mallet
  ],
  blend: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_dx_blend rhodes_vintage_tape
    rhodes_cafe_warm wurli_soul_bite clav_neo_funk dx7_bell_ep galaxy_ep1 galaxy_ep2
    galaxy_ep_bleeding organ_drawbar organ_perc vibes_mallet soul_piano_tack
  ],
  glass: %i[dx7_bell_ep galaxy_ep2 rhodes_dx_blend celeste_dust giga_fm_ep],
  vapor: %i[rhodes_cafe_warm galaxy_ep1 ep_mark1_dark vintage_dream_ep],
  crystal: %i[galaxy_ep2 dx_ep_glass vibes_mallet galaxy_ep3],
  ice: %i[rhodes_dx_blend galaxy_ep1 celeste_dust yamaha_soft_pedal],
  neon: %i[rhodes_mark1 clav_neo_funk giga_fm_ep],
  pulse: %i[clav_neo_funk wurli_bite dx7_bell_ep accordion_waltz],
  yamaha: %i[yamaha_grand yamaha_soft_pedal yamaha_honky soul_piano_tack galaxy_ep1],
  vintage: %i[vintage_dream_ep galaxy_ep1 rhodes_vintage_tape ep_mark1_dark],
  giga_fm: %i[giga_fm_ep dx7_bell_ep galaxy_ep2 rhodes_dx_blend],
  supersaw_bed: %i[rhodes_cafe_warm galaxy_ep1 yamaha_grand],
  nylon_soul: %i[nylon_guitar_pad rhodes_cafe_warm soul_piano_tack],
  orchestral: %i[yamaha_soft_pedal yamaha_grand soul_piano_tack],
}.freeze

PATCH_CYCLE_WARM = {
  rhodes: %i[
    juno_strings juno_chorus_wash solina_ensemble string_orchestra tape_string_pad
    prophet_6_warm slow_attack_pad cs80_ensemble pwm_sweep_pad analog_pad1 mellotron_flute_pad
    polysynth_soul memorymoon_pad warm_analog_duo tremolo_strings
  ],
  moog: %i[
    moog_model_d moog_sub37_pad moog_pad moog_bleeding_edge prophet_rev2_bleeding
    warm_analog_duo analog_hollow analog_pad2 prophet_brass_wash neon_ladder
  ],
  prophet: %i[
    prophet_5_pad prophet_6_warm prophet_pad prophet_rev2_bleeding cs80_ensemble
    oberheim_pad pwm_sweep_pad polysynth_soul memorymoon_pad juno_chorus_wash
    analog_pad1 tape_string_pad supersaw_pad
  ],
  blend: %i[
    prophet_5_pad moog_model_d prophet_6_warm moog_sub37_pad juno_strings juno_chorus_wash
    prophet_pad moog_pad cs80_ensemble solina_ensemble string_orchestra warm_analog_duo
    memorymoon_pad tape_string_pad polysynth_soul mellotron_flute_pad analog_hollow
    slow_attack_pad oberheim_pad vintage_dream_pad giga_fm_bell
  ],
  glass: %i[glass_fm_pad crystal_pwm ice_string_pad giga_fm_bell],
  vapor: %i[vapor_supersaw prophet_rev2_bleeding juno_chorus_wash supersaw_pad],
  crystal: %i[crystal_pwm glass_fm_pad pwm_sweep_pad],
  ice: %i[ice_string_pad solina_ensemble tape_string_pad french_horn_pad],
  neon: %i[neon_ladder moog_bleeding_edge analog_hollow],
  pulse: %i[pwm_sweep_pad crystal_pwm analog_pad1],
  yamaha: %i[tremolo_strings french_horn_pad tape_string_pad string_orchestra],
  vintage: %i[vintage_dream_pad vintage_dream_choir supersaw_pad juno_chorus_wash],
  giga_fm: %i[giga_fm_bell fm_bowed_pad giga_fm_choir glass_fm_pad],
  supersaw_bed: %i[supersaw_pad vapor_supersaw prophet_6_warm],
  nylon_soul: %i[french_horn_pad tape_string_pad juno_chorus_wash],
  orchestral: %i[tremolo_strings orchestral_harp_pad french_horn_pad string_orchestra],
}.freeze

LEAD_VOICE_POOLS = {
  donuts: %i[donuts_wurli_lead mark1_soul_lead wurli_soul_bite rhodes_skank_lead jupiter_superlead yamaha_ballad_lead],
  soul_prophet: %i[soul_prophet_arp jupiter_superlead warm_prophet_hook prophet_bleeding_lead mono_poly_lead],
  prophet: %i[jupiter_superlead soul_prophet_arp warm_prophet_hook mono_poly_lead obxr_sync_lead],
  moog: %i[moog_dilla_pocket mono_poly_lead questlove_moog_lead minimoog_lead sh101_sequence synth_bass_deep],
  neo_pluck: %i[neo_soul_pluck dx7_glass_arp dangelo_clav_lead glass_arp_lead steel_string],
  flylo: %i[flylo_fm_shimmer dx7_glass_arp glass_arp_lead tame_wobble_lead jupiter_superlead giga_fm_lead],
  ballad: %i[jazz_ballad_lead cs80_brass_lead nord_stage_lead soft_synth_lead yamaha_ballad_lead],
  gospel: %i[cs80_brass_lead gospel_brass_lead stevie_organ_lead jp8_brass_arp trombone_soul],
  erykah: %i[erykah_dust_lead portishead_dust_lead rhodes_lead_comp mark1_soul_lead],
  watermelon: %i[watermelon_glass nord_stage_lead dx7_glass_arp rhodes_lead_comp],
  soft: %i[soft_synth_lead jazz_ballad_lead nord_stage_lead rhodes_lead_comp yamaha_ballad_lead],
  cs: %i[cs80_brass_lead cs_lead glasper_ep_lead soul_prophet_arp],
  minimoog: %i[minimoog_lead mono_poly_lead questlove_moog_lead moog_dilla_pocket],
  pluck: %i[neo_soul_pluck dx7_glass_arp dangelo_clav_lead glass_arp_lead shamisen_pluck],
  glass: %i[dx7_glass_arp glass_arp_lead flylo_fm_shimmer jupiter_superlead giga_fm_lead],
  vapor: %i[vapor_lead jupiter_superlead tame_wobble_lead obxr_sync_lead supersaw_4],
  crystal: %i[dx7_glass_arp glass_arp_lead crystal_scale_lead],
  acid: %i[acid_pluck_lead sh101_sequence mono_poly_lead moog_ladder_lead],
  neon: %i[obxr_sync_lead mono_poly_lead jupiter_superlead acid_pluck_lead],
  yamaha: %i[yamaha_ballad_lead yamaha_scale_arp clean_jazz_guitar],
  vintage: %i[vintage_dream_lead giga_fm_lead harmonica_soul],
  giga: %i[giga_fm_lead giga_fm_bass_lead flylo_fm_shimmer],
  supersaw: %i[supersaw_1 supersaw_2 supersaw_4 vapor_lead],
  harmonica: %i[harmonica_soul muted_trumpet_lead],
  guitar: %i[clean_jazz_guitar steel_string],
  steel: %i[steel_string steel_drums clean_jazz_guitar],
  sitar: %i[sitar_drone shamisen_pluck],
  world: %i[shakuhachi_breath sitar_drone fiddle_reel steel_drums],
  horn: %i[muted_trumpet_lead trombone_soul english_horn],
  brass: %i[trombone_soul gospel_brass_lead muted_trumpet_lead],
  bass: %i[synth_bass_deep slap_bass_lead moog_dilla_pocket],
  steelpan: %i[steel_drums vibes_mallet],
}.freeze

PATCH_CYCLE_TEXTURE = %i[
  soft_synth_str shimmer_organ ethnic_flute kalimba_dust space_voice reverse_pad_ghost music_box
  harp_gliss vintage_dream_bell tinkle_bell bottle_blow agogo_perc seashore_bed breath_noise
  microkorg_vox_texture
].freeze

PATCH_CYCLE_SCALE_LEAD = %i[
  scale_arp_rhodes scale_arp_prophet scale_arp_moog scale_arp_supersaw crystal_scale_lead
  jp8_brass_arp sh101_sequence dx7_glass_arp jupiter_superlead glass_arp_lead
  rhodes_lead_comp glasper_ep_lead soul_prophet_arp yamaha_scale_arp supersaw_scale
].freeze

# Named lead-arp figures — tuned for lead register (louder/clearer than legacy pad arp).
LEAD_ARP_PRESETS = {
  donuts_shimmer: { style: :skip_up, subdiv: 8, gate: 0.66, vel: 0.48,
                    arp_styles: %i[skip_up euclidean quint_spread] },
  soul_wash:      { style: :updown, subdiv: 2, gate: 0.88, vel: 0.48,
                    arp_styles: %i[updown motif] },
  # Sparse chord-tone melody (quarter / half notes) — not dense random soup.
  melodic_soul:   { style: :motif, subdiv: 1, gate: 0.92, vel: 0.52,
                    arp_styles: %i[motif updown] },
  moog_funk:      { style: :up, subdiv: 4, gate: 0.7, vel: 0.54,
                    arp_styles: %i[up downup quint_spread] },
  prophet_glass:  { style: :pingpong, subdiv: 6, gate: 0.62, vel: 0.52,
                    arp_styles: %i[pingpong skip_up updown] },
  flylo_spiral:   { style: :spiral, subdiv: 8, gate: 0.58, vel: 0.46,
                    arp_styles: %i[spiral fibonacci random_walk] },
  neo_quartal:    { style: :quint_spread, subdiv: 6, gate: 0.68, vel: 0.46,
                    arp_styles: %i[quint_spread updown major_third_cycle_full] },
  ballad_bloom:   { style: :updown, subdiv: 4, gate: 0.76, vel: 0.44,
                    arp_styles: %i[updown major_third_cycle_full] },
  pocket_stab:    { style: :donda_stab, subdiv: 8, gate: 0.52, vel: 0.56,
                    arp_styles: %i[donda_stab skip_up euclidean] },
  erykah_dust:    { style: :euclidean, subdiv: 8, gate: 0.72, vel: 0.42,
                    arp_styles: %i[euclidean skip_up] },
  gospel_lift:    { style: :major_third_cycle_full, subdiv: 6, gate: 0.64, vel: 0.5,
                    arp_styles: %i[major_third_cycle_full up quint_spread] },
  # Experimental electronic figures (musical, not chaotic).
  glass_spin:     { style: :spiral, subdiv: 6, gate: 0.58, vel: 0.46,
                    arp_styles: %i[spiral quint_spread pingpong] },
  vapor_wave:     { style: :updown, subdiv: 4, gate: 0.7, vel: 0.44,
                    arp_styles: %i[updown flylo_wobble] },
  acid_run:       { style: :up, subdiv: 8, gate: 0.42, vel: 0.52,
                    arp_styles: %i[up skip_up euclidean] },
  crystal_scatter: { style: :fibonacci, subdiv: 6, gate: 0.55, vel: 0.45,
                     arp_styles: %i[fibonacci spiral skip_up] },
}.freeze

# Aggressive xlead arp figures — per-chord morph when LEAD_MORPH=1.
EXPERIMENTAL_LEAD_ARP_PRESETS = {
  hard_stab:     { style: :donda_stab, subdiv: 8, gate: 0.44, vel: 0.64,
                   arp_styles: %i[donda_stab euclidean flylo_wobble stutter burst] },
  flylo_spiral:  { style: :spiral, subdiv: 8, gate: 0.52, vel: 0.56,
                   arp_styles: %i[spiral fibonacci random_walk flylo_wobble ratchet] },
  glitch_walk:   { style: :random_walk, subdiv: 12, gate: 0.4, vel: 0.58,
                   arp_styles: %i[random_walk stutter ratchet euclidean burst] },
  prophet_saw:   { style: :pingpong, subdiv: 6, gate: 0.5, vel: 0.58,
                   arp_styles: %i[pingpong skip_up major_third_cycle_full quint_spread] },
  moog_rip:      { style: :up, subdiv: 4, gate: 0.62, vel: 0.6,
                   arp_styles: %i[up downup quint_spread ratchet stutter] },
  shred_burst:   { style: :burst, subdiv: 8, gate: 0.38, vel: 0.66,
                   arp_styles: %i[burst stutter donda_stab flylo_wobble] },
  stutter_gate:  { style: :stutter, subdiv: 12, gate: 0.35, vel: 0.62,
                   arp_styles: %i[stutter ratchet euclidean skip_up burst] },
  ratchet_funk:  { style: :ratchet, subdiv: 6, gate: 0.48, vel: 0.64,
                   arp_styles: %i[ratchet updown major_third_cycle_full burst flylo_wobble] },
}.freeze

PAD_TO_LEAD_ARP = {
  wash: :soul_wash, shimmer: :donuts_shimmer, pulse: :moog_funk, blend: :neo_quartal,
  duo: :prophet_glass, figure: :flylo_spiral, held: nil,
}.freeze
