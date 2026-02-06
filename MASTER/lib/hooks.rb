# frozen_string_literal: true

require_relative 'db'

module MASTER
  module Hooks
    EVENTS = [
      :before_edit,
      :after_fix,
      :on_stuck,
      :before_commit,
      :after_test,
      :on_quality_fail,
      :on_convergence
    ].freeze

    def self.register(event, handler, priority: 0)
      unless EVENTS.include?(event.to_sym)
        raise ArgumentError, "Unknown event: #{event}"
      end
      
      DB.connection.execute(
        "INSERT INTO hooks (event, handler, priority) VALUES (?, ?, ?)",
        [event.to_s, handler, priority]
      )
    end

    def self.trigger(event, context = {})
      return unless EVENTS.include?(event.to_sym)
      
      handlers = DB.connection.execute(
        "SELECT * FROM hooks WHERE event = ? ORDER BY priority DESC",
        [event.to_s]
      )
      
      handlers.each do |row|
        handler = row["handler"]
        begin
          # Execute handler (could be a shell command or Ruby code)
          if handler.start_with?('ruby:')
            eval(handler.sub('ruby:', ''))
          elsif handler.start_with?('shell:')
            system(handler.sub('shell:', ''))
          end
        rescue => e
          $stderr.puts "[hook] Error in #{event} handler: #{e.message}"
        end
      end
    end

    def self.list(event = nil)
      sql = "SELECT * FROM hooks"
      sql += " WHERE event = ?" if event
      DB.connection.execute(sql, event ? [event.to_s] : [])
    end

    def self.clear(event = nil)
      if event
        DB.connection.execute("DELETE FROM hooks WHERE event = ?", [event.to_s])
      else
        DB.connection.execute("DELETE FROM hooks")
      end
    end
  end
end
