# frozen_string_literal: true

require_relative "../command_registry/formatter"

module Master
  module CLI
    class Session
      private

      def run_help(command = nil)
        arg = command.to_s.strip
        text = arg.empty? ? Master::CLI::CommandRegistry.help_summary : Master::CLI::CommandRegistry.help_text(arg)
        puts @refs.renderer.render(text, mode: :dim)
        puts @refs.renderer.render("<< for multiline. anything else is a prompt.", mode: :dim) if arg.empty?
      end

      def safe_read_line
        Reline.readline("", true)&.chomp
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @refs.bus)
      end

      def setup_completion
        Reline.completion_proc = proc do |target|
          line = Reline.line_buffer.to_s
          if line.match?(%r{\A/(scan|fix|critique)\s+})
            complete_paths(target)
          else
            SLASH_COMMANDS.select { |cmd| cmd.start_with?(target.to_s) }
          end
        end
      end

      def complete_paths(target)
        prefix = target.to_s.empty? ? "*" : "#{target}*"
        Dir.glob(File.join(@refs.root, prefix)).map do |path|
          rel = path.delete_prefix("#{@refs.root}/")
          File.directory?(path) ? "#{rel}/" : rel
        end.first(50)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_paths")
        []
      end

      def cli_history_path
        File.join(@refs.root, ".master", "cli_history")
      end

      def load_cli_history
        path = cli_history_path
        return unless File.exist?(path)

        File.readlines(path, chomp: true).last(HISTORY_LIMIT).each { |line| Reline::HISTORY << line unless line.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.load_history", event_bus: @refs.bus)
      end

      def save_cli_history
        path = cli_history_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, Reline::HISTORY.to_a.last(HISTORY_LIMIT).join("\n") + "\n")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.save_history", event_bus: @refs.bus)
      end

      def exit_cli
        @refs.session&.save!
        save_cli_history
        line = @refs.renderer.closing
        puts line if line
        @running = false
      end

      def read_multiline
        lines = []
        puts @refs.renderer.render("enter lines, blank line to send", mode: :dim)
        loop do
          print "  "
          inner = safe_read_line
          break if inner.nil? || inner.strip.empty?
          lines << inner
          if lines.size >= MULTILINE_MAX_LINES
            puts @refs.renderer.render("multiline: capped at #{MULTILINE_MAX_LINES} lines", mode: :warning)
            break
          end
        end
        lines.join("\n")
      end

      def replay_recent_turns
        tail = @refs.session.messages.last(REPLAY_TURNS * 2)
        return if tail.empty?
        puts @refs.renderer.render("resume0: replaying last #{tail.size} messages", mode: :dim)
        tail.each do |msg|
          tag = msg[:role] == :user ? "you" : "master"
          content = msg[:content].to_s
          first_line = content.lines.first.to_s
          snippet = first_line.strip[0, 100]
          puts @refs.renderer.render("  #{tag}: #{snippet}", mode: :dim)
        end
        puts
      end

      def print_repo_tree
        lines = Master::CLI::CommandRegistry.dispatch_tree(@refs.root).to_s.split("\n")
        return if lines.empty?
        puts @refs.renderer.render("tree0: #{File.basename(@refs.root)} (#{lines.size} entries)", mode: :dim)
        lines.each { |l| puts @refs.renderer.render(l, mode: :dim) }
        puts
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @refs.bus)
      end

      def booted_before?
        flag = File.join(@refs.root, ".master", "booted_once")
        File.exist?(flag)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @refs.bus)
        false
      end

      def skip_boot_scan?
        ENV["MASTER_SKIP_BOOT_SCAN"] == "1" || ENV["MASTER_PIPE"] == "1"
      end

      def print_boot_wayfinding
        puts @refs.renderer.boot_wayfinding(constitution: true, agent: true, scan: :active)
        start_boot_scan
      end

      def first_boot_bar
        return unless $stdout.isatty
        flag = File.join(@refs.root, ".master", "booted_once")
        return if File.exist?(flag)
        INIT_FRAMES.times do |i|
          bar = ("\u25B0" * (i + 1)) + ("\u25B1" * (INIT_FRAMES - i - 1))
          pct = ((i + 1) * 100 / INIT_FRAMES).to_s.rjust(3)
          print "\rinit0: #{bar} #{pct}%"
          $stdout.flush
          sleep INIT_FRAME_MS
        end
        puts
        FileUtils.mkdir_p(File.dirname(flag))
        File.write(flag, Time.now.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @refs.bus)
      end
    end
  end
end
