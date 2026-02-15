# frozen_string_literal: true

module MASTER
  module UI
    extend self

    # --- Colorization for dmesg and system output ---

    def dmesg(subsystem, message, level: :info)
      elapsed = (Time.now - MASTER_BOOT_TIME).round(6)
      prefix = format("[%12.6f]", elapsed)
      line = "#{prefix} #{subsystem}: #{message}"
      case level
      when :error, :warn then $stderr.puts line
      else puts line
      end
    end

    # --- Special rendering methods ---

    def render_response(text)
      # Try markdown rendering, fallback to plain
      markdown(text)
    rescue StandardError => e
      text
    end

    def token_chart(prompt_tokens:, completion_tokens:, cached: 0)
      total = prompt_tokens + completion_tokens
      data = [
        { name: 'prompt', value: prompt_tokens, color: :blue },
        { name: 'completion', value: completion_tokens, color: :green }
      ]
      data << { name: 'cached', value: cached, color: :cyan } if cached > 0

      puts pie(data).render
      puts dim("Total: #{total} tokens")
    end

    def show_tree(path, depth: 3)
      require 'tty-tree'
      tree_obj = TTY::Tree.new(path, level: depth)
      puts tree_obj.render
    rescue LoadError
      # Simple fallback
      Dir.glob(File.join(path, '*')).each do |f|
        puts "  #{File.basename(f)}"
      end
    end
  end
end
