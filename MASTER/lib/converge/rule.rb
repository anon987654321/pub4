# frozen_string_literal: true

module Converge
  class Rule
    attr_reader :id, :type, :depends_on, :apply_block, :config

    def initialize(entry)
      @id = entry.fetch("id").to_s
      @type = (entry["type"] || entry["tier"] || "scan").to_s
      @depends_on = Array(entry["depends_on"]).map(&:to_s)
      @apply_block = entry["apply"]
      @config = entry.fetch("config", {})
      @raw = entry
    end

    def apply(context)
      return context unless apply_block

      instance_exec(context, &proc_block)
    end

    private

    def proc_block
      @proc_block ||= TOPLEVEL_BINDING.eval("proc { |ctx| #{apply_block}\n}")
    end
  end
end
