# frozen_string_literal: true

module MASTER
  # Layout: Clean, Grok-inspired terminal output
  # Minimal chrome, maximum content, breathing room
  module Layout
    extend self

    # Colors (4-bit for max compatibility)
    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    DIM    = "\e[2m"
    GREY   = "\e[90m"
    WHITE  = "\e[97m"
    CYAN   = "\e[36m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
    RED    = "\e[31m"

    # Response: clean, minimal, breathing room
    def response(text, tokens: nil, ms: nil, cached: false)
      out = []
      out << ""  # breathing room before response
      out << render_content(text)
      out << ""  # breathing room after
      out << stats_line(tokens: tokens, ms: ms, cached: cached) if tokens
      out.join("\n")
    end

    # Render markdown to clean ANSI
    def render_content(text)
      lines = text.lines.map { |l| render_line(l.chomp) }

      # Collapse triple+ blank lines
      collapsed = []
      blank_count = 0
      lines.each do |line|
        if line.strip.empty?
          blank_count += 1
          collapsed << '' if blank_count <= 2
        else
          blank_count = 0
          collapsed << line
        end
      end

      collapsed.join("\n")
    end

    def render_line(line)
      # Code block markers: hide them, content styled elsewhere
      return '' if line.match?(/^```/)

      # Headers: bold, no #
      if line.match?(/^#+\s/)
        return "#{BOLD}#{line.gsub(/^#+\s*/, '')}#{RESET}"
      end

      # Bullets: subtle dot
      if line.match?(/^\s*[-*]\s/)
        return line.gsub(/^(\s*)[-*]\s/, "\\1#{DIM}·#{RESET} ")
      end

      # Numbered: keep clean
      if line.match?(/^\s*\d+\.\s/)
        return line.gsub(/^(\s*)(\d+)\.\s/, "\\1#{DIM}\\2.#{RESET} ")
      end

      # Inline formatting
      line = line.gsub(/\*\*(.+?)\*\*/, "#{BOLD}\\1#{RESET}")      # bold
      line = line.gsub(/\*([^*]+)\*/, "#{DIM}\\1#{RESET}")         # italic as dim
      line = line.gsub(/`([^`]+)`/, "#{CYAN}\\1#{RESET}")          # inline code
      line = line.gsub(/\[([^\]]+)\]\([^)]+\)/, "#{CYAN}\\1#{RESET}")  # links

      line
    end

    # Stats: single subtle line
    def stats_line(tokens: nil, ms: nil, cached: false)
      parts = []
      parts << "#{ms}ms" if ms
      parts << "#{tokens[:input]}→#{tokens[:output]}" if tokens
      parts << "cached" if cached
      "#{DIM}#{parts.join(' · ')}#{RESET}"
    end

    # Shell output: code-style, indented
    def shell_output(text, cmd: nil)
      out = []
      out << "#{DIM}$ #{cmd}#{RESET}" if cmd
      text.lines.each { |l| out << "  #{l.chomp}" }
      out.join("\n")
    end

    # Error: red, clear
    def error(msg)
      "#{RED}#{msg}#{RESET}"
    end

    # Success: green, brief
    def success(msg)
      "#{GREEN}#{msg}#{RESET}"
    end

    # Info: dim, unobtrusive
    def info(msg)
      "#{DIM}#{msg}#{RESET}"
    end

    # Separator: subtle line
    def separator
      "#{DIM}#{'─' * 40}#{RESET}"
    end

    # Prompt: minimal, shows only essential state
    def prompt(dir:, persona: nil, cost: 0, turn: 0)
      parts = [dir]
      parts << ":#{persona}" if persona && persona != 'generic'
      parts << "(#{turn})" if turn > 0
      parts << cost_badge(cost) if cost > 0.01
      "#{parts.join} #{CYAN}❯#{RESET} "
    end

    def cost_badge(cost)
      color = cost < 0.10 ? GREEN : cost < 1.0 ? YELLOW : RED
      "#{color}$#{'%.2f' % cost}#{RESET}"
    end

    # Code block: dimmed background effect
    def code_block(code, lang: nil)
      lines = code.lines.map { |l| "  #{DIM}#{l.chomp}#{RESET}" }
      lines.unshift("#{DIM}#{lang}#{RESET}") if lang
      lines.join("\n")
    end

    # Trace: bold green dmesg-style (already in Dmesg)

    # Box: minimal, for important messages
    def box(title, content)
      width = [title.length, content.lines.map(&:length).max || 0].max + 4
      top = "#{DIM}┌#{'─' * (width - 2)}┐#{RESET}"
      bot = "#{DIM}└#{'─' * (width - 2)}┘#{RESET}"
      mid = content.lines.map { |l| "#{DIM}│#{RESET} #{l.chomp.ljust(width - 4)} #{DIM}│#{RESET}" }

      [top, "#{DIM}│#{RESET} #{BOLD}#{title.ljust(width - 4)}#{RESET} #{DIM}│#{RESET}", *mid, bot].join("\n")
    end
  end
end
