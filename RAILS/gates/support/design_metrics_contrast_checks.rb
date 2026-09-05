# frozen_string_literal: true

module Deploy
  class DesignMetricsGate
    # Token contrast, and the budget that decides what to do about it.
    #
    # Split out of design_metrics.rb when that file passed its length ceiling.
    # It is one subject across three methods — pair every declared token against
    # the backgrounds it is actually painted on, score them WCAG and APCA, then
    # judge the two counts against gates/data/css_budget.yml — and the maths it
    # calls lives next door in gates/support/design_metrics_contrast.rb, which
    # was split off the same subject at the other layer.
    #
    # A module included back into the gate, so it keeps @result, @tokens and the
    # private helpers it shares with the other twelve checks.
    module ContrastChecks
      # Enumerate the whole mode-matched fg/bg space per dialect instead of a
      # hand-written list of eight pairs.
      #
      # The old list checked text/bg and text/surface only, and passed — while
      # social.accent/bg sat at 4.37 and `color: var(--accent)` was being used as
      # a text colour in dozens of rules. Anything the author forgets to list is
      # invisible to a list.
      #
      # Severity is deliberately soft here: this enumerates pairings that *could*
      # occur, and a token pair the UI never actually renders is not a defect.
      # RenderedGeometryGate hard-fails the same threshold on pairs it observes rendered,
      # which is the difference between a possibility and a fact.
      def check_token_contrast
        normal_min = @rules.dig("typography", "accessibility", "normal_text_contrast").to_f
        normal_min = 7.0 if normal_min <= 0 # design_rules AAA default

        all_pairs = @tokens.flat_map { |name, dialect| DesignMetrics.token_pairs(name, dialect) } +
                    DesignMetrics.vertical_accent_pairs(@tokens, DesignMetricsGate::RAILS)
        if all_pairs.empty?
          @result.fail("design_metrics contrast: no token pairs resolved from design_tokens.yml", severity: :soft)
          return
        end

        # Only measure colours something paints. Reported rather than dropped
        # quietly: a gate that silently stops counting looks identical to one that
        # was fixed, and this file's own history is a warning about exactly the
        # opposite mistake — vertical accents rendering on social chrome with
        # nothing reporting them.
        # Both sides, not just the foreground. brgen_old_light.text/chrome_bg
        # reported 1.26:1 — which reads as catastrophic until you notice
        # --chrome-bg has no var() consumer left, so that pair measures ink on a
        # surface nothing paints. Checking only the foreground kept it, because
        # --text is read everywhere.
        # Read + wins. "Is the property read" is necessary and not sufficient: a
        # dialect can declare a value, the property can be read everywhere, and a
        # later rule at the same specificity can still overwrite it before it
        # reaches a pixel. social.accent does exactly that in all three apps.
        pairs, unpainted = all_pairs.partition do |p|
          DesignMetrics.token_painted?(DesignMetricsGate::RAILS, p[:fg_key]) &&
            DesignMetrics.token_painted?(DesignMetricsGate::RAILS, p[:bg_key]) &&
            DesignMetrics.token_value_wins?(DesignMetricsGate::RAILS, p[:fg_key], p[:fg]) &&
            DesignMetrics.token_value_wins?(DesignMetricsGate::RAILS, p[:bg_key], p[:bg])
        end
        if unpainted.any?
          skipped = unpainted.select { |p| p[:ratio] < 4.5 }
          # Name the side that has no reader, not the pair's foreground. Listing
          # fg_key alone printed "text, accent, danger" — tokens painted all over
          # the tree — because their *background* was the dead one, which reads as
          # though the gate had lost track of the palette entirely.
          dead = unpainted.flat_map { |p|
            [p[:fg_key], p[:bg_key]].reject { |k| DesignMetrics.token_painted?(DesignMetricsGate::RAILS, k) }
          }.uniq.sort
          # Two different reasons, reported as two. Calling a shadowed token
          # "unread" is the same error this filter was written to stop: --accent is
          # read everywhere and social's value still never lands.
          shadowed = unpainted.flat_map { |p|
            [[p[:fg_key], p[:fg]], [p[:bg_key], p[:bg]]]
              .select { |k, v| DesignMetrics.token_painted?(DesignMetricsGate::RAILS, k) && !DesignMetrics.token_value_wins?(DesignMetricsGate::RAILS, k, v) }
              .map { |k, v| "#{k}=#{v}" }
          }.uniq.sort
          detail = []
          detail << "unread: #{dead.join(', ')}" if dead.any?
          detail << "overridden: #{shadowed.join(', ')}" if shadowed.any?
          @result.warn(
            "design_metrics contrast: skipped #{unpainted.size} pair(s) whose colour never reaches a pixel " \
            "(#{skipped.size} of them below AA) — #{detail.join(' | ')}"
          )
        end
        if pairs.empty?
          @result.fail("design_metrics contrast: every token pair is unread — the palette paints nothing",
                       severity: :soft)
          return
        end

        below_aa = pairs.select { |p| p[:ratio] < 4.5 }
        below_aaa = pairs.select { |p| p[:ratio] >= 4.5 && p[:ratio] < normal_min }

        below_aa.sort_by { |p| p[:ratio] }.each do |pair|
          suggestion = DesignMetrics.suggest_contrast_fix(pair[:fg], pair[:bg], 4.5)
          hint = suggestion ? " — #{pair[:fg_key]} #{suggestion[:hex]} would reach #{suggestion[:ratio]}" : ""
          @result.fail(
            "design_metrics contrast: #{pair[:label]} #{pair[:fg]} on #{pair[:bg]} = #{pair[:ratio]} < 4.5 (WCAG AA)" \
            "#{hint} principle=accessibility",
            severity: :soft
          )
        end

        if below_aaa.any?
          @result.warn(
            "design_metrics contrast: #{below_aaa.size} pair(s) between 4.5 and the design_rules AAA target " \
            "#{normal_min} — #{below_aaa.sort_by { |p| p[:ratio] }.first(3).map { |p| "#{p[:label]}=#{p[:ratio]}" }.join(', ')}"
          )
        end
        @result.warn("design_metrics contrast: enumerated #{pairs.size} mode-matched token pairs " \
                     "across #{@tokens.keys.size} dialects (#{below_aa.size} below AA)")
        judge_contrast_budget(below_aa.size, below_aaa.size)
      end

      # Soft failures are warnings unless GATE_STRICT_SOFT is set, so 30 pairs under
      # WCAG AA sat under a green line indefinitely. A ceiling makes the number
      # monotone without going red on arrival — the same trade constitutional_budget
      # and css_budget make.
      def judge_contrast_budget(below_aa, below_aaa)
        budget = contrast_budget
        return @result.warn("design_metrics contrast: no ceiling recorded in css_budget.yml") if budget.empty?

        {
          "contrast_below_aa" => below_aa,
          "contrast_below_aaa" => below_aaa,
        }.each do |key, count|
          ceiling = budget[key]
          next if ceiling.nil?

          if count > ceiling
            @result.fail("design_metrics #{key}: #{count} exceeds ceiling #{ceiling} (+#{count - ceiling}) — " \
                         "raise the contrast, or record a new ceiling with a reason")
          elsif count < ceiling
            @result.warn("design_metrics #{key}: #{count}, under its #{ceiling} ceiling (-#{ceiling - count})")
          end
        end
      end

      def contrast_budget
# Relative to the gates root, not to __dir__: this method moved one
# directory deeper in the split and a path anchored on __dir__ silently
# became gates/lib/data/css_budget.yml, which does not exist. It failed
# the way this kind of thing does — not an exception, a rescue that
# logged "rules unreadable" and ran the gate unbudgeted, so the contrast
# ceiling stopped being enforced while the gate still reported ok.
path = File.expand_path("../data/css_budget.yml", __dir__)
        (YAML.safe_load_file(path)&.dig("rules") || {}).slice("contrast_below_aa", "contrast_below_aaa")
      rescue StandardError => e
        warn "design_metrics: rules unreadable (#{e.class}) — gate runs unbudgeted"
        {}
      end
    end
  end
end
