# frozen_string_literal: true

module Master::Core
  class Memory
  # The three channels Memory holds, as Memory::Types so the autoloader finds
  # them at memory/types.rb.
  module Types
  # EpisodicMemory — the chronological record of this specific session.
  # Linked directly to the Episode Ledger.
  class Episodic
    attr_reader :episode
    def initialize(episode)
      @episode = episode
    end

    def transcript
      @episode.events.map(&:to_s)
    end
  end

  # SemanticMemory — the distilled knowledge and invariants.
  # Stores a "World Model" that evolves as the agent learns.
  class Semantic
    attr_reader :knowledge_base
    def initialize
      @knowledge_base = {}
    end

    def learn(key, value)
      @knowledge_base[key] = value
    end

    def query(key)
      @knowledge_base[key]
    end
  end

  # ProceduralMemory — the "how-to" for specific domains.
  # Stores validated patterns, tool sequences, and recovery recipes.
  class Procedural
    attr_reader :recipes
    def initialize
      @recipes = {}
    end

    def register_recipe(name, steps)
      @recipes[name] = steps
    end

    def find_recipe(name)
      @recipes[name]
    end
  end
end
end
end
