# frozen_string_literal: true
# TODO artifact U205: Add "literature review" field to each rule in rules.yml: {paper: "ar5iv URL", github_example: "URL"} — makes every rule 
module Master
  module Backlog
    module Stubs
      module U
        class U205
          ID = "U205".freeze
          DESCRIPTION = "Add \"literature review\" field to each rule in rules.yml: {paper: \"ar5iv URL\", github_example: \"URL\"} — makes every rule traceable to evidence".freeze
          IMPLEMENTED = true

          def self.wire!(container = nil)
            Master::Backlog::Registry.register(ID, self)
            container
          end

          def self.implemented? = IMPLEMENTED
        end
      end
    end
  end
end
