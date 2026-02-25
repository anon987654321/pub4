# frozen_string_literal: true

module MASTER
  # Capability levels — explicit escalation required for destructive operations.
  #
  # Level 0: read-only  (safe inspection, no side effects)
  # Level 1: propose    (generate patches/plans, write nothing)  ← default
  # Level 2: write      (--apply: write files, update configs)
  # Level 3: execute    (run shell commands, run tests)
  # Level 4: deploy     (network ops, service restarts, production changes)
  #
  # Usage:
  #   Capabilities.level           # => 1
  #   Capabilities.require!(:write)        # raises unless level >= 2
  #   Capabilities.allowed?(:execute)      # => false at default
  #
  # Escalation via ENV or CLI flags (set before Runtime.call):
  #   ENV["MASTER_CAP"] = "3"
  #   Capabilities.level = 3
  #   bin/master --apply      # sets level 2
  #   bin/master --exec       # sets level 3
  #   bin/master deploy       # sets level 4 with explicit confirmation
  module Capabilities
    LEVELS = {
      read_only: 0,
      propose:   1,
      write:     2,
      execute:   3,
      deploy:    4,
    }.freeze

    LEVEL_NAMES = LEVELS.invert.freeze

    class InsufficientCapabilityError < StandardError; end

    @level = nil
    @mutex = Mutex.new

    class << self
      def level
        @mutex.synchronize do
          @level ||= begin
            env = ENV["MASTER_CAP"].to_i
            env.positive? ? env.clamp(0, 4) : LEVELS[:propose]
          end
        end
      end

      def level=(val)
        @mutex.synchronize { @level = val.to_i.clamp(0, 4) }
      end

      def allowed?(capability)
        required = LEVELS.fetch(capability.to_sym, 999)
        level >= required
      end

      # Raises InsufficientCapabilityError unless current level covers capability.
      def require!(capability, context: nil)
        return if allowed?(capability)

        required = LEVELS.fetch(capability.to_sym, 999)
        msg = "Capability '#{capability}' requires level #{required} (#{LEVEL_NAMES[required]}); " \
              "current level #{level} (#{LEVEL_NAMES[level] || 'unknown'})."
        msg += " Context: #{context}" if context
        msg += " Use --apply, --exec, or set MASTER_CAP=#{required}."
        raise InsufficientCapabilityError, msg
      end

      def name
        LEVEL_NAMES[level] || "unknown(#{level})"
      end

      # Elevate for the duration of a block, then restore.
      def with_level(new_level)
        old = level
        self.level = new_level
        yield
      ensure
        self.level = old
      end
    end
  end
end
