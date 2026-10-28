# frozen_string_literal: true

require_relative "../io/lane_state"

module Master
  module Fix
    # Before /fix reads anything, print the model each kind of call will get
    # and refuse to start on a free or local one while a better lane is live:
    # on 2026-10-26 three runs read the tree on gemma3:4b because the router
    # excluded an idle opus. MASTER_FIX_FREE_OK=1 accepts the free lane.
    module LanePreflight

      OPERATIONS = %i[tree structural_review file_write code_generation].freeze

      Row = Data.define(:operation, :model, :kind)

      module_function

      # nil when the run may start, else a Result::Err naming the operation,
      # the model it would get, and the lane it should have had.
      def check(agent:, env: ENV)
        return unless agent.class.method_defined?(:model_for)

        rows = routes(agent)
        explain_skipped
        weak = rows.find { |row| free_class?(row.model) }
        better = Master::Io::LaneSelection.live_lanes.find { |id| !free_class?(id) }
        return if weak.nil? || better.nil? || env["MASTER_FIX_FREE_OK"] == "1"

        refuse(weak, better)
      end

      def routes(agent)
        OPERATIONS.map do |operation|
          model = agent.model_for(operation:).to_s
          Row.new(operation:, model:, kind: Master::Io::LaneSelection.kind(model))
        end.each { |row| say("#{row.operation} -> #{row.model} (#{row.kind})") }
      ensure
        Fiber[:master_operation] = nil
      end

      # One line per catalogue lane LaneState refuses, with the store and its
      # reason, so a run says which lanes it is not using and why.
      def explain_skipped
        lanes = Master::Io::LaneSelection.catalogue.uniq { |id| Master::Io::LaneState.lane_of(id) }
        lanes.map { |id| Master::Io::LaneState.verdict(id) }.reject(&:usable?).each do |verdict|
          say("skipped #{verdict.model}: #{verdict.source}, #{verdict.reason}")
        end
      end

      def refuse(weak, better)
        message = "fix: #{weak.operation} would run on #{weak.model} (#{weak.kind}) while #{better} is live; " \
                  "the router is excluding it. MASTER_FIX_FREE_OK=1 runs anyway"
        say(message)
        Master::Result.err(message, category: :human_decision)
      end

      def free_class?(model)
        Master::Io::LaneSelection::FREE_CLASS_KINDS.include?(Master::Io::LaneSelection.kind(model))
      end

      def say(text) = Master::Trace::Dmesg.status("lane0", text)
    end
  end
end
