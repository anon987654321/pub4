# frozen_string_literal: true

module MASTER
  # Simple prompt generator (starship-like but native)
  class Prompt
    def initialize(cli)
      @cli = cli
    end

    def generate
      user = ENV['USER'] || 'dev'
      model = current_model
      dir = short_dir
      cost = format_cost
      hist = history_count

      # Format: user@model:dir(hist)$cost $
      parts = ["#{user}@#{model}:#{dir}"]
      parts << "(#{hist})" if hist > 0
      parts << cost if @cli.llm.total_cost > 0
      "#{parts.join('')} $ "
    end

    private

    def current_model
      tier = @cli.llm.instance_variable_get(:@current_tier) || :strong
      case tier
      when :strong then 'sonnet-4.5'
      when :cheap then 'deepseek'
      when :fast then 'grok-4'
      when :code then 'grok-code'
      when :reasoning then 'r1'
      when :gemini then 'gemini-3'
      else tier.to_s
      end
    end

    def short_dir
      dir = Dir.pwd
      home = ENV['HOME'] || ''
      dir.sub(home, '~').split('/').last(2).join('/')
    end

    def format_cost
      cost = @cli.llm.total_cost
      return '' if cost <= 0
      "$#{'%.2f' % cost}"
    end

    def history_count
      @cli.llm.instance_variable_get(:@history)&.size || 0
    end
  end
end
