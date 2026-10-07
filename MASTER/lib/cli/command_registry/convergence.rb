# frozen_string_literal: true

require_relative "../../convergence/architecture"
require_relative "../../convergence/measure"
require_relative "../../convergence/proof"
require_relative "../../convergence/wishlist"

module Master
  module CLI
    module CommandRegistry
      module_function

      def dispatch_wishlist(_root, ctx: nil)
        Master::Convergence::Wishlist.render(arg_for(ctx), root: Master::ROOT)
      rescue StandardError => e
        "wishlist0: failed — #{e.class}: #{e.message}"
      end

      def dispatch_size(_root, ctx: nil)
        arg = arg_for(ctx)
        valid = arg.empty? || arg == "all" || Master::Convergence::ROOTS.include?(arg.upcase)
        return "usage: /size [all|MASTER|RAILS|OPENBSD|STUDIO]" unless valid

        target = arg.empty? || arg == "all" ? Master::Convergence::ROOTS : [arg.upcase]
        data = Master::Convergence::Measure.inventory(root: Master::REPO_ROOT)
        lines = ["size0: git=#{data[:git]}"]
        target.each do |name|
          row = data[:trees].fetch(name)
          lines << "size0: #{name} files=#{row[:files]} bytes=#{row[:bytes]} ruby_lines=#{row[:ruby_lines]}"
        end
        lines.join("\n")
      rescue StandardError => e
        "size0: failed — #{e.class}: #{e.message}"
      end

      def dispatch_events(_root, ctx: nil)
        arg = arg_for(ctx)
        strict = arg == "strict"
        return "usage: /events [strict]" unless arg.empty? || strict

        code, output = Master::Trace::EventInventory.render(strict:)
        return output.strip unless output.strip.empty?

        "events0: clean#{strict && code.positive? ? ", problems found" : ""}"
      rescue StandardError => e
        "events0: inconclusive — #{e.class}: #{e.message}"
      end

      def dispatch_explain(_root, ctx: nil)
        Master::Convergence::Architecture.render(root: Master::REPO_ROOT, target: arg_for(ctx))
      end

      def dispatch_prove(_root, ctx: nil)
        arg = arg_for(ctx)
        return render_proof_history(arg.delete_prefix("history").strip) if arg == "history" || arg.start_with?("history ")
        return "usage: /prove [history [N]]" unless arg.empty?
        Master::Convergence::Proof.render(root: Master::REPO_ROOT)
      rescue StandardError => e
        "prove0: failed — #{e.class}: #{e.message}"
      end

      def render_proof_history(argument)
        limit = Integer(argument.empty? ? 10 : argument)
        rows = Master::Convergence::Receipt.recent(root: Master::REPO_ROOT, limit:)
        return "prove0: no receipts" if rows.empty?

        rows.map do |row|
          total = row.dig("inventory", "totals") || {}
          "prove0: #{row["id"]} state=#{row["state"]} files=#{total["files"]} bytes=#{total["bytes"]}"
        end.join("\n")
      rescue ArgumentError
        "usage: /prove history [N]"
      end
    end
  end
end
