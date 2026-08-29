# frozen_string_literal: true

module Master
  module CLI
    class Session
      Container = Struct.new(
        :session, :agent, :renderer, :logging, :undo, :config, :pipeline,
        :scanner, :root, :diff_stager, :bus, :watch_loop,
        :phase_gates, :skills,
        keyword_init: true
      ) do
        def self.from_hash(deps)
          new(
            session: deps[:session],
            agent: deps[:agent],
            renderer: deps[:renderer],
            logging: deps[:logging],
            undo: deps[:undo],
            config: deps[:config],
            pipeline: deps[:pipeline],
            scanner: deps[:scanner],
            root: deps.fetch(:root, Dir.pwd),
            diff_stager: deps[:diff_stager],
            bus: deps[:bus],
            watch_loop: deps[:watch_loop],
            phase_gates: deps[:phase_gates],
            skills: deps[:skills],
          )
        end
      end
    end
  end
end
