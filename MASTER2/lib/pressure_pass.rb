# frozen_string_literal: true

module MASTER
  # PressurePass is the legacy name for Refinement.
  # All callers should use Refinement directly; this alias exists only for
  # backward compatibility with older code paths.
  PressurePass = Refinement
end
