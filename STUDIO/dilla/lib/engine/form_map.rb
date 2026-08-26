# frozen_string_literal: true
#
# Song form: section maps, motifs per chord.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def motif_from_chord(chord)
  return [0, 1, 2, 1] unless chord && chord[:hz]&.any?
  tones = chord[:hz].sort
  [0, 1, 2, tones.length > 3 ? 3 : 1]
end

def chord_symbol_key(chord)
  chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
end

# Phrase-locked recall — same 4-note figure whenever the same chord symbol returns.
def chord_motif_for(chord)
  sym = chord_symbol_key(chord)
  @chord_motif_cache ||= {}
  return @chord_motif_cache[sym] if motif_recall_enabled? && @chord_motif_cache.key?(sym)
  motif = motif_from_chord(chord)
  @chord_motif_cache[sym] = motif if motif_recall_enabled?
  motif
end

def parse_section_map!(raw)
  raw.split(",").filter_map do |pair|
    name, len = pair.strip.split(":", 2)
    next unless name && len
    kind = SECTION_KIND_ALIASES.fetch(name.downcase, name.downcase.to_sym)
    [kind, len.to_i]
  end
end

def resolve_form_map
  return @resolve_form_map if defined?(@resolve_form_map) && @resolve_form_map
  if ENV["SECTION_MAP"] && !ENV["SECTION_MAP"].empty?
    @resolve_form_map = parse_section_map!(ENV["SECTION_MAP"])
  elsif ENV["FORM"] && !ENV["FORM"].empty?
    preset = FORM_PRESETS[ENV["FORM"].to_sym]
    @resolve_form_map = preset&.fetch(:map, nil)
  end
  @resolve_form_map
end

# FORM_FIT — stretch the form across the track instead of repeating it.
#
# A form is a CYCLE here: form_section_at takes `bar % cycle_len`, so a 32-bar
# map over a 128-bar render is four copies of itself -- four intros, four outros,
# an "intro" arriving at bars 32, 64 and 96. An intro that happens four times is
# not an intro, and a form that repeats is a loop of a form rather than the shape
# of a piece.
#
# That matters for what this engine is being asked to do. The records it is
# measured against have one or two section boundaries across four or five
# minutes -- a whole-song arc, each part happening once. dilla could not express
# that at any length: the only way to get a single pass was to hand-write a
# SECTION_MAP whose lengths happen to sum to the exact bar count, which is a
# different map for every render length.
#
# So: scale the map's proportions to the track. intro:4,main:8,build:8,turn:8,
# outro:4 over 128 bars becomes 16/32/32/32/16 rather than four passes of
# 4/8/8/8/4. The shape is the operator's; only its size follows the render.
#
# ON BY DEFAULT PAST 64 BARS. Below about two passes a repeated form reads as a
# repeated form, which is a legitimate thing to want on a beat. Past it, it stops
# being a form at all: nothing is unique and "intro" stops meaning anything a
# listener can hear. soul_32 and camel_32 are 32-bar maps, so 64 is exactly two
# passes -- the last length at which a repeat is still a structure rather than a
# loop of one.
#
# FORM_FIT=0 forces cycling at any length and FORM_FIT=1 forces fitting; only the
# unset case consults the bar count. A render that sets no FORM is untouched
# either way, because form_section_at is never reached without one -- so this
# changes nothing for the default render path and everything for a long one that
# asked for a shape.
FORM_FIT_DEFAULT_BARS = 64

def form_fit_enabled?(n_bars = nil)
  case ENV["FORM_FIT"]
  when "1" then true
  when "0" then false
  else n_bars.to_i > FORM_FIT_DEFAULT_BARS
  end
end

def form_section_at(bar, n_bars)
  map = resolve_form_map
  return unless map&.any?
  cycle_len = map.sum { |_, len| len }
  return if cycle_len <= 0

  if form_fit_enabled?(n_bars) && n_bars.to_i.positive?
    # Proportional, in bars, with the last section absorbing the rounding so the
    # map always covers the track exactly. Rounding each section independently
    # leaves a gap or an overlap at the end, and a bar belonging to no section
    # falls through to the legacy map -- which would put a stray `main` after the
    # outro and be hard to see.
    scaled = 0.0
    map.each_with_index do |(kind, len), i|
      return kind if i == map.length - 1

      scaled += len.to_f * n_bars / cycle_len
      return kind if bar < scaled.round
    end
  end

  pos = bar % cycle_len
  cumulative = 0
  map.each do |kind, len|
    return kind if pos < cumulative + len
    cumulative += len
  end
  map.last.first
end

def apply_form_to_cfg!(cfg)
  form = ENV["FORM"]&.to_sym
  preset = FORM_PRESETS[form] if form && FORM_PRESETS.key?(form)
  preset ||= FORM_PRESETS[:camel_32] if %w[camel dilla].include?(ENV["RENDER_MODE"].to_s.downcase)
  preset ||= FORM_PRESETS[:soul_16] if ENV["RENDER_MODE"] == "long_soul" || ENV["RENDER_MODE"] == "golden"
  return cfg unless preset
  cfg.merge(
    intro_bars: preset[:intro_bars] || cfg[:intro_bars],
    phrase_bars: preset[:phrase_bars] || cfg[:phrase_bars],
    form: form || :soul_16,
  )
end
