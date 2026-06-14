# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      class Command
        def initialize(&handler)
          @handler = handler
        end

        def call(ctx)
          @handler.call(ctx)
        end
      end
    end
  end
end
