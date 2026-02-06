# frozen_string_literal: true

module MASTER
  # Pure Ruby TTY toolkit for terminal UI
  # No dependencies on external gems like tty-*
  module TTY
    CLEAR_LINE = "\e[2K\r"
    HIDE_CURSOR = "\e[?25l"
    SHOW_CURSOR = "\e[?25h"
    MOVE_UP = "\e[1A"
    
    # Spinners
    SPINNERS = {
      dots: %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏],
      line: %w[- \\ | /],
      arrow: %w[← ↖ ↑ ↗ → ↘ ↓ ↙],
      box: %w[◰ ◳ ◲ ◱],
      bounce: %w[⠁ ⠂ ⠄ ⠂],
      arc: %w[◜ ◠ ◝ ◞ ◡ ◟]
    }.freeze
    
    # Get terminal size
    def self.size
      if ENV['COLUMNS'] && ENV['LINES']
        return [ENV['LINES'].to_i, ENV['COLUMNS'].to_i]
      end
      
      # Try stty
      size_str = `stty size 2>/dev/null`.strip
      if !size_str.empty?
        rows, cols = size_str.split.map(&:to_i)
        return [rows, cols] if rows > 0 && cols > 0
      end
      
      # Try tput
      rows = `tput lines 2>/dev/null`.strip.to_i
      cols = `tput cols 2>/dev/null`.strip.to_i
      return [rows, cols] if rows > 0 && cols > 0
      
      # Fallback
      [24, 80]
    rescue
      [24, 80]
    end
    
    def self.width
      size[1]
    end
    
    def self.height
      size[0]
    end
    
    # Progress bar
    class ProgressBar
      attr_reader :total, :current
      
      def initialize(total:, width: 40, format: ':bar :percent :current/:total')
        @total = total
        @current = 0
        @width = width
        @format = format
        @started_at = Time.now
      end
      
      def advance(step = 1)
        @current = [@current + step, @total].min
        render
      end
      
      def finish
        @current = @total
        render
        puts
      end
      
      def render
        percent = (@current.to_f / @total * 100).round
        filled = (@current.to_f / @total * @width).round
        bar = '█' * filled + '░' * (@width - filled)
        
        output = @format.dup
        output.gsub!(':bar', bar)
        output.gsub!(':percent', "#{percent}%")
        output.gsub!(':current', @current.to_s)
        output.gsub!(':total', @total.to_s)
        
        elapsed = Time.now - @started_at
        rate = @current > 0 ? @current.to_f / elapsed : 0
        eta = rate > 0 ? (@total - @current) / rate : 0
        output.gsub!(':eta', format_time(eta))
        output.gsub!(':elapsed', format_time(elapsed))
        
        print TTY::CLEAR_LINE + output
        $stdout.flush
      end
      
      private
      
      def format_time(seconds)
        return '0s' if seconds < 1
        return "#{seconds.round}s" if seconds < 60
        mins = (seconds / 60).floor
        secs = (seconds % 60).round
        "#{mins}m#{secs}s"
      end
    end
    
    # Spinner
    class Spinner
      def initialize(message, style: :dots)
        @message = message
        @frames = SPINNERS[style] || SPINNERS[:dots]
        @running = false
        @thread = nil
      end
      
      def start
        return if @running
        @running = true
        print TTY::HIDE_CURSOR
        
        @thread = Thread.new do
          idx = 0
          while @running
            frame = @frames[idx % @frames.length]
            print TTY::CLEAR_LINE + "#{frame} #{@message}"
            $stdout.flush
            sleep 0.1
            idx += 1
          end
        end
      end
      
      def stop(final_message = nil)
        return unless @running
        @running = false
        @thread&.join
        print TTY::CLEAR_LINE
        puts final_message || "#{@message} ✓"
        print TTY::SHOW_CURSOR
      end
      
      def self.spin(message, style: :dots)
        spinner = new(message, style: style)
        spinner.start
        
        result = yield if block_given?
        
        spinner.stop
        result
      rescue => e
        spinner.stop("#{message} ✗")
        raise e
      end
    end
    
    # Simple status line
    class Status
      def initialize(message)
        @message = message
      end
      
      def update(new_message)
        @message = new_message
        print TTY::CLEAR_LINE + @message
        $stdout.flush
      end
      
      def clear
        print TTY::CLEAR_LINE
        $stdout.flush
      end
      
      def done(final_message = nil)
        clear
        puts final_message || @message
      end
    end
    
    # Box drawing
    module Box
      SINGLE = {
        top_left: '┌', top_right: '┐',
        bottom_left: '└', bottom_right: '┘',
        horizontal: '─', vertical: '│',
        cross: '┼', left_tee: '├', right_tee: '┤',
        top_tee: '┬', bottom_tee: '┴'
      }.freeze
      
      DOUBLE = {
        top_left: '╔', top_right: '╗',
        bottom_left: '╚', bottom_right: '╝',
        horizontal: '═', vertical: '║',
        cross: '╬', left_tee: '╠', right_tee: '╣',
        top_tee: '╦', bottom_tee: '╩'
      }.freeze
      
      ROUNDED = {
        top_left: '╭', top_right: '╮',
        bottom_left: '╰', bottom_right: '╯',
        horizontal: '─', vertical: '│',
        cross: '┼', left_tee: '├', right_tee: '┤',
        top_tee: '┬', bottom_tee: '┴'
      }.freeze
      
      def self.draw(text, style: :single, padding: 1)
        chars = const_get(style.to_s.upcase)
        lines = text.split("\n")
        width = lines.map(&:length).max + (padding * 2)
        
        result = []
        result << chars[:top_left] + chars[:horizontal] * width + chars[:top_right]
        
        lines.each do |line|
          padded = line.ljust(width - padding * 2)
          result << chars[:vertical] + ' ' * padding + padded + ' ' * padding + chars[:vertical]
        end
        
        result << chars[:bottom_left] + chars[:horizontal] * width + chars[:bottom_right]
        result.join("\n")
      end
    end
    
    # Table rendering
    class Table
      def initialize(headers)
        @headers = headers
        @rows = []
      end
      
      def add_row(row)
        @rows << row
      end
      
      def render
        return '' if @rows.empty?
        
        # Calculate column widths
        widths = @headers.map.with_index do |header, i|
          max_content = @rows.map { |r| r[i].to_s.length }.max || 0
          [header.length, max_content].max
        end
        
        # Build table
        lines = []
        
        # Header
        header_line = @headers.map.with_index { |h, i| h.ljust(widths[i]) }.join(' │ ')
        lines << "│ #{header_line} │"
        
        # Separator
        sep = widths.map { |w| '─' * w }.join('─┼─')
        lines << "├─#{sep}─┤"
        
        # Rows
        @rows.each do |row|
          row_line = row.map.with_index { |cell, i| cell.to_s.ljust(widths[i]) }.join(' │ ')
          lines << "│ #{row_line} │"
        end
        
        # Borders
        width = lines.first.length - 2
        top = "┌─#{'─' * width}─┐"
        bottom = "└─#{'─' * width}─┘"
        
        ([top] + lines + [bottom]).join("\n")
      end
    end
    
    # Prompt for user input
    def self.ask(question, default: nil)
      prompt = default ? "#{question} [#{default}]: " : "#{question}: "
      print prompt
      answer = $stdin.gets&.strip
      answer.empty? && default ? default : answer
    end
    
    def self.confirm(question, default: false)
      suffix = default ? '[Y/n]' : '[y/N]'
      print "#{question} #{suffix}: "
      answer = $stdin.gets&.strip&.downcase
      
      return default if answer.empty?
      answer.start_with?('y')
    end
    
    # Select from list
    def self.select(question, choices)
      puts question
      choices.each_with_index do |choice, i|
        puts "  #{i + 1}. #{choice}"
      end
      
      loop do
        print 'Select (1-' + choices.length.to_s + '): '
        answer = $stdin.gets&.strip&.to_i
        return choices[answer - 1] if answer > 0 && answer <= choices.length
        puts 'Invalid selection'
      end
    end
  end
end
