# frozen_string_literal: true

module MASTER
  class Dashboard
    SPARK = " ░▒▓█".chars.freeze

    def render
      clear
      header
      stats_box
      alignment_box
      recent_activity
    end

    private

    def clear = print("\e[2J\e[H")

    def header
      puts UI.bold("\n  MASTER v#{VERSION}\n")
      puts "  #{'─' * 42}\n"
    end

    def stats_box
      s = fetch_stats
      puts "  #{UI.bold('status')}"
      puts "    model    #{UI.dim('│')} #{s[:model]}"
      puts "    circuit  #{UI.dim('│')} #{s[:circuits_ok]} ok  #{s[:circuits_tripped]} tripped"
      puts "    axioms   #{UI.dim('│')} #{s[:axioms]}  personas #{s[:council]}"
      puts
    end

    def alignment_box
      axioms = DB.axioms.first(8) rescue []
      return if axioms.empty?

      puts "  #{UI.bold('constitutional alignment')}"
      axioms.each do |ax|
        score = alignment_score(ax)
        bar   = sparkline(score)
        puts "    #{ax[:id].to_s.ljust(22)} #{UI.dim(bar)} #{score}/10"
      end
      puts
    end

    def recent_activity
      puts "  #{UI.bold('recent')}"
      costs = DB.recent_costs(limit: 5) rescue []
      if costs.empty?
        puts "    #{UI.dim('─ no activity')}"
      else
        costs.each do |row|
          model = row[:model].to_s.split("/").last
          puts "    #{row[:created_at].to_s[11, 5]} #{UI.dim('│')} #{model.ljust(22)} #{UI.dim('│')} #{UI.currency_precise(row[:cost]).rjust(9)}"
        end
      end
      puts
    end

    def fetch_stats
      {
        model:            LLM.respond_to?(:prompt_model_name) ? LLM.prompt_model_name.split("/").last : "─",
        circuits_ok:      LLM.respond_to?(:models) ? LLM.models.count { |m| LLM.circuit_closed?(m.id) } : 0,
        circuits_tripped: LLM.respond_to?(:models) ? LLM.models.count { |m| !LLM.circuit_closed?(m.id) } : 0,
        axioms:           DB.axioms.size,
        council:          DB.council.size,
      }
    rescue StandardError
      { model: "─", circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end

    # Heuristic: scan recent violations for axiom id; fewer = higher alignment
    def alignment_score(axiom)
      violations = DB.recent_violations(axiom_id: axiom[:id], limit: 20) rescue []
      raw = 10 - [violations.size, 10].min
      [[raw, 0].max, 10].min
    end

    def sparkline(score)
      filled = (score * 4.0 / 10).round.clamp(0, 4)
      (SPARK[4] * filled) + (SPARK[0] * (4 - filled))
    end
  end
end

