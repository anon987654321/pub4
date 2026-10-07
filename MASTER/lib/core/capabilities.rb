# frozen_string_literal: true

module Master::Core
  # Monotonic authority for one cognitive context.
  #
  # A context starts from an explicit profile. Capabilities may be removed,
  # never acquired. Locking freezes the decision so authority cannot widen
  # halfway through a task.
  class Capabilities
    PROFILES = {
      boot: %i[stdio read execute],
      model: %i[stdio read model],
      observe: %i[stdio read],
      plan: %i[stdio read model],
      fix: %i[stdio read write create execute network],
      repair: %i[stdio read write create execute network],
      deploy: %i[stdio read write create execute network deploy],
      device: %i[stdio read device],
      world: %i[stdio read world]
    }.freeze

    def self.for(name)
      values = PROFILES.fetch(name.to_sym)
      new(name:, capabilities: values)
    end

    def self.read_only
      new(name: :read_only, capabilities: %i[stdio read])
    end

    def initialize(name:, capabilities:)
      @name = name.to_sym
      @allowed = capabilities.map(&:to_sym).uniq.freeze
      @locked = false
    end

    attr_reader :name
    def capabilities = @allowed
    def allows?(capability) = @allowed.include?(capability.to_sym)
    alias allow? allows?

    def require!(capability)
      return true if allows?(capability)
      raise SecurityError, "capability refused: #{capability}"
    end

    def drop(*capabilities)
      raise SecurityError, "capability table is locked" if @locked
      @allowed = (@allowed - capabilities.map(&:to_sym)).freeze
      self
    end

    def lock!
      @locked = true
      freeze
    end

    def locked? = @locked

    def acquire(_capability)
      raise SecurityError, "capability acquisition is forbidden; create a new trusted context"
    end

    def to_h
      { name: @name, capabilities: @allowed, locked: @locked }
    end
  end
end