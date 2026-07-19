# frozen_string_literal: true

module Master
  module CLI
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
          parameters = @receiver.method(@method_name).parameters
          keys = parameters.filter_map { |type, name| name if %i[key keyreq].include?(type) && name != :ctx }
          # A dependency can legitimately *be* nil (e.g. council_stage in lean
          # boot) -- compacting those away alongside genuinely-absent optional
          # args used to drop required keywords too, turning a working nil
          # dependency into a "missing keyword" crash. Only optional (:key)
          # params may fall back to their own default when nil; required
          # (:keyreq) params must always be passed through, nil or not.
          required = parameters.filter_map { |type, name| name if type == :keyreq }
          mapped = keys.zip(@args).each_with_object({}) do |(name, value), acc|
            next if value.nil? && !required.include?(name)

            acc[name] = value
          end.merge(@kwargs)
          accepts_ctx = parameters.any? { |type, name| %i[key keyreq].include?(type) && name == :ctx }
          accepts_ctx ? mapped.merge(ctx:) : mapped
        end
      end
    end
  end
end
