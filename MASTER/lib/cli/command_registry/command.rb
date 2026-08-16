# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      class Command
        # Matches OpenCrabs' skill-level `review_gate: true`: a command
        # opts in to requiring an explicit, deliberate confirmation before
        # its side effects run, even under otherwise-autonomous operation.
        # /commit is the first consumer -- it currently runs `git add -u`
        # + `git commit` with an LLM-written message and zero confirmation.
        CONFIRM_FLAG = "--confirm"

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

          @receiver.public_send(@method_name, *@args, **@kwargs.merge(ctx:))
        rescue ArgumentError => e
          return @receiver.public_send(@method_name, *@args, **@kwargs) if e.message.include?("unknown keyword: :ctx")
          raise unless keyword_dependency_error?(e)

          @receiver.public_send(@method_name, **dependency_kwargs(ctx))
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

        def keyword_dependency_error?(error)
          error.message.include?("wrong number of arguments") ||
            error.message.include?("missing keywords")
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
