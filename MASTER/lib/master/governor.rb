# frozen_string_literal: true

require "tty-prompt"

module Master
  class Governor
    TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

    def initialize(config:, event_bus: nil)
      @config  = config
      @bus     = event_bus
      @prompt  = $stdout.isatty ? TTY::Prompt.new : nil
      @auto    = config.auto?
      @approve_all = false
    end

    def check_permit(tool_name, tier, description = nil)
      @bus&.publish("tool:before", tool: tool_name, tier:)

      case tier
      when :safe    then return Result.ok(true)
      when :guarded then return Result.ok(true) if @auto || @approve_all
      when :dangerous then return Result.ok(true) if @auto || @approve_all
      end

      ask_user(tool_name, tier, description)
    rescue => e
      Result.err(e.message, category: :validation)
    end

    def approve_all!    = @approve_all = true
    def reset_approve!  = @approve_all = false

    private

    def ask_user(tool_name, tier, description)
      return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt
      
      label = description ? "#{tool_name}: #{description}" : tool_name
      choice = @prompt.select("#{tier_icon(tier)} #{label}", [
        { name: "approve",     value: :approve },
        { name: "deny",        value: :deny },
        { name: "quit",        value: :quit }
      ])

      case choice
      when :approve     then Result.ok(true)
      when :deny        then @bus&.publish("tool:denied", tool: tool_name) ; Result.err("denied by user", category: :validation)
      when :quit        then exit(0)
      end
    end

    def tier_icon(tier)
      case tier
      when :safe      then "i"
      when :guarded   then "!"
      when :dangerous then "!!"
      end
    end
  end
end