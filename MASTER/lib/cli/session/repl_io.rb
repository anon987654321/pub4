# frozen_string_literal: true

module Master
  module CLI
    # The REPL's terminal: help, line reading, completion, history, exit,
    # multiline input and the first-boot screens.
    class Session
      private

      def run_help(command = nil)
        arg = command.to_s.strip
        text = arg.empty? ? Master::CLI::CommandRegistry.help_summary : Master::CLI::CommandRegistry.help_text(arg)
        puts @refs.renderer.render(text, mode: :dim)
        puts @refs.renderer.render("<< for multiline, !command runs zsh. anything else is a prompt.", mode: :dim) if arg.empty?
      end

      # Reline asks the terminal where the cursor is, and a reply that arrives
      # late lands in the input as text, "[38;51R", which would be saved and
      # replayed as the operator's words. A paste the terminal did not bracket
      # arrives as lines already waiting, and those join the first rather than
      # becoming prompts of their own.
      TERMINAL_REPLY = /\e?\[?\d{1,4};\d{1,4}R|\e\[[\d;?]*[A-Za-z~]/

      def safe_read_line(prompt = "")
        line = Reline.readline(prompt, false)
        return if line.nil?

        line = [line, *pasted_lines].join("\n")
        clean = line.gsub(TERMINAL_REPLY, "").chomp
        Reline::HISTORY << clean unless clean.strip.empty?
        clean
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @refs.bus)
      end

      def pasted_lines
        lines = []
        lines << Reline.readline("", false).to_s while lines.size < MULTILINE_MAX_LINES && Reline::IOGate.in_pasting?
        lines
      end

      def setup_completion
        Reline.completion_proc = proc do |target|
          line = Reline.line_buffer.to_s
          if line.match?(%r{\\A/(?:fix|review|status|undo|commit|model|pair|doctor|rules|why|orders|soul|clear|sessions|continue|resume|fork|help)\s+})
            complete_command_argument(line, target)
          elsif line.match?(%r{\A/\S*\z})
            SLASH_COMMANDS.select { |cmd| cmd.start_with?(target.to_s) }
          elsif line.strip.empty?
            ["/fix ", "/review ", "/status ", "/undo ", "/runtime ", "/help "]
          else
            []
          end
        end
      end

      def complete_command_argument(line, target)
        command = line.split.first.to_s
        case command
        when "/model"
          model_completion(target)
        when "/help"
          SLASH_COMMANDS.map { |name| name.delete_prefix("/") }.select { |name| name.start_with?(target.to_s) }
        else
          complete_paths(target)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_argument")
        []
      end

      def model_completion(target)
        pool = @refs.agent.respond_to?(:model_router) && @refs.agent.model_router
        models = pool&.pool(wait: false)
        Array(models).map(&:to_s).select { |model| model.start_with?(target.to_s) }.first(50)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_model")
        []
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
          inner = safe_read_line("  ")
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

        puts
        puts @refs.renderer.render("resume0: last #{tail.size} messages", mode: :dim)
        tail.each do |msg|
          # A loaded transcript holds the role as a string.
          tag = msg[:role].to_s == "user" ? "you" : "master"
          snippet = msg[:content].to_s.gsub(TERMINAL_REPLY, "").lines.first.to_s.strip[0, 100]
          puts @refs.renderer.render("  #{tag}: #{snippet}", mode: :dim) unless snippet.empty?
        end
      end

      def print_repo_tree
        lines = Master::CLI::CommandRegistry.dispatch_tree(@refs.root).to_s.split("\n")
        return if lines.empty?

        # One line, as a disk attaches: the entries are `/tree` away, and two
        # hundred of them buried the prompt on a first boot.
        puts @refs.renderer.render("tree0 at master0: #{File.basename(@refs.root)}, #{lines.size} entries", mode: :dim)
        mark_booted
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

      def mark_booted
        flag = File.join(@refs.root, ".master", "booted_once")
        FileUtils.mkdir_p(File.dirname(flag))
        File.write(flag, Time.now.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @refs.bus)
      end
    end
  end
end
