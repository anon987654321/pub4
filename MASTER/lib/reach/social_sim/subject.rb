# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      module Subject
        PATH = Master.data_path("social_sim", "subjects.yml").freeze

        class Error < StandardError; end

        module_function

        def load(name)
          raw = File.file?(PATH) ? (Master.load_yaml(PATH) || {}) : {}
          row = raw.dig("subjects", name.to_s)
          raise Error, "unknown subject #{name}" unless row

          {
            id: name.to_s,
            display_name: row.fetch("display_name", name.to_s),
            bio: row["bio"].to_s,
            ghost_after_messages: row.fetch("ghost_after_messages", 0).to_i,
            auto_mode: row.fetch("auto_mode", "manual").to_s,
            avatar_prompt: row["avatar_prompt"].to_s,
          }
        end
      end
    end
  end
end
