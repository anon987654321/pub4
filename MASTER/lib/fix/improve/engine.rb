# frozen_string_literal: true

require_relative "../../ground/swallow"
require_relative "domains"
require_relative "ideate"
require_relative "restructure"

module Master
  module Fix
    module Improve
      # The engine /fix calls each pass. It reads the pass's own file list,
      # asks the domains for elevation opportunities, ideates, and returns the
      # strongest findings in the exact shape the improvement stage applies —
      # one anchored, smallest-possible step per file, never a rewrite.
      #
      # /fix embodies the improvement it performs: the engine's own files are
      # small, single-concept, and law-anchored, and it never claims an
      # improvement it cannot point at evidence for.
      class Engine
        MAX_PER_DOMAIN = 2

        def initialize(root:, lane: nil)
          @root = File.expand_path(root)
          @lane = lane
        end

        def elevate(files:)
          scoped = Array(files).select { |path| File.file?(path) }
          return [] if scoped.empty?

          opportunities = Domains.scan(root: @root, files: scoped)
          best_per_domain = {}
          opportunities.each do |opportunity|
            best_per_domain[opportunity.domain] ||= []
            next if best_per_domain.fetch(opportunity.domain).size >= MAX_PER_DOMAIN

            best_per_domain[opportunity.domain] << opportunity
          end
          best_per_domain.values.flatten.map { |opportunity| opportunity.finding(root: @root) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "improve.engine.elevate")
          []
        end

        def ideate(files:)
          Ideate.new(root: @root).generate(files: Array(files).select { |p| File.file?(p) })
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "improve.engine.ideate")
          []
        end

        def restructure_proposals(files:)
          Restructure.new(root: @root).proposals(files: Array(files))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "improve.engine.restructure")
          []
        end
      end
    end
  end
end
