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
          return @receiver.public_send(@method_name, *@args, **@kwargs) if e.message.include?("unknown keyword: :ctx")
          raise unless keyword_dependency_error?(e)

          @receiver.public_send(@method_name, **dependency_kwargs(ctx))
        end

        private

        def keyword_dependency_error?(error)
          error.message.include?("wrong number of arguments") ||
            error.message.include?("missing keywords")
        end

        def dependency_kwargs(ctx)
          keys = @receiver.method(@method_name).parameters.filter_map do |type, name|
            name if %i[key keyreq].include?(type) && name != :ctx
          end
          mapped = keys.zip(@args).to_h.compact.merge(@kwargs)
          accepts_ctx = @receiver.method(@method_name).parameters.any? { |type, name| %i[key keyreq].include?(type) && name == :ctx }
          accepts_ctx ? mapped.merge(ctx:) : mapped
        end
      end
    end
  end
end
