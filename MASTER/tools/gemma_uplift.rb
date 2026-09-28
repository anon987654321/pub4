#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/master"

module Master
  module Tools
    module GemmaUplift
      module_function

      def usage
        <<~TEXT
          usage:
            ruby MASTER/tools/gemma_uplift.rb contract
            ruby MASTER/tools/gemma_uplift.rb manifest
            ruby MASTER/tools/gemma_uplift.rb score TRAJECTORIES.ndjson
            ruby MASTER/tools/gemma_uplift.rb record TRAJECTORY.json
            ruby MASTER/tools/gemma_uplift.rb export TRAJECTORIES.ndjson OUTPUT.ndjson
        TEXT
      end

      def run(argv)
        command = argv.shift
        case command
        when "contract"
          puts Master::AI::OperatorContract.prompt
        when "manifest"
          puts JSON.pretty_generate(Master::AI::OperatorContract.manifest)
        when "score"
          score_file(argv.fetch(0))
        when "record"
          record_file(argv.fetch(0))
        when "export"
          input = argv.fetch(0)
          output = argv.fetch(1)
          count = Master::AI::Uplift::Dataset.export(input:, output:)
          puts "gemma0: exported #{count} verified trajectory(s)"
        else
          puts usage
          return false
        end
        true
      rescue ArgumentError, JSON::ParserError => e
        warn "gemma0: #{e.class}: #{e.message}"
        false
      end

      def score_file(path)
        File.foreach(path) do |line|
          next if line.strip.empty?
          record = JSON.parse(line)
          puts JSON.generate(Master::AI::Uplift::Benchmark.score(record))
        end
      end

      def record_file(path)
        record = Master::AI::Uplift::Trajectory.new(JSON.parse(File.read(path)))
        destination = File.join(Master::ROOT, ".master", "gemma", "trajectories.ndjson")
        record.append!(destination)
        puts "gemma0: recorded #{destination}"
      end
    end
  end
end

exit(Master::Tools::GemmaUplift.run(ARGV) ? 0 : 1)
