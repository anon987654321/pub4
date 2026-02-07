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

    def initialize(llm: LLM, chamber: nil, staged: false)
      @llm = llm
      @chamber = chamber || Chamber.new(llm: llm)
      @iteration = 0
      @cost = 0.0
      @history = []
      @staged = staged
      @staging = staged ? Staging.new : nil
    end

    def run(path: MASTER.root, dry_run: true, validation_command: nil)
      @iteration = 0
      files = find_ruby_files(path)

      # If using staged mode, stage all files first
      if @staged
        files.each do |file|
          next if protected?(file)
          result = @staging.stage(file)
          unless result.ok?
            @history << { file: file, error: "staging failed: #{result.error}" }
          end
        end
      end

      files.each do |file|
        break if over_budget?
        next if protected?(file)

        @iteration += 1
        result = improve_file(file, dry_run: dry_run)
        @history << result
      end
      
      # If using staged mode, validate and promote
      if @staged && !dry_run
        handle_staged_promotion(validation_command)
      end

      {
        iterations: @iteration,
        cost: @cost,
        files_processed: @history.size,
        improvements: @history.count { |h| h[:improved] },
        history: @history,
        staged: @staged,
        staging_summary: @staged ? @staging.summary : nil,
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
        # In staged mode, write to staging area; otherwise write directly
        target_file = @staged && !dry_run ? file_in_staging(file) : file
        File.write(target_file, result.value[:final]) unless dry_run
        @cost += result.value[:cost]
        { file: file, improved: true, cost: result.value[:cost], dry_run: dry_run }
      else
        { file: file, improved: false, reason: result.err? ? result.error : "no changes" }
      end
    rescue StandardError => e
      { file: file, error: e.message }
    end
    
    def handle_staged_promotion(validation_command)
      # Validate staged changes
      if validation_command
        validation = @staging.validate(command: validation_command)
      else
        # Default validation: ensure Ruby files parse correctly
        validation = @staging.validate do |staging_dir, files|
          files.each do |file_info|
            next unless file_info[:relative].end_with?('.rb')
            ruby_check = `ruby -c #{file_info[:staged]} 2>&1`
            raise "Syntax error in #{file_info[:relative]}" unless $?.success?
          end
          "All Ruby files parse correctly"
        end
      end
      
      if validation.ok?
        @staging.promote
      else
        @staging.rollback
        @history << { staged_validation: :failed, reason: validation.error }
      end
    end
    
    def file_in_staging(original_path)
      relative = original_path.sub(File.expand_path(".") + "/", "")
      File.join(@staging.class::STAGING_DIR, relative)
    end

    def over_budget?
      @cost >= (MAX_ITERATIONS * PER_FILE_BUDGET)
    end
  end
end
