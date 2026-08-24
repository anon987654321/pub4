# frozen_string_literal: true

module Master
  module Ground
    module Policy
      module Workflow
        Phase = Data.define(:name, :input, :output, :questions, :actions)
        Metric = Data.define(:name, :method, :threshold, :action)

        LIMITS = {
          coverage: 0.8,
          complexity: 10,
          convergence: 0.01,
          iterations: 10,
          coupling: 5,
          duplication: 0.03,
          nesting_depth: 4,
          section_count: 15,
        }.freeze

        PRINCIPLES = [
          %i[dry three_duplications abstract high],
          %i[kiss complexity_over_10 simplify high],
          %i[yagni unused remove medium],
          %i[solid coupling_over_5 decouple critical],
          %i[composition deep_inheritance compose medium],
          %i[evidence assumption validate critical],
          %i[reversible irreversible add_rollback critical],
          %i[explicit implicit make_explicit high],
          %i[orthogonal coupled split high],
          %i[minimalism bloat subtract medium],
          %i[clarity synonym unify medium],
          %i[flatten wrapper flatten high],
          %i[pola surprise make_predictable high],
          %i[unix multi_responsibility one_thing high],
          %i[anti_divitis div_soup semantic_html medium],
          %i[anti_sectionitis scattered_sections consolidate high],
          %i[geometric visual_confusion simplify_geometry medium],
        ].freeze

        PHASES = [
          Phase.new(:discover, :problem, :definition,
                    %w[specific_measurable who_affected_freq current_impact evidence if_nothing], []),
          Phase.new(:analyze, :definition, :analysis,
                    %w[hidden_assumptions could_be_wrong dependencies evidence_support biases], %w[assumptions cost risk bias]),
          Phase.new(:ideate, :analysis, :options,
                    %w[fifteen_approaches persona_suggests challenge_assumptions unconventional simplest], %w[gen_15_alt apply_10_personas synth]),
          Phase.new(:design, :options, :plan,
                    %w[min_viable irreversible test_strategy maintainable], []),
          Phase.new(:implement, :plan, :code,
                    %w[tests_prove edge_cases simplify duplication fail_points], %w[tests_first implement refactor]),
          Phase.new(:validate, :code, :verified,
                    %w[proves_correct breaks missed violated adversarial_finds], %w[check_principles run_gates adversarial]),
          Phase.new(:deliver, :verified, :deployed,
                    %w[deploy_ready docs monitoring rollback], []),
          Phase.new(:learn, :deployed, :knowledge,
                    %w[worked failed differently patterns codify], %w[patterns measure improve codify]),
        ].freeze

        WORKFLOWS = {
          new_feature: %i[discover analyze ideate design implement validate deliver learn],
          bug: %i[analyze implement validate deliver],
          refactor: %i[analyze design implement validate],
          security_fix: %i[analyze implement validate deliver],
          migration: %i[analyze design implement validate deliver],
        }.freeze

        METRICS = [
          Metric.new(:complexity, :cyclomatic, LIMITS[:complexity], :simplify),
          Metric.new(:coupling, :afferent_efferent, LIMITS[:coupling], :decouple),
          Metric.new(:duplication, :token_similarity, LIMITS[:duplication], :extract),
          Metric.new(:coverage, :line, LIMITS[:coverage], :write_tests),
          Metric.new(:nesting, :depth, LIMITS[:nesting_depth], :flatten),
          Metric.new(:sections, :count, LIMITS[:section_count], :consolidate),
        ].freeze

        GATES = {
          functional: { tests: true, coverage: LIMITS[:coverage] },
          secure: { vulnerabilities: 0, input_validation: true },
          maintainable: { complexity: LIMITS[:complexity], duplication: LIMITS[:duplication] },
          access: { wcag: :aaa, lcp: 2.0, inp: 200, cls: 0.1, mobile: true },
          perf: { lcp: 2.5, cls: 0.1, js_kb: 170, total_kb: 2048 },
          deploy: { health: true, rollback: true },
          privacy: { gdpr: true, pii: true },
        }.freeze

        AUTO_FIX = %i[format dead_code typo import space naming].freeze
        CONFIRM = %i[drop_table delete_production force_push rm_rf irreversible_data_change].freeze

        def self.phase(name)
          PHASES.find { |phase| phase.name == name.to_sym }
        end

        def self.workflow(name)
          WORKFLOWS.fetch(name.to_sym, WORKFLOWS[:refactor]).filter_map { |phase_name| phase(phase_name) }
        end

        def self.gates(*names)
          names.flatten.map(&:to_sym).to_h { |name| [name, GATES.fetch(name, {})] }
        end

        def self.confirm?(action)
          CONFIRM.include?(action.to_sym)
        end

        def self.autofix?(action)
          AUTO_FIX.include?(action.to_sym)
        end

        def self.brief(workflow: :refactor)
          phases = workflow(workflow).map(&:name).join(" -> ")
          "Workflow policy: #{workflow} phases #{phases}; gates #{GATES.keys.join(', ')}; hard limits #{LIMITS}."
        end
      end
    end
  end
end
