# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      module Personas
        PATH = Master.data_path("social_sim", "personas.yml").freeze

        class Error < StandardError; end

        module_function

        def load
          return @cache if defined?(@cache) && @cache

          raw = File.file?(PATH) ? (Master.load_yaml(PATH) || {}) : {}
          @cache = Array(raw["personas"]).map { |row| normalize(row) }
        end

        def find(id)
          load.find { |persona| persona[:id] == id.to_s }
        end

        def sample(count:, seed: nil)
          pool = load.shuffle(random: seeded_random(seed))
          pool.first([count.to_i, pool.size].min)
        end

        def normalize(row)
          {
            id: row["id"].to_s,
            handle: row["handle"].to_s,
            archetype: row["archetype"].to_s,
            respect_boundaries: row.fetch("respect_boundaries", 0.5).to_f,
            patience_hours: row.fetch("patience_hours", 48).to_i,
            message_rate: row.fetch("message_rate", 0.4).to_f,
            opener_pool: Array(row["opener_pool"]),
            followup_pool: Array(row["followup_pool"]),
          }
        end

        def seeded_random(seed)
          return Random if seed.nil?

          Random.new(seed.to_i)
        end
      end
    end
  end
end
