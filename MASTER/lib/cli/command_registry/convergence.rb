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

      def dispatch_explain(_root, ctx: nil)
        Master::Convergence::Architecture.render(root: Master::REPO_ROOT, target: arg_for(ctx))
      end

      def dispatch_prove(_root, ctx: nil)
        return "usage: /prove" unless arg_for(ctx).empty?
        Master::Convergence::Proof.render(root: Master::REPO_ROOT)
      rescue StandardError => e
        "prove0: failed — #{e.class}: #{e.message}"
      end
    end
  end
end
