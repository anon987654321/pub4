# frozen_string_literal: true

module Master
  module Now
    class PipelineContext
      # Class-level construction/validation helpers — separate from
      # PipelineContext's own instance-level accessor/merge API.
      module FactoryMethods
        def build(user_message:, **opts)
          new({ user_message:, on_chunk: opts[:on_chunk] }.merge(opts))
        end

        def validate!(ctx)
          hash = ctx.is_a?(PipelineContext) ? ctx.to_h : ctx
          missing = REQUIRED.reject { |k| hash.key?(k) }
          raise ArgumentError, "PipelineContext missing required keys: #{missing.join(', ')}" unless missing.empty?
        end

        def assert_stage!(ctx, stage)
          hash = ctx.is_a?(PipelineContext) ? ctx.to_h : ctx
          prereqs = STAGE_PREREQUISITES.fetch(stage, [])
          missing = prereqs.reject { |k| hash.key?(k) }
          raise ArgumentError, "#{stage} stage missing prerequisites: #{missing.join(', ')}" unless missing.empty?
          KEY_TYPES.each do |key, allowed|
            next unless hash.key?(key)
            value = hash[key]
            next if allowed.any? { |t| value.is_a?(t) }
            raise TypeError, "ctx[#{key.inspect}] expected #{allowed.map(&:name).join('|')}, got #{value.class}"
          end
        end

        def fetch!(ctx, key)
          value = ctx[key]
          raise KeyError, "PipelineContext: missing key #{key.inspect}" unless ctx.key?(key)
          value
        end

        # Wrap a plain Hash into a PipelineContext. Skips wrapping if already typed.
        def wrap(hash)
          return hash if hash.is_a?(PipelineContext)
          new(hash)
        end
      end
    end
  end
end
