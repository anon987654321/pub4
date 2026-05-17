# frozen_string_literal: true

module Master
  module Plugins
  module Ground
    def self.boot(root:, config:, homeostat:)
      memory      = Master::Ground::Memory.new(root:)
      personality = Master::Voice::Personality.new(
        config["persona"]&.to_sym || Master::Voice::Personality::DEFAULT, root:, homeostat:
      )
      learnings   = Master::Ground::KnowledgeStore.new(root:)
      { memory:, personality:, learnings: }
    end

    Master::Plugin.register(:ground, self)
  end
  end
end
