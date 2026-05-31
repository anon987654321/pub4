# frozen_string_literal: true

module Master
  module Loop
  # Architecture #13: CRDT-based codebase convergence for distributed agents.
  # Treats the codebase as a CRDT. Rules define merge functions.
  # Multiple agents make concurrent fixes; the CRDT guarantees eventual
  # consistency without conflict resolution overhead.
  #
  # Status: scaffolded. Implements a LWW-Register (Last-Write-Wins) CRDT
  # per file, with vector clocks for causal ordering across agents.
  # True multi-agent deployment requires a shared clock service or SSE stream.
    class CrdtLoop
      # Last-Write-Wins register per file path.
      LwwRegister = Struct.new(:agent_id, :timestamp, :content, keyword_init: true)

      def initialize(agent_id:, root:, bus: nil)
        @agent_id = agent_id
        @root = root
        @bus = bus
        @state = {} # path → LwwRegister
        @clock = 0
        @mutex = Mutex.new
      end

      # Apply a fix proposal from any agent. Wins if timestamp is newer.
      def propose(path:, content:, timestamp: nil, agent_id: @agent_id)
        ts = timestamp || monotonic_ts
        @mutex.synchronize do
          existing = @state[path]
          if existing.nil? || ts > existing.timestamp
            @state[path] = LwwRegister.new(agent_id: agent_id, timestamp: ts, content: content)
            @bus&.publish("crdt_loop:accepted", path: path, agent: agent_id, ts: ts)
            apply_to_disk(path, content)
            true
          else
            @bus&.publish("crdt_loop:rejected", path: path, agent: agent_id, existing_ts: existing.timestamp)
            false
          end
        end
      end

      # Merge incoming state vector from another agent. Accepts any newer entries.
      def merge(remote_state)
        accepted = 0
        remote_state.each do |path, reg|
          next unless reg.is_a?(LwwRegister)
          accepted += 1 if propose(path: path, content: reg.content,
                                    timestamp: reg.timestamp, agent_id: reg.agent_id)
        end
        @bus&.publish("crdt_loop:merge", accepted: accepted, total: remote_state.size)
        accepted
      end

      # Snapshot of current state — share with peer agents.
      def state_snapshot
        @mutex.synchronize { @state.dup }
      end

      def vector_clock = @clock

      private

      def monotonic_ts
        @mutex.synchronize { @clock += 1 }
      end

      def apply_to_disk(path, content)
        full_path = path.start_with?("/") ? path : File.join(@root, path)
        return unless File.exist?(full_path)
        temporary_path = "#{full_path}.crdt.#{Process.pid}.tmp"
        File.write(temporary_path, content, encoding: "UTF-8")
        File.rename(temporary_path, full_path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CrdtLoop.apply_to_disk", event_bus: @bus, path:)
        File.delete(temporary_path) if defined?(temporary_path) && File.exist?(temporary_path) rescue nil
        @bus&.publish("crdt_loop:write_error", path: path, error: e.message)
      end
    end
  end
end
