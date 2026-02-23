# frozen_string_literal: true

module MASTER
  module UI
    # Components - TTY component lazy loaders
    module Components
      def prompt
        @prompt ||= begin
          require "tty-prompt"
          TTY::Prompt.new(symbols: { marker: ">" }, active_color: :cyan)
        rescue LoadError
          nil
        end
      end

      def spinner(message = nil, style: :line)
        MASTER::UI::SubtleSpinner.new(message)
      end

      def multi_spinner
        Object.new.tap { |s| s.define_singleton_method(:register) { |*| spinner } }
      end

      def table(data, header: nil)
        require "tty-table"
        opts = header ? { header: header } : {}
        TTY::Table.new(opts) { |t| data.each { |row| t << row } }
      rescue LoadError
        lines = []
        lines << header.join(" | ") if header
        data.each { |row| lines << row.join(" | ") }
        lines.join("\n")
      end

      def box(content, title: nil, **)
        require "tty-box"
        TTY::Box.frame(
          content,
          title: title ? { top_left: " #{title} " } : nil,
          padding: [0, 1],
          border: :round,
          **,
        )
      rescue LoadError
        lines = []
        lines << bold(title) if title
        lines << ""
        content.each_line { |l| lines << "  #{l.rstrip}" }
        lines << ""
        lines.join("\n")
      end

      def markdown(text, width: nil)
        require "tty-markdown"
        TTY::Markdown.parse(text, width: width || screen_width)
      rescue LoadError
        text
      end

      def progress(total, format: :bar)
        require "tty-progressbar"
        TTY::ProgressBar.new(
          "[:bar] :percent :eta",
          total: total,
          bar_format: format == :block ? :block : :classic,
        )
      rescue LoadError
        Object.new.tap do |p|
          p.instance_variable_set(:@current, 0)
          p.instance_variable_set(:@total, total)
          p.define_singleton_method(:advance) do |n = 1|
            @current += n
            print "\r  #{@current}/#{@total}"
          end
          p.define_singleton_method(:finish) { puts " done" }
        end
      end

      def cursor
        @cursor ||= begin
          require "tty-cursor"
          TTY::Cursor
        rescue LoadError
          Module.new do
            def self.hide = ""
            def self.show = ""
            def self.up(_n = 1) = ""
            def self.down(_n = 1) = ""
            def self.forward(_n = 1) = ""
            def self.backward(_n = 1) = ""
            def self.column(_n) = ""
            def self.move_to(_x, _y) = ""
            def self.clear_line = "\r"
            def self.clear_screen = ""
          end
        end
      end

      def reader
        @reader ||= begin
          require "tty-reader"
          TTY::Reader.new
        rescue LoadError
          Object.new.tap do |r|
            r.define_singleton_method(:read_line) { |*| gets }
            r.define_singleton_method(:read_keypress) { begin; $stdin.getch; rescue StandardError; gets; end }
          end
        end
      end

      def tree(data)
        require "tty-tree"
        TTY::Tree.new(data)
      rescue LoadError
        def self.format_tree(data, indent = 0)
          return "" unless data.is_a?(Hash) || data.is_a?(Array)

          lines = []
          (data.is_a?(Hash) ? data : data.each_with_index.to_a).each do |k, v|
            lines << (("  " * indent) + "- #{k}")
            lines << format_tree(v, indent + 1) if v.is_a?(Hash) || v.is_a?(Array)
          end
          lines.join("\n")
        end
        format_tree(data)
      end

      def pie(data)
        require "tty-pie"
        TTY::Pie.new(data: data, radius: 5)
      rescue LoadError
        Object.new.tap do |p|
          p.instance_variable_set(:@data, data)
          p.define_singleton_method(:render) do
            @data.map { |d| "#{d[:name]}: #{d[:value]}" }.join(", ")
          end
        end
      end

      def pager
        @pager ||= begin
          require "tty-pager"
          TTY::Pager.new
        rescue LoadError
          Object.new.tap do |p|
            p.define_singleton_method(:page) { |text| puts text }
          end
        end
      end

      def link(text, url)
        require "tty-link"
        TTY::Link.link_to(text, url)
      rescue LoadError
        "#{text} (#{url})"
      end

      def font(text, font_name = :doom)
        require "tty-font"
        TTY::Font.new(font_name).write(text)
      rescue LoadError
        text
      end

      def edit(path_or_text)
        require "tty-editor"
        TTY::Editor.open(path_or_text)
      rescue LoadError
        editor = ENV["EDITOR"] || "vi"
        if File.exist?(path_or_text)
          system(editor, path_or_text)
        else
          tmpfile = "/tmp/master_edit_#{Time.now.to_i}.txt"
          File.write(tmpfile, path_or_text)
          system(editor, tmpfile)
          File.read(tmpfile)
        end
      end

      def command(*cmd, **)
        require "tty-command"
        TTY::Command.new(printer: :quiet).run(*cmd, **)
      rescue LoadError
        system(*cmd)
      end

      def pastel
        @pastel ||= begin
          require "pastel"
          Pastel.new(enabled: color_enabled?)
        rescue LoadError
          Object.new.tap do |p|
            %i[green red yellow cyan dim bold magenta bright_magenta bright_cyan bright_black blue].each do |color|
              p.define_singleton_method(color) { |text = nil| text.nil? ? self : text }
            end
          end
        end
      end
    end
  end
end
