# frozen_string_literal: true

module Deploy
  # Weight is a size, not a count, so it cannot ride the tally shape
  # judge_budgets uses. The contract is otherwise identical: over the ceiling
  # fails, under it warns, and GATE_CSS_RATCHET=1 records the new low.
  #
  # app/assets/builds/application.css is the only stylesheet this gate can weigh
  # reproducibly. RAILS/*/public/assets/ is gitignored, so the compiled JS is
  # whatever the local machine last built; weighing it would fail on the wrong
  # laptop rather than on the wrong commit.
  module CssWeight
    def check_weight
      ceilings = weight_ceilings
      return @result.warn("css_constitution weight: no weight_kb in css_budget.yml") if ceilings.empty?

      ceilings.each do |app, ceiling|
        built = File.join(CssConstitutionGate::RAILS, app, "app", "assets", "builds", "application.css")
        next @result.warn("css_constitution weight: #{app} has no built application.css") unless File.file?(built)

        kb = (File.size(built) / 1024.0).ceil
        if kb > ceiling
          @result.fail("css_constitution weight: #{app} application.css is #{kb}KB, over its " \
                       "#{ceiling}KB ceiling (+#{kb - ceiling}) -- cut it, or record a new ceiling with a reason")
        elsif kb < ceiling
          @result.warn("css_constitution weight: #{app} is #{kb}KB, under its #{ceiling}KB ceiling " \
                       "(-#{ceiling - kb}) -- GATE_CSS_RATCHET=1 records the new low")
          ratchet_weight(app, kb)
        else
          @result.warn("css_constitution weight: #{app} at its #{ceiling}KB ceiling")
        end
      end
    end

    def weight_ceilings
      YAML.safe_load_file(CssConstitutionGate::BUDGET_PATH)&.dig("weight_kb") || {}
    rescue StandardError => e
      warn "css_constitution: weight budget unreadable (#{e.class}) -- weight runs unbudgeted"
      {}
    end

    def ratchet_weight(app, kb)
      return unless GateResult.flag?("GATE_CSS_RATCHET")

      path = CssConstitutionGate::BUDGET_PATH
      body = File.read(path)
      File.write(path, body.sub(/^  #{Regexp.escape(app)}: \d+$/, "  #{app}: #{kb}"))
    end
  end
end
