# frozen_string_literal: true
# TODO artifact AJ105: Tax categorization: flag transactions by Norwegian tax category (fradragsberettiget, privat, næring) for å-meldingen
module Master
  module Backlog
    module Stubs
      module AJ
        class AJ105
          ID = "AJ105".freeze
          DESCRIPTION = "Tax categorization: flag transactions by Norwegian tax category (fradragsberettiget, privat, næring) for å-meldingen".freeze
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
