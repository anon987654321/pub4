# frozen_string_literal: true

require_relative 'bridges/postpro'
require_relative 'bridges/repligen'

module MASTER
  # Bridges - Post-processing and AI generation pipeline interfaces
  # Consolidates PostproBridge and RepligenBridge
  module Bridges
    PLUGINS = {
      replicate: :ReplicateBridge,
      repligen: :RepligenBridge,
      postpro: :PostproBridge
    }.freeze

    module_function

    def validate_plugins
      PLUGINS.filter_map do |name, const_name|
        next if MASTER.const_defined?(const_name, false)
        name.to_s
      end
    end
  end

  # ===================================================================
  # BACKWARD COMPATIBILITY ALIASES
  # ===================================================================

  PostproBridge = Bridges::PostproBridge
  ReplicateBridge = Bridges::ReplicateBridge
  RepligenBridge = Bridges::RepligenBridge
end
