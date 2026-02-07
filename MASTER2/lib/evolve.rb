# frozen_string_literal: true

module MASTER
  # Evolve - Self-improvement workflow
  class Evolve
    MAX_ITERATIONS = 10
    CONVERGENCE_THRESHOLD = 0.02
    PER_FILE_BUDGET = 0.25

    PROTECTED_FILES = %w[
      lib/evolve.rb
      lib/master.rb
      lib/db_jsonl.rb
    ].freeze

    def initialize(llm: LLM, chamber: nil)
      @llm = llm
      @chamber = chamber || Chamber.new(llm: llm)
      @iteration = 0
      @cost = 0.0
      @history = []
    end

    def run(path: MASTER.root, dry_run: true)
      @iteration = 0
      files = find_ruby_files(path)

      files.each do |file|
        break if over_budget?
        next if protected?(file)

        @iteration += 1
        result = improve_file(file, dry_run: dry_run)
        @history << result
      end

      {
        iterations: @iteration,
        cost: @cost,
        files_processed: @history.size,
        improvements: @history.count { |h| h[:improved] },
        history: @history,
      }
    end

    private

    def find_ruby_files(path)
      Dir.glob(File.join(path, "lib", "**", "*.rb")).sort_by { |f| -File.size(f) }
    end

    def protected?(file)
      PROTECTED_FILES.any? { |p| file.end_with?(p) }
    end

    def improve_file(file, dry_run:)
      code = File.read(file)
      return { file: file, skipped: true, reason: "too large" } if code.size > 10_000

      result = @chamber.deliberate(code, filename: File.basename(file))

      if result.ok? && result.value[:final] != code
        File.write(file, result.value[:final]) unless dry_run
        @cost += result.value[:cost]
        { file: file, improved: true, cost: result.value[:cost], dry_run: dry_run }
      else
        { file: file, improved: false, reason: result.err? ? result.error : "no changes" }
      end
    rescue StandardError => e
      { file: file, error: e.message }
    end

    def over_budget?
      @cost >= (MAX_ITERATIONS * PER_FILE_BUDGET)
    end
  end
end
