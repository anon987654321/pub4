# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "prism"
require "time"
require_relative "../reach/git_operations"
require_relative "../judge/repo_ecology"
require_relative "opportunity_surface/opportunity_generators"

module Master
  module Now
    class OpportunitySurface
      REVIEW_LINES_THRESHOLD = 50
      TEST_FILE_PATTERN = %r{\AMASTER/test/test_(.+)\.rb\z}.freeze

      include OpportunityGenerators

      def initialize(root:, bus: nil, git: nil, scanner: nil)
        @root = root
        @bus = bus
        @git = git || Master::Reach::GitOperations.new(root)
        @scanner = scanner
        @repo_ecology = nil
      end

      def call
        proposals = []
        proposals.concat(clean_scan_opportunities)
        proposals.concat(pattern_extraction_opportunities)
        proposals.concat(semantic_duplicate_opportunities)
        proposals.concat(literal_abstraction_opportunities)
        proposals.concat(layer_purity_opportunities)
        proposals.concat(sibling_fix_opportunities)
        proposals.concat(commit_review_opportunities)
        proposals.concat(test_gap_opportunities)
        proposals.compact
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "opportunity_surface.call", event_bus: @bus)
        []
      end

      private

      def clean_scan_opportunities
        return [] unless recent_clean_scan?

        report = repo_ecology.scan
        persist_dead_file_history(report[:dead_file_candidates])
        out = []
        out << architecture_critique(report)
        out.concat(coupling_opportunities(report[:co_change_pairs]))
        out.concat(refactor_opportunities(report[:similar_clusters]))
        out.concat(dead_file_opportunities(report[:dead_file_candidates]))
        out.concat(dead_file_repeat_opportunities)
        out.concat(review_large_files(report[:large_files]))
        out
      end

      def persist_dead_file_history(candidates)
        path = File.join(@root, "runtime", "dead_file_radar.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") do |file|
          file.puts(JSON.generate(
            ts: Time.now.utc.iso8601,
            candidates: Array(candidates).map { |candidate| candidate[:path].to_s }
          ))
        end
      rescue StandardError
        nil
      end

      def dead_file_history
        path = File.join(@root, "runtime", "dead_file_radar.jsonl")
        return [] unless File.exist?(path)

        File.readlines(path, chomp: true).filter_map do |line|
          data = JSON.parse(line, symbolize_names: true)
          { ts: data[:ts], candidates: Array(data[:candidates]).map(&:to_s) }
        rescue JSON::ParserError
          nil
        end
      rescue StandardError
        []
      end

      def recent_clean_scan?
        return false unless @bus&.respond_to?(:tail)

        events = @bus.tail(20)
        scan = events.reverse.find { |event| event[:event].to_s == "scan:complete" }
        scan && scan.dig(:payload, :count).to_i.zero?
      rescue StandardError
        false
      end

      def coupling_opportunities(pairs)
        Array(pairs).filter_map do |pair|
          next unless pair[:count].to_i >= 5

          prop(
            action: "/refactor",
            reason: "co-change pair #{pair[:a]} ↔ #{pair[:b]} changed together #{pair[:count]} times; extract shared concern",
            weight: 0.74
          )
        end.first(3)
      end

      def refactor_opportunities(clusters)
        Array(clusters).filter_map do |cluster|
          next unless cluster[:count].to_i >= 2

          prop(
            action: "/refactor",
            reason: "similar cluster #{cluster[:signature]} spans #{cluster[:count]} files; consider a shared module",
            weight: 0.68
          )
        end.first(3)
      end

      def dead_file_opportunities(candidates)
        Array(candidates).filter_map do |candidate|
          prop(
            action: "/review",
            reason: "#{candidate[:path]} looks dead: #{candidate[:reason]}",
            weight: 0.62
          )
        end.first(3)
      end

      def dead_file_repeat_opportunities
        history = dead_file_history
        return [] if history.size < 3

        recent = history.last(3)
        repeated = recent.map { |entry| entry[:candidates] }.reduce(:&) || []
        return [] if repeated.empty?

        path = repeated.first
        [prop(
          action: "/review",
          reason: "#{path} has appeared as a dead-file candidate in 3 recent scans; schedule removal",
          weight: 0.64
        )]
      end

      def review_large_files(files)
        Array(files).filter_map do |file|
          next unless file[:lines].to_i > 0

          prop(
            action: "/review",
            reason: "#{file[:path]} is #{file[:lines]} lines; consider a split before it drifts into a god class",
            weight: 0.55
          )
        end.first(3)
      end

      def pattern_extraction_reason(path, message)
        rel = path.delete_prefix("#{@root}/")
        if message.to_s.match?(/Strategy opportunity/i)
          "#{rel}: #{message} — before: one method branches by type; after: extract named handlers behind a Strategy"
        else
          "#{rel}: #{message} — before: one method chains many transforms; after: split the steps into a named pipeline"
        end
      end

      def architecture_critique(report)
        score = report[:score] || {}
        prop(
          action: "/why",
          reason: "architecture critique: #{score[:grade]} at #{score[:value]}/100 with #{Array(report[:large_files]).size} large file(s), #{Array(report[:similar_clusters]).size} similar cluster(s), and #{Array(report[:co_change_pairs]).size} co-change pair(s)",
          weight: 0.66
        )
      end

      def repo_ecology
        @repo_ecology ||= Master::Judge::RepoEcology.new(root: @root, event_bus: @bus)
      end

      def prop(action:, reason:, weight:)
        {
          action: action,
          reason: reason,
          weight: weight,
          confidence: [weight.to_f, 1.0].min,
          impact: 0.5 + [weight.to_f / 2.0, 0.5].min,
          kind: :opportunity,
          estimated_tokens: 450,
          estimated_cost: 0.0014
        }
      end
    end
  end
end
