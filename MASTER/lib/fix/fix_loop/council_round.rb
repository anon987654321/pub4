# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # The council, inside the loop. A pass that found violations asks the
      # panel what is wrong with the files those violations are in, has it
      # propose competing repairs, and hands the strongest of them to the rule
      # loop as context. A critique that ends in prose changes nothing; this is
      # the seam where it becomes a repair the fixer can weigh.
      #
      # It runs at most once per pass and only while the pass has time left,
      # because it is the most expensive call in the loop: a panel over a dozen
      # files costs minutes, and a repair that arrives after the deadline is a
      # repair nobody applies.
      class CouncilRound
        FILES_PER_ROUND = 12

        def initialize(agent:, root:, bus: nil)
          @agent = agent
          @root = root
          @bus = bus
        end

        # nil when there is nothing to argue about or nobody to argue with, so
        # the caller can treat "no council" and "council said nothing" alike.
        def run(files:, pass:, deadline:)
          return if @agent.nil? || files.empty? || Time.now >= deadline

          result = critique(files.first(FILES_PER_ROUND))
          return unless result&.ok?

          value = result.value!
          return if Array(value[:cherry_picks]).empty?

          publish(value, pass:, files:)
          value
        end

        private

        def critique(files)
          Master::Review::Council::Critique.new(mode: :general, agent: @agent, event_bus: @bus, files:).run
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.council_round", event_bus: @bus)
          nil
        end

        def publish(value, pass:, files:)
          picks = Array(value[:cherry_picks]).size
          @bus&.publish("fix_loop:council", pass:, files: files.size,
                                            critiques: Array(value[:feedback]).size, cherry_picks: picks)
          Master::Trace::Dmesg.status("fix0",
                                      "pass #{pass}, council picked #{Master::Trace::Dmesg.counted(picks, "repair")}")
        end
      end
    end
  end
end
