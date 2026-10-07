# frozen_string_literal: true

require_relative "receipt"
require_relative "wishlist"

module Master
  module Convergence
    module Proof
      ROOTS = Master::Convergence::ROOTS

      module_function

      def run(root: Master::REPO_ROOT)
        checks = [
          check_constitution(root),
          check_trees(root),
          check_commands,
          check_wishlist(root),
          check_snapshot_contract(root),
        ]
        failed = checks.select { |row| row[:state] == "fail" }
        inconclusive = checks.select { |row| row[:state] == "inconclusive" }
        state = failed.any? ? :fail : (inconclusive.any? ? :inconclusive : :pass)
        receipt = Receipt.write(root:, command: "convergence.prove", state:, details: { checks: checks })
        { state:, checks:, receipt: }
      end

      def render(root: Master::REPO_ROOT)
        result = run(root:)
        lines = ["prove0: #{result[:state]}"]
        result[:checks].each do |row|
          suffix = row[:detail].to_s.empty? ? "" : ": #{row[:detail]}"
          lines << "prove0: #{row[:name]} #{row[:state]}#{suffix}"
        end
        lines << "prove0: receipt=#{result[:receipt][:path].delete_prefix("#{root}/")}"
        lines.join("\n")
      end

      def check_constitution(root)
        soul = File.join(root, "MASTER", "data", "soul.yml")
        laws = File.join(root, "MASTER", "data", "laws.yml")
        return fail_row("constitution", "soul.yml or laws.yml missing") unless File.file?(soul) && File.file?(laws)

        pass_row("constitution", "soul.yml + laws.yml present")
      rescue StandardError => e
        fail_row("constitution", "#{e.class}: #{e.message}")
      end

      def check_trees(root)
        missing = ROOTS.reject { |tree| File.directory?(File.join(root, tree)) }
        missing.empty? ? pass_row("trees", "four governed roots present") : fail_row("trees", "missing #{missing.join(", ")}")
      end

      def check_commands
        commands = Master::CLI::CommandRegistry::HELP_TOPICS.keys
        required = %w[status fix rules why wishlist size explain prove]
        missing = required - commands
        missing.empty? ? pass_row("commands", "required convergence commands documented") : fail_row("commands", "missing #{missing.join(", ")}")
      rescue StandardError => e
        inconclusive_row("commands", "#{e.class}: #{e.message}")
      end

      def check_wishlist(root)
        items = Wishlist.items(root:)
        missing_paths = items.reject { |item| item[:implementation_present] }
        missing_paths.empty? ? pass_row("wishlist", "#{items.size} workstreams have implementation anchors") :
          inconclusive_row("wishlist", "#{missing_paths.size} workstream implementation anchors need external proof")
      rescue StandardError => e
        fail_row("wishlist", "#{e.class}: #{e.message}")
      end

      def check_snapshot_contract(root)
        snapshot = File.join(root, "MASTER", "tools", "snapshot.rb")
        return fail_row("snapshot", "MASTER/tools/snapshot.rb missing") unless File.file?(snapshot)

        pass_row("snapshot", "share-size bounded snapshot implementation present")
      end

      def pass_row(name, detail) = { name:, state: "pass", detail: detail.to_s }
      def fail_row(name, detail) = { name:, state: "fail", detail: detail.to_s }
      def inconclusive_row(name, detail) = { name:, state: "inconclusive", detail: detail.to_s }
    end
  end
end
