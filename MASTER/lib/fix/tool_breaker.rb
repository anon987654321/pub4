# frozen_string_literal: true

require "digest"

module Master
  module Fix
    # A fuse per (law, finding) for the length of one /fix run. A fix attempt
    # that ends without a change and finds the file byte-for-byte as the last
    # attempt found it is the same attempt again; after LIMIT of them the model
    # is not asked a fourth time, because the three answers already say this
    # prompt does not produce a repair here. A changed file or a different
    # finding is a different tuple and starts at one.
    #
    # Only outcomes where a model answered and the answer failed count. A lane
    # that did not answer (:model_failed, :model_unavailable) is the
    # environment's failure, and the lane breaker in Io::LaneHealth owns it:
    # fusing a tuple for an outage would turn five minutes of dead lane into a
    # file skipped for the whole run.
    #
    # RunBudget reports `fused_count` at every pass boundary, which is the
    # reader that keeps a tripped fuse from being silent.
    class ToolBreaker
      LIMIT = 3
      COUNTED = %i[no_proposal reflexion_rejected consensus_rejected rejected].freeze
      Entry = Struct.new(:state, :count)

      class << self
        def current = @current ||= new

        def reset! = @current = new

        def refuse?(tool, finding, state) = current.refuse?(tool, finding, state)

        def record(tool, finding, state, outcome) = current.record(tool, finding, state, outcome)

        def fused_count = current.fused_count

        # The file's bytes are the state: any edit, ours or a person's, reopens the tuple.
        def state_of(finding)
          Digest::SHA256.file(finding[:file].to_s).hexdigest
        rescue SystemCallError
          ""
        end
      end

      def initialize(limit: LIMIT)
        @limit = limit
        @entries = {}
        @lock = Mutex.new
      end

      def refuse?(tool, finding, state)
        @lock.synchronize do
          entry = @entries[key(tool, finding)]
          entry && entry.state == state && entry.count >= @limit
        end || false
      end

      def record(tool, finding, state, outcome)
        tuple = key(tool, finding)
        fused = @lock.synchronize do
          next @entries.delete(tuple) && false if %i[applied commit_refused].include?(outcome)
          next false unless COUNTED.include?(outcome)

          entry = @entries[tuple]
          entry = @entries[tuple] = Entry.new(state, 0) unless entry&.state == state
          entry.count += 1
          entry.count == @limit
        end
        announce(tool, finding) if fused
        fused
      end

      def fused_count = @lock.synchronize { @entries.each_value.count { |entry| entry.count >= @limit } }

      private

      def key(tool, finding) = [tool.to_s, finding[:file].to_s, finding[:message].to_s]

      def announce(tool, finding)
        Master::Trace::Dmesg.status("fix0", "#{tool} fused on #{File.basename(finding[:file].to_s)}, " \
                                            "#{@limit} identical attempts and the file unchanged; not asking again this run")
      end
    end
  end
end
