#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/master"
require_relative "../lib/trace/dmesg"

module Master
  module Tools
    module LlmTrajectory
      module_function

      def usage
        <<~TEXT
          usage:
            ruby MASTER/tools/llm_trajectory.rb contract
            ruby MASTER/tools/llm_trajectory.rb manifest
            ruby MASTER/tools/llm_trajectory.rb benchmark
            ruby MASTER/tools/llm_trajectory.rb score TRAJECTORIES.ndjson
            ruby MASTER/tools/llm_trajectory.rb record TRAJECTORY.json
            ruby MASTER/tools/llm_trajectory.rb export TRAJECTORIES.ndjson OUTPUT.ndjson
            ruby MASTER/tools/llm_trajectory.rb preferences TRAJECTORIES.ndjson OUTPUT.ndjson
        TEXT
      end

      def run(argv)
        command = argv.shift
        case command
        when "contract"
          puts Master::AI::OperatorContract.prompt
        when "manifest"
          puts JSON.pretty_generate(Master::AI::OperatorContract.manifest)
        when "benchmark"
          puts JSON.pretty_generate(Master::AI::Trajectory::Benchmark.suite)
        when "score"
          score_file(argv.fetch(0))
        when "record"
          record_file(argv.fetch(0))
        when "export"
          count = Master::AI::Trajectory::Dataset.export(input: argv.fetch(0), output: argv.fetch(1))
          Master::Trace::Dmesg.status("trajectory0", "exported #{count} verified trajectories")
        when "preferences"
          count = Master::AI::Trajectory::Dataset.export_preferences(input: argv.fetch(0), output: argv.fetch(1))
          Master::Trace::Dmesg.status("trajectory0", "exported #{count} preference pairs")
        else
          Master::Trace::Dmesg::Report.print("/help", usage)
          return false
        end
        true
      rescue ArgumentError, JSON::ParserError => e
        Master::Trace::Dmesg.status("trajectory0", "#{e.class}: #{e.message}", io: $stderr)
        false
      end

      def score_file(path)
        File.foreach(path) do |line|
          next if line.strip.empty?
          puts JSON.generate(Master::AI::Trajectory::Benchmark.score(JSON.parse(line)))
        end
      end

      def record_file(path)
        record = Master::AI::Trajectory::Record.new(JSON.parse(File.read(path)))
        destination = File.join(Master::ROOT, ".master", "trajectories", "trajectories.ndjson")
        record.append!(destination)
        Master::Trace::Dmesg.status("trajectory0", "recorded #{destination}")
      end
    end
  end
end

exit(Master::Tools::LlmTrajectory.run(ARGV) ? 0 : 1)
