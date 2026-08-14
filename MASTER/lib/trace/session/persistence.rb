# frozen_string_literal: true

module Master
  module Trace
    class Session
      # Save/load the session's durable state to/from disk — separate from
      # Session's own in-memory message/cost/snapshot tracking.
      #
      # This is `.master/session.json`, which is the CLI's transcript: one
      # process, one person, one file. Since Session grew per-conversation
      # partitions it reads and writes the :local partition explicitly rather
      # than whichever conversation happens to be current — a web request must
      # never be able to persist a visitor's transcript to the operator's disk,
      # and load! must not drop a visitor's turns into the operator's history.
      module Persistence
        def save!
          FileUtils.mkdir_p(File.dirname(@path))
          data = {
            name: name(Session::LOCAL),
            phase: @phase,
            topic: @topic,
            last_inferred_command: @last_inferred_command,
            last_inferred_args: @last_inferred_args,
            messages: pruned_messages(Session::LOCAL),
            cost: @cost,
            ts: Time.now.to_i,
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
          @phase = data.fetch(:phase, nil)&.to_sym || :discover
          @topic = data[:topic]
          @last_inferred_command = data[:last_inferred_command]
          @last_inferred_args = data[:last_inferred_args]
          @cost = data[:cost].to_f
          # Rebuilt directly rather than replayed through add_message, which
          # would stamp a fresh `ts` on every restored turn and re-derive a name
          # the file already carries. Pinned to :local: this file is the
          # operator's transcript, and loading it must not land in a visitor.
          msgs = data.fetch(:messages, [])
          est = msgs.sum { |m| Session.estimate_tokens(m[:content]) }
          @mutex.synchronize { @conversations[Session::LOCAL] = { messages: msgs, token_est: est, name: data[:name] } }
          self
        end
      end
    end
  end
end
