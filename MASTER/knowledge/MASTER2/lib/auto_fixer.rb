# frozen_string_literal: true

module MASTER
  # AutoFixer - safe wrapper around optional external auto-fix engines.
  # If no external AutoFixer is installed, this class provides a predictable
  # fallback API so commands/tests can still run in read/analyze environments.
  class AutoFixer
    attr_reader :mode

    def initialize(mode: :moderate)
      @mode = mode
      @history = []
    end

    def fix(path = nil, issue: nil, **opts)
      if external_fixer_available?
        external_fixer.new(mode: mode).fix(path, issue: issue, **opts)
      else
        @history << { at: Time.now.utc.iso8601, path: path, issue: issue, mode: mode, opts: opts }
        Result.ok(fixed: false, reason: "No external AutoFixer installed", mode: mode, path: path)
      end
    rescue StandardError => e
      Result.err("AutoFixer failed: #{e.message}")
    end

    def rollback(*args, **kwargs)
      if external_fixer_available? && external_fixer.instance_methods.include?(:rollback)
        external_fixer.new(mode: mode).rollback(*args, **kwargs)
      else
        last = @history.pop
        Result.ok(rolled_back: !last.nil?, mode: mode, last: last)
      end
    rescue StandardError => e
      Result.err("AutoFixer rollback failed: #{e.message}")
    end

    private

    def external_fixer_available?
      external_fixer && external_fixer != self.class
    end

    def external_fixer
      @external_fixer ||= begin
        klass = Object.const_get(:AutoFixer) if Object.const_defined?(:AutoFixer)
        klass if klass.is_a?(Class)
      rescue StandardError
        nil
      end
    end
  end
end
