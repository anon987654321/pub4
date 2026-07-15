# frozen_string_literal: true

module Master
  module Trace
    class Session
      # Save/load the session's durable state to/from disk — separate from
      # Session's own in-memory message/cost/snapshot tracking.
      module Persistence
        def save!
          FileUtils.mkdir_p(File.dirname(@path))
          data = {
            name: @name,
            phase: @phase,
            topic: @topic,
            last_inferred_command: @last_inferred_command,
            last_inferred_args: @last_inferred_args,
            messages: pruned_messages,
            cost: @cost,
            ts: Time.now.to_i
          }
          File.write(@path, JSON.generate(data))
        end

        def load!
          return self unless File.exist?(@path)
          begin
            data = JSON.parse(File.read(@path), symbolize_names: true)
          rescue JSON::ParserError, Errno::ENOENT
            data = {}
          end
          @name = data[:name]
          @phase = data.fetch(:phase, nil)&.to_sym || :discover
          @topic = data[:topic]
          @last_inferred_command = data[:last_inferred_command]
          @last_inferred_args = data[:last_inferred_args]
          @messages = data.fetch(:messages, [])
          @token_est = @messages.sum { |m| Session.estimate_tokens(m[:content]) }
          @cost = data[:cost].to_f
          self
        end
      end
    end
  end
end
