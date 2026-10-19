# frozen_string_literal: true

module Master
  module CLI
    class Session
      Container = Struct.new(
        :session, :agent, :renderer, :logging, :undo, :config, :pipeline,
        :scanner, :root, :diff_stager, :bus, :watch_loop,
        :skills,
        keyword_init: true
      ) do
        def self.from_hash(deps)
          new(**deps.slice(*members), root: deps.fetch(:root, Dir.pwd))
        end
      end
    end
  end
end
