# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Reach
    module SocialSim
      module Logger
        module_function

        def append(run_dir, event)
          Guard.assert_sandbox!(run_dir: run_dir)
          path = File.join(run_dir, "events.jsonl")
          FileUtils.mkdir_p(run_dir)
          File.open(path, "a") { |io| io.puts(JSON.generate(event)) }
        end

        def read_all(run_dir)
          path = File.join(run_dir, "events.jsonl")
          return [] unless File.file?(path)

          File.readlines(path).filter_map do |line|
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
        end
      end
    end
  end
end
