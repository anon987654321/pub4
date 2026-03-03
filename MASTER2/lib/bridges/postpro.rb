# frozen_string_literal: true

module Bridges
  class Postpro
    DEFAULT_BATCH_SIZE = 500
    DEFAULT_PRESET = :standard

    def initialize(relation:, preset: nil, options: {})
      @relation = relation
      @preset = (preset || DEFAULT_PRESET).to_sym
      @options = options
    end

    def call
      scope = build_scope
      apply_preset(scope, preset: @preset, options: @options)
    end

    def apply_preset(scope, preset:, options:)
      opts = preset_options(preset, options)

      ensure_replicate! if opts.fetch(:use_replicate, false)

      if opts.fetch(:use_replicate, false)
        run_replicate(scope, opts)
      else
        scope.in_batches(of: opts.fetch(:batch_size, DEFAULT_BATCH_SIZE)) do |batch|
          batch.update_all(opts.fetch(:updates, {}))
        end
      end

      scope
    end

    private

    def build_scope
      includes_assocs = Array(@options.fetch(:includes, []))
      rel = includes_assocs.empty? ? @relation : @relation.includes(*includes_assocs)

      rel = rel.where(@options.fetch(:where, {}))
      rel = rel.references(*Array(@options.fetch(:references, []))) if @options.key?(:references)
      rel
    end

    def run_replicate(scope, opts)
      ensure_replicate!
      Replicate.apply(scope, updates: opts.fetch(:updates, {}), batch_size: opts.fetch(:batch_size, DEFAULT_BATCH_SIZE))
    rescue Replicate::Error => e
      raise e
    end

    def ensure_replicate!
      raise NameError, "Replicate is not available" unless defined?(Replicate)
    end

    def quote_columns(columns)
      Array(columns).map { |c| %("#{c}") }.join(", ")
    end

    def preset_options(preset, options)
      base = case preset
             when :standard
               { updates: {}, use_replicate: false, batch_size: DEFAULT_BATCH_SIZE }
             when :replicate
               { updates: {}, use_replicate: true, batch_size: DEFAULT_BATCH_SIZE }
             else
               raise ArgumentError, "Unknown preset: #{preset.inspect}"
             end

      base.merge(options)
    end
  end
end