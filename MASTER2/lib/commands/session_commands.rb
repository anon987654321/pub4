# frozen_string_literal: true

module MASTER
  module Commands
    # Session management commands
    module SessionCommands
      def manage_session(args)
        parts = args&.split || []
        case parts.first
        when "new"
          Session.start_new
          puts "  New session: #{UI.truncate_id(Session.current.id)}"
        when "save"
          Session.current.save
          puts "  Session saved: #{UI.truncate_id(Session.current.id)}"
        when "load", "resume"
          id = parts[1]
          if id && Session.resume(id)
            puts "  Resumed session: #{UI.truncate_id(Session.current.id)}"
          else
            puts "  Session not found: #{id}"
          end
        when "info"
          s = Session.current
          UI.header("Session Info")
          puts [
            "  ID:       #{s.id}",
            "  Messages: #{s.message_count}",
            "  Cost:     #{UI.currency_precise(s.total_cost)}",
            "  Created:  #{s.created_at}"
          ].join("\n")
          puts
        when "replay"
          return puts "  SessionReplay not available" unless defined?(SessionReplay)
          id = parts[1] || Session.current.id
          SessionReplay.replay(id)
        when "list-detail", "ls"
          return puts "  SessionReplay not available" unless defined?(SessionReplay)
          result = SessionReplay.list_with_summaries
          if result.ok?
            UI.header("Sessions (detailed)")
            result.value.each do |s|
              status = s[:crashed] ? UI.red("CRASHED") : UI.green("ok")
              cost_str = s[:cost] > 0 ? UI.currency_precise(s[:cost]) : "free"
              puts "  #{s[:short_id]} | #{s[:messages]} msgs | #{cost_str} | #{s[:duration]} | #{status}"
            end
            puts
          end
        when "diff"
          return puts "  SessionReplay not available" unless defined?(SessionReplay)
          if parts.size >= 3
            result = SessionReplay.diff_sessions(parts[1], parts[2])
            if result.ok?
              diff = result.value
              puts "\n  Session Diff:"
              puts "  A: #{diff[:session_a][:messages]} messages"
              puts "  B: #{diff[:session_b][:messages]} messages"
              puts "  Cost diff: #{UI.currency_precise(diff[:cost_diff].abs)} (#{diff[:cost_diff] > 0 ? '+' : '-'})"
              puts
            else
              puts "  Error: #{result.error}"
            end
          else
            puts "  Usage: session diff <id_a> <id_b>"
          end
        when "export"
          return puts "  SessionReplay not available" unless defined?(SessionReplay)
          id = parts[1] || Session.current.id
          format = args&.include?("--md") ? :markdown : :json
          result = SessionReplay.replay(id, format: format)
          if result.ok?
            puts result.value if format == :markdown
            puts JSON.pretty_generate(result.value) if format == :json
          else
            puts "  Error: #{result.error}"
          end
        else
          puts <<~HELP

            Session Commands:

              session new                  Start new session
              session save                 Save current session
              session load <id>            Load saved session
              session info                 Show current session info
              session replay [id]          Replay session conversation
              session ls                   List sessions with details
              session diff <a> <b>         Diff two sessions
              session export [id] [--md]   Export session as JSON or Markdown

          HELP
        end
      end

      def print_saved_sessions
        sessions = Session.list
        if sessions.empty?
          puts "\n  No saved sessions.\n"
        else
          UI.header("Saved Sessions")
          sessions.each do |id|
            data = Memory.load_session(id)
            next unless data

            msgs = data[:history]&.size || 0
            puts "  #{UI.truncate_id(id)} | #{msgs} messages"
          end
          puts
        end
      end

      def undo_last_exchange
        session = Session.current
        if session.history.size < 2
          puts "  Nothing to forget."
          return
        end

        # IMMUTABLE_HISTORY: append tombstone instead of mutating
        session.history << { role: :system, content: "[UNDO: Previous 2 messages hidden]", tombstone: true, undone_at: Time.now.utc.iso8601 }
        session.instance_variable_set(:@undo_count, (session.instance_variable_get(:@undo_count) || 0) + 1)
        session.instance_variable_set(:@dirty, true)
        puts "  Marked last exchange as undone. Context preserved for history."
      end

      def print_session_summary
        session = Session.current
        if session.history.empty?
          puts "  No conversation yet."
          return
        end

        UI.header("Conversation Summary")
        puts "  Messages: #{session.message_count}"
        puts "  Cost:     #{UI.currency_precise(session.total_cost)}"
        puts

        history = session.history
        puts "  First message: #{truncate(history.first[:content], 60)}"
        puts "  Last message:  #{truncate(history.last[:content], 60)}" if history.size > 1
        puts
      end

      def truncate(str, max)
        return str if str.length <= max
        "#{str[0, max - 3]}..."
      end
    end
  end
end
