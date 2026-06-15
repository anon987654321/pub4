# frozen_string_literal: true
# TODO artifact AK404: Reward model integration: train a small reward model on {fix, scan_result_after} pairs to predict fix quality without ru
module Master
  module Backlog
    module Stubs
      module AK
        class AK404
          ID = "AK404".freeze
          DESCRIPTION = "Reward model integration: train a small reward model on {fix, scan_result_after} pairs to predict fix quality without running the scan".freeze
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
