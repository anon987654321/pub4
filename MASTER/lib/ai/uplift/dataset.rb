# frozen_string_literal: true

require "json"

module Master
  module AI
    module Uplift
      module Dataset
        SCHEMA = "master.gemma.sft/v1"

        module_function

        def export(input:, output:)
          count = 0
          File.open(output, "w") do |out|
            File.foreach(input) do |line|
              next if line.strip.empty?
              record = JSON.parse(line)
              score = Benchmark.score(record)
              next unless score["verified"]
              out.puts(JSON.generate(
                "schema" => SCHEMA,
                "messages" => messages_for(record),
                "trajectory" => record["events"],
                "score" => score,
                "outcome" => record["outcome"]
              ))
              count += 1
            rescue JSON::ParserError
              next
            end
          end
          count
        end

        def messages_for(record)
          [
            { "role" => "system", "content" => Master::AI::OperatorContract.prompt },
            { "role" => "user", "content" => record["task"].to_s },
            { "role" => "assistant", "content" => JSON.generate(record["events"]) }
          ]
        end
      end
    end
  end
end
