# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      class Command
        # Matches OpenCrabs' skill-level `review_gate: true`: a command
        # opts in to requiring an explicit, deliberate confirmation before
        # its side effects run, even under otherwise-autonomous operation.
        # /commit is the consumer: it commits the named paths under a
        # model-written message, so a person confirms before git runs.
        CONFIRM_FLAG = "--confirm"

        # The dispatcher a built verb reaches, so a test can prove it exists
        # without calling it.
        attr_reader :method_name

        def initialize(receiver = nil, method_name = nil, *args, review_gate: false, **kwargs, &handler)
          @receiver = receiver
          @method_name = method_name
          @args = args
          @kwargs = kwargs
          @handler = handler
          @review_gate = review_gate
        end

        def call(ctx)
          return review_gate_notice if @review_gate && !confirmed?(ctx)

          ctx = strip_confirm_flag(ctx) if @review_gate
          return @handler.call(ctx) if @handler

          method = @receiver.method(@method_name)
          return method.call(*@args, **invoke_keywords(ctx, method.parameters)) if positional_parameters?(method.parameters)

          method.call(**dependency_kwargs(ctx))
        end

        private

        def confirmed?(ctx)
          ctx.to_h.fetch(:args, "").to_s.strip.split(/\s+/).include?(CONFIRM_FLAG)
        end

        def strip_confirm_flag(ctx)
          hash = ctx.to_h
          cleaned = hash.fetch(:args, "").to_s.strip.split(/\s+/).reject { |tok| tok == CONFIRM_FLAG }.join(" ")
          hash.merge(args: cleaned)
        end

        def review_gate_notice
          "review_gate: this command has side effects and needs explicit confirmation — " \
            "re-run with #{CONFIRM_FLAG} to proceed"
        end

        def positional_parameters?(parameters)
          parameters.any? { |type, _name| %i[req opt rest].include?(type) }
        end

        def invoke_keywords(ctx, parameters)
          keywords = @kwargs.dup
          accepts_ctx = parameters.any? do |type, name|
            type == :keyrest || (%i[key keyreq].include?(type) && name == :ctx)
          end
          accepts_ctx ? keywords.merge(ctx:) : keywords
        end

        def dependency_kwargs(ctx)
          parameters = @receiver.method(@method_name).parameters
          keys = parameters.filter_map { |type, name| name if %i[key keyreq].include?(type) && name != :ctx }
          # A dependency can legitimately *be* nil, so only optional (:key)
          # params may fall back to their own default when one is. Required
          # (:keyreq) params are passed through nil and all: compacting them
          # away turns a working nil dependency into a missing-keyword crash.
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
