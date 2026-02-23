# frozen_string_literal: true

module MASTER
  module Boot
    # Boot mode profiles -- load only what each entrypoint needs.
    # Prevents MCP/tools-only boots from pulling in Falcon, Chamber, Speech, etc.
    #
    # Usage:
    #   Boot::Modes.load(:mcp)   # in bin/mcp_server
    #   Boot::Modes.load(:full)  # in bin/master (default)
    #   Boot::Modes.load(:tools) # in test helpers or lightweight scripts
    module Modes
      # Files relative to lib/ directory. Order matters -- dependencies first.
      PROFILES = {
        # Minimal: just enough to call ToolDispatch methods
        tools: %w[
          result
          logging
          utils
          executor/tools
          llm/tools
        ],

        # MCP server: tools + MCP wrapper + LLM for ask_llm tool
        mcp: %w[
          result
          logging
          utils
          executor/tools
          llm
          llm/tools
          mcp_server
        ],

        # Full interactive session: everything
        full: %w[master],
      }.freeze

      def self.load(mode = :full)
        lib_root = File.expand_path("..", __dir__) # lib/
        files = PROFILES.fetch(mode.to_sym) do
          warn "Boot::Modes: unknown mode #{mode.inspect}, falling back to :full"
          PROFILES[:full]
        end
        files.each { |f| require File.join(lib_root, f) }
      end

      def self.valid?(mode)
        PROFILES.key?(mode.to_sym)
      end

      def self.profile_names
        PROFILES.keys
      end
    end
  end
end
