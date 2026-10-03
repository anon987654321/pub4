# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module AI
    module Trajectory
      module Dataset
        SCHEMA = "master.llm.sft/v1"

        module_function

        def export(input:, output:)
          FileUtils.mkdir_p(File.dirname(output))
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


        def export_preferences(input:, output:)
          records = File.foreach(input).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
          grouped = records.group_by { |record| record["task"].to_s }
          count = 0
          FileUtils.mkdir_p(File.dirname(output))
          File.open(output, "w") do |out|
            grouped.each_value do |group|
              chosen = group.find { |record| Benchmark.score(record)["verified"] }
              rejected = group.find { |record| !Benchmark.score(record)["verified"] }
              next unless chosen && rejected
              out.puts(JSON.generate(
                "schema" => "master.llm.preference/v1",
                "task" => chosen["task"],
                "chosen" => chosen["events"],
                "rejected" => rejected["events"]
              ))
              count += 1
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
