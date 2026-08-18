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

def form_section_at(bar, _n_bars)
  map = resolve_form_map
  return unless map&.any?
  cycle_len = map.sum { |_, len| len }
  return if cycle_len <= 0
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
