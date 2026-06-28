# frozen_string_literal: true

require "fileutils"
require "tty-reader"

module Master
  module Now
    class CLI
      class Repl
        MULTILINE_CAP = 500
        HISTORY_PATH = ".master/cli_history"

        NL_DISPATCH = [
          [/\b(?:show|print|list)\s+(?:undo\s+)?histor/i, :run_history],
          [/\b(?:why|how)\s+(?:this|that|did|was)\b/i, :run_why],
          [/\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i, :toggle_focus],
          [/\b(?:last|prev(?:ious)?)\s+(?:input|message|prompt)\b/i, :run_last],
          [/\b(?:suggest|what(?:'s|\s+is)\s+next|next\s+steps?)\b/i, :run_propose],
          [/\b(?:show|list)\s+(?:my\s+)?principles\b/i, :run_principles],
          [/\brestart\b|\bhot[\s-]?reload\b/i, :run_restart],
          [/\bui[\s-]?critique\b/i, :run_ui_critique],
          [/\bsound[\s-]?critique\b/i, :run_sound_critique],
          [/\brebuild\b/i, :run_rebuild],
          [/\bshow\s+context\b|\bcontext\s+window\b/i, :run_context],
          [/\bverifie?d?\b/i, :run_verify],
          [/\brails[\s-]?pwa[\s-]?audit\b/i, :run_rails_pwa_audit],
          [/\brails[\s-]?pwa[\s-]?fix\b/i, :run_rails_pwa_fix],
          [/\bswallow[\s-]?report\b|\berror\s+ledger\b/i, :run_swallow_report],
          [/\btoggle\s+chips?\b|\bchips?\s+(?:on|off)\b/i, :toggle_chips],
          [/\btoggle\s+dmesg\b|\bdmesg\s+(?:on|off)\b/i, :toggle_dmesg],
        ].freeze

        def initialize(cli:)
          @cli = cli
          @reader = TTY::Reader.new(track_history: true)
          load_history!
        end

        def loop
          while @cli.running?
            @cli.display.prompt_for_mode
            line = safe_read_line
            break if line.nil?
            handle_line(line)
          end
          @cli.background_scan.request_stop!
          persist_history!
          @cli.session.save!
        end

        def handle_line(line)
          stripped = line.strip
          return @cli.accept_top_suggestion if stripped.empty?
          NL_DISPATCH.each { |pat, meth| return @cli.send(meth) if stripped.match?(pat) }
          case stripped
          when "/help", "/?" then @cli.run_help(stripped)
          when %r{\A/help\s+(\S+)\z}i then @cli.run_help(stripped)
          when "/exit", "/quit" then @cli.exit_cli
          when "/undo" then @cli.run_undo
          when "/redo" then @cli.run_redo
          when "/checkpoint" then @cli.run_checkpoint
          when "/history" then @cli.run_history
          when "/why" then @cli.run_why
          when "/focus" then @cli.toggle_focus
          when "/last" then @cli.run_last
          when "/cmd" then @cli.run_cmd
          when "/dmesg" then @cli.toggle_dmesg
          when "/chips" then @cli.toggle_chips
          when "/propose" then @cli.run_propose
          when "/principles" then @cli.run_principles
          when "/restart" then @cli.run_restart
          when "/self" then @cli.run_self_scan
          when "/ui-critique" then @cli.run_ui_critique
          when "/sound-critique" then @cli.run_sound_critique
          when "/rebuild" then @cli.run_rebuild
          when "/context" then @cli.run_context
          when "/verify" then @cli.run_verify
          when "/rails-pwa-audit" then @cli.run_rails_pwa_audit
          when "/rails-pwa-fix" then @cli.run_rails_pwa_fix
          when "/swallow-report" then @cli.run_swallow_report
          when "<<" then @cli.run_input(read_multiline)
          else stripped.start_with?("/") ? @cli.run_input(stripped) : @cli.run_input(line)
          end
        end

        private

        def safe_read_line
          @reader.read_line("", echo: true).chomp
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.repl.safe_read_line", event_bus: @cli.bus)
        end

        def read_multiline
          lines = []
          puts @cli.renderer.render("enter lines, blank line to send", mode: :dim)
          loop do
            print "  "
            inner = safe_read_line
            break if inner.nil? || inner.strip.empty?
            lines << inner
            break if lines.size >= MULTILINE_CAP
          end
          lines.join("\n")
        end

        def history_path
          File.join(@cli.root, HISTORY_PATH)
        end

        def load_history!
          return unless File.exist?(history_path)
          File.readlines(history_path, chomp: true).last(500).each { |l| @reader.history << l }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.repl.load_history", event_bus: @cli.bus)
        end

        def persist_history!
          FileUtils.mkdir_p(File.dirname(history_path))
          File.write(history_path, @reader.history.to_a.last(500).join("\n") + "\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.repl.persist_history", event_bus: @cli.bus)
        end
      end
    end
  end
end
