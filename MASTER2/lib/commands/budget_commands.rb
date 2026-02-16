# frozen_string_literal: true

module MASTER
  module Commands
    # Budget and cost tracking commands
    module BudgetCommands
      def print_budget
        tier = LLM.tier
        remaining = LLM.budget_remaining
        spent = LLM::SPENDING_CAP - remaining
        pct = (spent / LLM::SPENDING_CAP * 100).round(1)

        UI.header("Budget Status")
        puts "  Tier:      #{tier}"
        puts "  Remaining: #{UI.currency(remaining)}"
        puts "  Spent:     #{UI.currency(spent)} (#{pct}%)"
        puts
      end

      def print_context_usage
        session = Session.current
        u = ContextWindow.usage(session)

        UI.header("Context Window")
        puts "  #{ContextWindow.bar(session)}"
        puts "  Used:      #{humanize_tokens(u[:used])}"
        puts "  Limit:     #{humanize_tokens(u[:limit])}"
        puts "  Remaining: #{humanize_tokens(u[:remaining])}"
        puts "  Messages:  #{session.message_count}"
        puts
      end

      def humanize_tokens(n)
        n >= 1000 ? "#{(n / 1000.0).round(1)}k" : n.to_s
      end

      def print_cost_history
        costs = DB.recent_costs(limit: 10)

        if costs.empty?
          puts "\n  No history yet.\n"
        else
          UI.header("Recent Queries", width: 50)
          costs.each do |row|
            model = row[:model].split("/").last[0, 12]
            tokens_in = row[:tokens_in]
            tokens_out = row[:tokens_out]
            cost = row[:cost]
            created = row[:created_at]
            puts "  #{created[0, 16]} | #{model.ljust(12)} | #{tokens_in}->#{tokens_out} | #{UI.currency_precise(cost)}"
          end
          puts
        end
      end
    end
  end
end
