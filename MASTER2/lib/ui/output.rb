# frozen_string_literal: true

module MASTER
  module UI
    module_function

    def dmesg(subsystem, message, level: :info)
      elapsed = (Time.now - MASTER_BOOT_TIME).round(6)
      prefix = format("[%12.6f]", elapsed)
      line = "#{prefix} #{subsystem}: #{message}"
      case level
      when :error, :warn then warn line
      else puts line
      end
    end

    def render_response(text)
      markdown(text)
    rescue StandardError => e
      Logging.warn("markdown render failed: #{e.message}", subsystem: "Output") if defined?(Logging)
      text
    end

    def token_chart(prompt_tokens:, completion_tokens:, cached: 0)
      total = prompt_tokens + completion_tokens
      token_segments = [
        { name: "prompt",     value: prompt_tokens,     color: :blue },
        { name: "completion", value: completion_tokens,  color: :white },
      ]
      token_segments << { name: "cached", value: cached, color: :bright_black } if cached > 0

      puts pie(token_segments).render
      puts dim("Total: #{total} tokens")
    end

    def show_tree(path, depth: 3)
      require "tty-tree"
      tree_obj = TTY::Tree.new(path, level: depth)
      puts tree_obj.render
    rescue LoadError
      # Simple fallback
      Dir.glob(File.join(path, "*")).each do |f|
        puts "  #{File.basename(f)}"
      end
    end
  end
end
