# frozen_string_literal: true

module MASTER
  module Commands
    # Session management commands
    module SessionCommands
      def manage_session(args)
        case args&.split&.first
        when "new"
          Session.start_new
          puts "  New session: #{UI.truncate_id(Session.current.id)}"
        when "save"
          Session.current.save
          puts "  Session saved: #{UI.truncate_id(Session.current.id)}"
        when "load", "resume"
          id = args.split[1]
          if id && Session.resume(id)
            puts "  Resumed session: #{UI.truncate_id(Session.current.id)}"
          else
            puts "  Session not found: #{id}"
          end
        when "info"
          s = Session.current
          UI.header("Session Info")
          puts "  ID:       #{s.id}"
          puts "  Messages: #{s.message_count}"
          puts "  Cost:     #{UI.currency_precise(s.total_cost)}"
          puts "  Created:  #{s.created_at}"
          puts
        else
          puts "  Usage: session [new|save|load <id>|info]"
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
