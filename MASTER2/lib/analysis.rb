# frozen_string_literal: true

require 'yaml'

require_relative 'analysis/prescan'
require_relative 'analysis/introspection'

module MASTER
  # Analysis - Situational awareness and introspection
  # Consolidates Prescan and Introspection modules
  module Analysis
  end

  # ═══════════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY ALIASES
  # ═══════════════════════════════════════════════════════════════════

  Prescan = Analysis::Prescan
  Introspection = Analysis::Introspection
  SelfMap = Analysis::Introspection
  SelfCritique = Analysis::Introspection
  SelfRepair = Analysis::Introspection
  SelfTest = Analysis::Introspection
end
