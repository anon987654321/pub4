# frozen_string_literal: true

# Tier-B ML stubs — heuristic fallbacks until `tools/dilla-ml/` ships.
module DillaMl
  module_function

  def groove_synced_vinyl(ghost_count, kick_count, base: 0.06)
    base = base.to_f
    return 0.0 if base <= 0.0
    g = ghost_count.to_f / [kick_count, 1].max
    # Honor low bases (e.g. VINYL=10 → ~0.018); do not force a 0.04 floor of hiss.
    lo = [base * 0.85, 0.008].max
    (base + g * 0.012).clamp(lo, 0.12).round(3)
  end

  def ddsp_stub_note
    "DDSP sidecar not installed — using heuristic spectral regen. Set DILLA_ML=1 when tools/dilla-ml ships."
  end

end
