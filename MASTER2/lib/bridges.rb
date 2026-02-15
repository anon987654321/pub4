# frozen_string_literal: true

require_relative 'bridges/postpro'
require_relative 'bridges/repligen'

module MASTER
  # Bridges - Post-processing and AI generation pipeline interfaces
  # Consolidates PostproBridge and RepligenBridge
  module Bridges
  end

  # ═══════════════════════════════════════════════════════════════════
  # BACKWARD COMPATIBILITY ALIASES
  # ═══════════════════════════════════════════════════════════════════

  PostproBridge = Bridges::PostproBridge
  RepligenBridge = Bridges::RepligenBridge
end
