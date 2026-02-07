# frozen_string_literal: true

module MASTER
  # Dashboard - Terminal status display
  class Dashboard
    def initialize
      @ui = UI
    end

    def render
      clear
      header
      stats_box
      budget_box
      recent_activity
      footer
    end

    private

    def clear
      print "\e[2J\e[H"
    end

    def header
      puts @ui.bold("\n  MASTER Dashboard v#{VERSION}\n")
      puts "  #{'-' * 40}\n"
    end

    def stats_box
      stats = fetch_stats

      puts "  #{@ui.bold('System Status')}"
      puts "    Model Tier:    #{stats[:tier]}"
      puts "    Budget:        #{UI.currency(stats[:remaining])} / #{UI.currency(stats[:limit])}"
      puts "    Circuit:       #{stats[:circuits_ok]} ok, #{stats[:circuits_tripped]} tripped"
      puts "    Axioms:        #{stats[:axioms]}"
      puts "    Council:       #{stats[:council]} personas"
      puts
    end

    def budget_box
      spent = LLM::SPENDING_CAP - LLM.budget_remaining
      pct = (spent / LLM::SPENDING_CAP * 100).round(1)

      bar_width = 30
      filled = (pct / 100.0 * bar_width).round
      bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

      puts "  #{@ui.bold('Budget Usage')}"
      puts "    #{bar} #{pct}%"
      puts
    end

    def recent_activity
      puts "  #{@ui.bold('Recent Activity')}"

      costs = DB.recent_costs(limit: 5)

      if costs.empty?
        puts "    (no activity yet)"
      else
        costs.each do |row|
          model = row[:model].split("/").last
          cost = row[:cost]
          created = row[:created_at]
          puts "    #{created[11, 5]} | #{model.ljust(15)} | #{UI.currency_precise(cost)}"
        end
      end
      puts
    end

    def footer
      puts "  #{@ui.dim('Press any key to return...')}"
    end

    def fetch_stats
      {
        tier: LLM.tier,
        remaining: LLM.budget_remaining,
        limit: LLM::SPENDING_CAP,
        circuits_ok: LLM::MODEL_RATES.count { |m, _| LLM.circuit_closed?(m) },
        circuits_tripped: LLM::MODEL_RATES.count { |m, _| !LLM.circuit_closed?(m) },
        axioms: DB.axioms.size,
        council: DB.council.size,
      }
    rescue StandardError
      { tier: :unknown, remaining: 0, limit: 10, circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end
  end
end
