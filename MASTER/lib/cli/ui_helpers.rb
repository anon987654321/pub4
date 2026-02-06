# frozen_string_literal: true

module MASTER
  class CLI
    module UIHelpers
      # Colorize output based on content
      def colorize_output(text)
        return text unless text.is_a?(String)

        if text.start_with?('Error', 'Not found', 'Usage')
          "#{C_RED}#{text}#{C_RESET}"
        elsif text.start_with?('Switched', 'Cleaned', 'Done', 'Changed', 'Cleared')
          "#{C_GREEN}#{text}#{C_RESET}"
        else
          text
        end
      end

      # Colorize cost values with tier-based colors
      def colorize_cost(cost)
        if cost < COST_TIER_LOW
          C_GREEN
        elsif cost < COST_TIER_MED
          C_YELLOW
        else
          C_RED
        end
      end

      # Colorize cost inline with formatting
      def colorize_cost_inline(cost)
        formatted = "$#{'%.2f' % cost}"
        if cost < COST_TIER_LOW
          "#{C_GREEN}#{formatted}#{C_RESET}"
        elsif cost < COST_TIER_MED
          "#{C_YELLOW}#{formatted}#{C_RESET}"
        else
          "#{C_RED}#{formatted}#{C_RESET}"
        end
      end

      # Format uptime duration
      def format_uptime(seconds)
        hours = (seconds / UPTIME_THRESHOLD).to_i
        mins = ((seconds % UPTIME_THRESHOLD) / 60).to_i
        "#{hours}h#{mins}m"
      end

      # Format general duration
      def format_duration(secs)
        if secs < 60
          "#{secs.to_i}s"
        elsif secs < 3600
          "#{(secs / 60).to_i}m #{(secs % 60).to_i}s"
        else
          "#{(secs / 3600).to_i}h #{((secs % 3600) / 60).to_i}m"
        end
      end

      # Build command prompt
      def build_prompt
        # Use starship if available
        return starship_prompt if starship_available?
        
        dir = File.basename(@root)
        persona = @llm.persona&.dig(:name)
        cost = @llm.total_cost
        hist = @llm.instance_variable_get(:@history)&.size || 0
        uptime = Time.now - @boot_time

        parts = [dir]
        parts << ":#{persona}" if persona && persona != 'default'
        parts << "(#{hist})" if hist > 0
        parts << format_uptime(uptime) if uptime > UPTIME_THRESHOLD
        parts << colorize_cost_inline(cost) if cost > 0

        "#{parts.join('')} $ "
      end
      
      def starship_available?
        @starship_available ||= system('which starship > /dev/null 2>&1')
      end
      
      def starship_prompt
        # Set MASTER-specific env vars for starship to use
        ENV['MASTER_PERSONA'] = @llm.persona&.dig(:name) || 'generic'
        ENV['MASTER_COST'] = format('%.2f', @llm.total_cost)
        ENV['MASTER_HIST'] = (@llm.instance_variable_get(:@history)&.size || 0).to_s
        
        `starship prompt 2>/dev/null`.chomp
      rescue StandardError
        build_fallback_prompt
      end
      
      def build_fallback_prompt
        "#{File.basename(@root)} $ "
      end

      # Spinner animation
      def with_spinner
        # Use TTY::Spinner if available
        if TTY_AVAILABLE
          spinner = TTY::Spinner.new("[:spinner] ", format: :dots)
          spinner.auto_spin
          result = yield
          spinner.stop
          return result
        end
        
        # Fallback to simple orb spinner
        done = false
        result = nil

        spinner = Thread.new do
          i = 0
          until done
            draw_orb(SPINNER[i % SPINNER.size])
            i += 1
            sleep 0.1
          end
          clear_orb
        end

        result = yield
        done = true
        spinner.join
        result
      end

      # Progress indicator for long operations
      def with_progress(message)
        if TTY_AVAILABLE
          spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots)
          spinner.auto_spin
          result = yield
          spinner.success
          return result
        end
        
        done = false
        spinner_thread = Thread.new do
          i = 0
          until done
            print "\r#{message} #{SPINNER[i % 4]}"
            i += 1
            sleep 0.1
          end
        end
        result = yield
        done = true
        spinner_thread.join
        puts "\r#{message} #{C_GREEN}✓#{C_RESET}"
        result
      end

      # Terminal utilities
      def terminal_cols
        IO.console&.winsize&.last || 80
      rescue StandardError
        80
      end

      def draw_orb(frame)
        print "\r#{frame} "
        $stdout.flush
      end

      def clear_orb
        print "\r  \r"
        $stdout.flush
      end

      # Output helpers - consistent formatting per typography spec
      def out_ok(msg)
        "#{C_GREEN}#{ICON_OK}#{C_RESET} #{msg}"
      end

      def out_err(msg, detail = nil)
        lines = ["#{C_RED}#{ICON_ERR}#{C_RESET} #{msg}"]
        lines << "  #{C_DIM}#{detail}#{C_RESET}" if detail
        lines.join("\n")
      end

      def out_warn(msg)
        "#{C_YELLOW}#{ICON_WARN}#{C_RESET} #{msg}"
      end

      def out_dim(msg)
        "#{C_DIM}#{msg}#{C_RESET}"
      end

      def out_row(label, value, width = 12)
        "  #{label.ljust(width)}#{C_DIM}#{value}#{C_RESET}"
      end

      # Visual separator - using whitespace instead of ASCII art
      def separator(label = nil)
        if label
          "\n#{C_BOLD}#{label}#{C_RESET}\n"
        else
          ""
        end
      end

      # TTY-Prompt interactive selection
      def tty_select(question, choices, default: nil)
        return choices.first unless TTY_AVAILABLE
        @prompt.select(question, choices, default: default, cycle: true)
      end
      
      # TTY-Prompt multi-select
      def tty_multi_select(question, choices)
        return choices unless TTY_AVAILABLE
        @prompt.multi_select(question, choices, cycle: true)
      end
      
      # TTY-Prompt yes/no
      def tty_confirm(question, default: true)
        return default unless TTY_AVAILABLE
        @prompt.yes?(question, default: default)
      end
      
      # TTY-Prompt text input
      def tty_ask(question, default: nil)
        return default unless TTY_AVAILABLE
        @prompt.ask(question, default: default)
      end
      
      # TTY-Table for structured data
      def tty_table(headers, rows)
        if TTY_AVAILABLE
          table = TTY::Table.new(headers, rows)
          table.render(:unicode, padding: [0, 1])
        else
          # Fallback to simple aligned output
          widths = headers.map.with_index { |h, i| [h.to_s.length, rows.map { |r| r[i].to_s.length }.max || 0].max }
          lines = [headers.map.with_index { |h, i| h.to_s.ljust(widths[i]) }.join('  ')]
          rows.each { |row| lines << row.map.with_index { |c, i| c.to_s.ljust(widths[i]) }.join('  ') }
          lines.join("\n")
        end
      end
      
      # TTY-Box for highlighted content
      def tty_box(content, title: nil)
        if TTY_AVAILABLE
          TTY::Box.frame(content, title: title, padding: 1, border: :round)
        else
          title_line = title ? "#{C_BOLD}#{title}#{C_RESET}\n\n" : ""
          "#{title_line}#{content}"
        end
      end
      
      # Pastel colorization (richer than ANSI)
      def colorize(text, *styles)
        return text unless TTY_AVAILABLE && @pastel
        @pastel.decorate(text, *styles)
      end
    end
  end
end
