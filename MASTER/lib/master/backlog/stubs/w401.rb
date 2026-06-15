# frozen_string_literal: true
# TODO artifact W401: Codify relayd-first rule: any generated config that references nginx must be flagged as ERROR by MASTER's own linter — a
module Master
  module Backlog
    module Stubs
      module W
        class W401
          ID = "W401".freeze
          DESCRIPTION = "Codify relayd-first rule: any generated config that references nginx must be flagged as ERROR by MASTER's own linter — add as lexical rule NGINX_BANNED in web_rules.rb with applies_to: %i[conf yaml sh]".freeze
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
