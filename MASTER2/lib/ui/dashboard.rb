# frozen_string_literal: true

module MASTER
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
      puts "    Model Tier:    #{stats[:tier].to_s.rjust(8)}"
      puts "    Budget:        managed by OpenRouter"
      puts "    Circuit:       #{stats[:circuits_ok].to_s.rjust(3)} ok, #{stats[:circuits_tripped].to_s.rjust(3)} tripped"
      puts "    #{UI.pluralize(stats[:axioms],  'axiom').rjust(12)}"
      puts "    #{UI.pluralize(stats[:council], 'persona').rjust(12)}"
      puts
    end

    def budget_box
      puts "  #{@ui.bold('Budget Usage')}"
      puts "    managed by OpenRouter"
      puts
    end

    def recent_activity
      puts "  #{@ui.bold('Recent Activity')}"

      costs = DB.recent_costs(limit: 5)

      if costs.empty?
        puts "    (no activity yet)"
      else
        costs.each do |row|
          model  = row[:model].split("/").last
          cost   = row[:cost]
          ts     = row[:created_at]
          puts "    #{ts[11, 5]} #{@ui.dim('│')} #{model.ljust(20)} #{@ui.dim('│')} #{UI.currency_precise(cost).rjust(9)}"
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
        circuits_ok: LLM.models.count { |m| LLM.circuit_closed?(m.id) },
        circuits_tripped: LLM.models.count { |m| !LLM.circuit_closed?(m.id) },
        axioms: DB.axioms.size,
        council: DB.council.size,
      }
    rescue StandardError
      { tier: :unknown, circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end
  end
end
