# frozen_string_literal: true

module MASTER
  # Dashboard - Terminal dashboard with TTY components
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
      puts "    Budget:        $#{'%.2f' % stats[:remaining]} / $#{'%.2f' % stats[:limit]}"
      puts "    Circuit:       #{stats[:circuits_ok]} ok, #{stats[:circuits_tripped]} tripped"
      puts "    Axioms:        #{stats[:axioms]}"
      puts "    Council:       #{stats[:council]} personas"
      puts
    end

    def budget_box
      spent = LLM::BUDGET_LIMIT - LLM.remaining
      pct = (spent / LLM::BUDGET_LIMIT * 100).round(1)

      bar_width = 30
      filled = (pct / 100.0 * bar_width).round
      bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

      puts "  #{@ui.bold('Budget Usage')}"
      puts "    #{bar} #{pct}%"
      puts
    end

    def recent_activity
      puts "  #{@ui.bold('Recent Activity')}"

      costs = DB.connection.execute(
        "SELECT model, cost, created_at FROM costs ORDER BY id DESC LIMIT 5"
      ) rescue []

      if costs.empty?
        puts "    (no activity yet)"
      else
        costs.each do |row|
          model = row['model'].split('/').last
          puts "    #{row['created_at'][11, 5]} | #{model.ljust(15)} | $#{'%.4f' % row['cost']}"
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
        remaining: LLM.remaining,
        limit: LLM::BUDGET_LIMIT,
        circuits_ok: LLM::RATES.count { |m, _| LLM.healthy?(m) },
        circuits_tripped: LLM::RATES.count { |m, _| !LLM.healthy?(m) },
        axioms: DB.axioms.count,
        council: DB.council.count
      }
    rescue
      { tier: :unknown, remaining: 0, limit: 10, circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end
  end
end
