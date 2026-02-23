# frozen_string_literal: true

require "fileutils"
require "json"

module MASTER
  # SelfRefactor — applies MASTER2's own refactor pipeline to its own source.
  # Delegates to Evolve (LLM + Staging) for fixes and Workflow::Convergence
  # for stopping criteria. Identical path to what runs on user code.
  module SelfRefactor
    _c = begin
           require "yaml"
           f = File.expand_path("../../data/constitution.yml", __FILE__)
           YAML.safe_load_file(f).dig("convergence", "max_iterations")
         rescue StandardError
           nil
         end
    MAX_ITERATIONS = (_c || 20).freeze
    RESUME_FILE = File.join(MASTER.root, "var", "self_refactor_resume.json").freeze

    module_function

    # Iterate Evolve over MASTER2's own lib/ until Convergence says stop.
    # Resumes from RESUME_FILE if interrupted (FINISH_FIRST).
    def run(max_iterations: MAX_ITERATIONS)
      evolve  = Evolve.new(staged: true, llm: LLM)
      history = []
      summary, start_iter = resume_state || [{ iterations: 0, improvements: 0, errors: [], stop_reason: nil }, 0]

      max_iterations.times do |idx|
        next if idx < start_iter

        summary[:iterations] = idx + 1
        save_resume_state(summary, idx + 1)

        pass = evolve.run(path: MASTER.root, dry_run: false)
        summary[:improvements] += pass[:improvements].to_i
        summary[:errors].concat(pass[:history].filter_map { |h| h[:error] })

        violations = count_violations
        status = Workflow::Convergence.track(history, { violations: violations, score: pass[:improvements].to_i })
        Logging.dmesg_log("self_refactor", message: "iter #{idx + 1}: #{violations} violations, #{pass[:improvements]} improved") if defined?(Logging)

        if status[:should_stop]
          summary[:stop_reason] = status[:reason]
          break
        end
      end

      summary[:stop_reason] ||= :max_iterations
      clear_resume_state
      Result.ok(summary)
    rescue StandardError => err
      Result.err("SelfRefactor crashed: #{err.message}")
    end

    # Count total violations across all lib/ files using the real enforcer.
    def count_violations
      files = Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
      files.sum do |f|
        code = File.read(f)
        defined?(Review::Enforcer) ? Review::Enforcer.check(code, filename: f)[:violations].size : 0
      rescue StandardError
        0
      end
    end

    def resume_state
      return nil unless File.exist?(RESUME_FILE)

      data = JSON.parse(File.read(RESUME_FILE), symbolize_names: true)
      start_iter = data.delete(:_resume_iter) || 0
      Logging.dmesg_log("self_refactor0", message: "resuming from iteration #{start_iter}") if defined?(Logging)
      [data, start_iter]
    rescue StandardError
      nil
    end

    def save_resume_state(summary, iter)
      FileUtils.mkdir_p(File.dirname(RESUME_FILE))
      File.write(RESUME_FILE, JSON.generate(summary.merge(_resume_iter: iter)))
    rescue StandardError
      nil
    end

    def clear_resume_state
      File.delete(RESUME_FILE) if File.exist?(RESUME_FILE)
    rescue StandardError
      nil
    end
  end
end
