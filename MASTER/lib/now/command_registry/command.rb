# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      class Command
        def initialize(receiver = nil, method_name = nil, *args, **kwargs, &handler)
          @receiver = receiver
          @method_name = method_name
          @args = args
          @kwargs = kwargs
          @handler = handler
        end

        def call(ctx)
          return @handler.call(ctx) if @handler

          @receiver.public_send(@method_name, *@args, **@kwargs.merge(ctx: ctx))
        rescue ArgumentError => e
          raise unless e.message.include?("unknown keyword: :ctx")

          @receiver.public_send(@method_name, *@args, **@kwargs)
        end
      end
    end
  end
end
