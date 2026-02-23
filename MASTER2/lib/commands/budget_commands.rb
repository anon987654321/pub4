# frozen_string_literal: true

module MASTER
  module Commands
    # Budget and cost tracking commands
    module BudgetCommands
      TOKENS_PER_K        = 1000
      COST_HISTORY_LIMIT  = 10
      def print_budget
        UI.header("Budget Status")
        puts "  Tier:      #{LLM.tier}"
        puts "  Budget:    unlimited (managed by OpenRouter)"
        puts
      end

      def print_context_usage
        session = Session.current
        usage = ContextWindow.usage(session)

        UI.header("Context Window")
        puts "  #{ContextWindow.bar(session)}"
        puts "  Used:      #{humanize_tokens(usage[:used])}"
        puts "  Limit:     #{humanize_tokens(usage[:limit])}"
        puts "  Remaining: #{humanize_tokens(usage[:remaining])}"
        puts "  Messages:  #{session.message_count}"
        puts
      end

      def humanize_tokens(n)
        n >= TOKENS_PER_K ? "#{(n / TOKENS_PER_K.to_f).round(1)}k" : n.to_s
      end

      def print_cost_history
        costs = DB.recent_costs(limit: COST_HISTORY_LIMIT)

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
