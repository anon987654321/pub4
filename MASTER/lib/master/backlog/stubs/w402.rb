# frozen_string_literal: true
# TODO artifact W402: Codify httpd-for-acme-only: if httpd.conf has any server block other than /.well-known/acme-challenge/, flag as violatio
module Master
  module Backlog
    module Stubs
      module W
        class W402
          ID = "W402".freeze
          DESCRIPTION = "Codify httpd-for-acme-only: if httpd.conf has any server block other than /.well-known/acme-challenge/, flag as violation".freeze
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
