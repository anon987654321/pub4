# frozen_string_literal: true
# TODO artifact AA807: Comparable mixin for ordered types: Finding should include Comparable with `<=>` by severity then line — enables `findin
module Master
  module Backlog
    module Stubs
      module AA
        class AA807
          ID = "AA807".freeze
          DESCRIPTION = "Comparable mixin for ordered types: Finding should include Comparable with `<=>` by severity then line — enables `findings.min`, `findings.sort`, `findings.max_by`".freeze
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
