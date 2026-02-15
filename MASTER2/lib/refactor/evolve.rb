# frozen_string_literal: true

module MASTER
  # Evolve - Self-improvement workflow
  class Evolve
    MAX_ITERATIONS = 10
    CONVERGENCE_THRESHOLD = 0.02
    PER_FILE_BUDGET = 0.25

    def initialize(llm: LLM, chamber: nil, staged: false, validation_command: nil, language: :ruby)
      @llm = llm
      @chamber = chamber || Chamber.new(llm: llm)
      @staged = staged
      @validation_command = validation_command
      @language = language
      @iteration = 0
      @cost = 0.0
      @history = []
    end

    def run(path: MASTER.root, dry_run: true)
      @iteration = 0
      @checkpoint = create_safety_checkpoint unless dry_run
      files = find_files(path)

      files.each do |file|
        break if over_budget?

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
        checkpoint: @checkpoint
      }
    end

    private

    # Only evolve lib/ files — bin/, test/, and sbin/ are excluded for safety
    def find_lib_ruby_files(path)
      Dir.glob(File.join(path, "lib", "**", "*.rb")).sort_by { |f| -File.size(f) }
    end

    def find_shell_files(path)
      patterns = ["*.sh", "*.zsh", "*.bash"]
      patterns.flat_map { |p| Dir.glob(File.join(path, "**", p)) }.sort_by { |f| -File.size(f) }
    end

    def find_files(path)
      case @language
      when :shell
        find_shell_files(path)
      else
        find_lib_ruby_files(path)
      end
    end

    def improve_file(file, dry_run:)
      code = File.read(file)
      return { file: file, skipped: true, reason: "too large" } if code.size > 10_000

      # Handle shell scripts with embedded Ruby
      if @language == :shell || shell_file?(file)
        return improve_shell_file(file, code, dry_run: dry_run)
      end

      result = @chamber.deliberate(code, filename: File.basename(file))

      if result.ok? && result.value[:final] != code
        unless dry_run
          if @staged && defined?(Staging)
            # Use staging workflow when enabled
            staging = Staging.new
            stage_result = staging.staged_modify(file, validation_command: @validation_command) do |staged_path|
              File.write(staged_path, result.value[:final])
            end

            unless stage_result.ok?
              return { file: file, improved: false, error: stage_result.error }
            end
          else
            # Default behavior - direct write
            File.write(file, result.value[:final])
          end
        end

        @cost += result.value[:cost]
        { file: file, improved: true, cost: result.value[:cost], dry_run: dry_run }
      else
        { file: file, improved: false, reason: result.err? ? result.error : "no changes" }
      end
    rescue StandardError => e
      { file: file, error: e.message }
    end

    def shell_file?(file)
      %w[.sh .zsh .bash].any? { |ext| file.end_with?(ext) }
    end

    def improve_shell_file(file, code, dry_run:)
      parser = MASTER::Parser::MultiLanguage.new(code, file_path: file)
      parsed = parser.parse

      return { file: file, skipped: true, reason: "no embedded Ruby" } if parsed[:embedded].nil? || parsed[:embedded].empty?

      ruby_blocks = parsed[:embedded][:ruby] || []
      return { file: file, skipped: true, reason: "no Ruby heredocs" } if ruby_blocks.empty?

      # Refactor each Ruby block
      improved_blocks = []
      total_cost = 0.0

      ruby_blocks.each do |block|
        result = @chamber.deliberate(block[:code], filename: "#{File.basename(file)}:#{block[:start_line]}")

        if result.ok? && result.value[:final] != block[:code]
          improved_blocks << { original: block, improved: result.value[:final] }
          total_cost += result.value[:cost]
        end
      end

      if improved_blocks.any?
        # Reconstruct shell script with improved Ruby blocks
        new_code = code.dup
        improved_blocks.reverse.each do |improvement|
          block = improvement[:original]
          new_code = new_code.sub(block[:raw_block]) do
            "<<-#{block[:marker]}\n#{improvement[:improved]}\n#{block[:marker]}"
          end
        end

        unless dry_run
          File.write(file, new_code)
        end

        @cost += total_cost
        { file: file, improved: true, cost: total_cost, dry_run: dry_run, blocks_improved: improved_blocks.size }
      else
        { file: file, improved: false, reason: "no improvements suggested" }
      end
    rescue StandardError => e
      { file: file, error: e.message }
    end

    def create_safety_checkpoint
      return unless system("git rev-parse --git-dir > /dev/null 2>&1")

      tag_name = "evolve_checkpoint_#{Time.now.to_i}"
      success = system("git", "tag", tag_name, out: File::NULL, err: File::NULL)
      success ? tag_name : nil
    end

    def over_budget?
      @cost >= (MAX_ITERATIONS * PER_FILE_BUDGET)
    end
  end
end
