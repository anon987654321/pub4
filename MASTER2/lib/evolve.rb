# frozen_string_literal: true

module MASTER
  # Evolve - Self-improvement workflow
  class Evolve
    _c = begin
           require "yaml"
           f = File.expand_path("../../data/constitution.yml", __FILE__)
           YAML.safe_load_file(f).dig("convergence", "evolve_max_iterations")
         rescue StandardError
           nil
         end
    MAX_ITERATIONS = (_c || 10).freeze
    CONVERGENCE_THRESHOLD = 0.02
    PER_FILE_BUDGET = 0.25
    MAX_FILE_SIZE = 10_000 # bytes; files larger than this are skipped

    def initialize(llm: LLM, chamber: nil, staged: false, validation_command: nil, language: :ruby)
      @llm = llm
      @chamber = chamber || Council.new(llm: llm)
      @staged = staged
      @validation_command = validation_command
      @language = language
      @iteration = 0
      @cost = 0.0
      @history = []
    end

    def run(path: MASTER.root, dry_run: true)
      Logging.dmesg_log("evolve", message: "ENTER evolve.run")
      @iteration = 0
      @checkpoint = create_safety_checkpoint unless dry_run
      files = find_files(path).reject { |f| File.size(f) > MAX_FILE_SIZE }

      return { iterations: 0, cost: 0, files_processed: 0, improvements: 0, history: [] } if files.empty?

      # Batch all files into a single LLM call -- one request, structured JSON output
      batch_result = batch_improve(files, dry_run: dry_run)
      @history = batch_result
      @iteration = files.size

      {
        iterations: @iteration,
        cost: @cost,
        files_processed: @history.size,
        improvements: @history.count { |h| h[:improved] },
        history: @history,
        checkpoint: @checkpoint,
      }
    end

    private

    def batch_improve(files, dry_run:)
      # Build a single prompt listing all files with their contents
      file_sections = files.map do |f|
        code = File.read(f)
        "### #{File.basename(f)}\n```ruby\n#{code}\n```"
      end.join("\n\n")

      prompt = <<~PROMPT
        Review the following Ruby source files for constitutional violations and style improvements.
        Return a JSON array. Each element: {"file":"basename","improved":true/false,"reason":"...","fixed_code":"...or null if no change"}.
        Apply Strunk & White, ONE_JOB, SIMPLEST_WORKS, FAIL_VISIBLY axioms only.
        Return ONLY the JSON array, no prose.

        #{file_sections}
      PROMPT

      result = LLM.ask(prompt, tier: :strong, stream: false)
      return files.map { |f| { file: f, improved: false, reason: "LLM failed" } } unless result.ok?

      raw = result.value[:content].to_s.strip
                  .gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "")
      begin
        suggestions = JSON.parse(raw)
      rescue JSON::ParserError => e
        Logging.warn("evolve: LLM returned invalid JSON: #{e.message}", subsystem: "evolve") if defined?(Logging)
        return files.map { |f| { file: f, improved: false, reason: "invalid JSON from LLM" } }
      end
      @cost += result.value[:cost].to_f

      suggestions.map do |s|
        file = files.find { |f| File.basename(f) == s["file"] }
        next { file: s["file"], improved: false, reason: "file not found" } unless file

        if s["improved"] && s["fixed_code"] && !dry_run
          clean = TextHygiene.normalize(s["fixed_code"], filename: file)
          File.write(file, clean)
        end

        { file: file, improved: s["improved"] == true, reason: s["reason"], dry_run: dry_run }
      end.compact
    rescue JSON::ParserError => e
      files.map { |f| { file: f, improved: false, reason: "parse error: #{e.message}" } }
    rescue StandardError => e
      files.map { |f| { file: f, improved: false, reason: e.message } }
    end

    # per-file improve kept for shell scripts (embedded Ruby path)
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
      return { file: file, skipped: true, reason: "too large" } if code.size > MAX_FILE_SIZE

      # Handle shell scripts with embedded Ruby
      return improve_shell_file(file, code, dry_run: dry_run) if @language == :shell || shell_file?(file)

      result = @chamber.deliberate(code, filename: File.basename(file))

      if result.ok? && result.value[:final] != code
        unless dry_run
          if @staged && defined?(Staging)
            # Use staging workflow when enabled
            staging = Staging.new
            stage_result = staging.staged_modify(file, validation_command: @validation_command) do |staged_path|
              clean = TextHygiene.normalize(result.value[:final], filename: staged_path)
              File.write(staged_path, clean)
            end

            return { file: file, improved: false, error: stage_result.error } unless stage_result.ok?
          else
            # Default behavior - direct write
            clean = TextHygiene.normalize(result.value[:final], filename: file)
            File.write(file, clean)
          end
        end

        @cost += result.value[:cost]
        { file: file, improved: true, cost: result.value[:cost], dry_run: dry_run }
      else
        { file: file, improved: false, reason: result.err? ? result.error : "no changes" }
      end
    rescue StandardError => err
      { file: file, error: err.message }
    end

    def shell_file?(file)
      %w[.sh .zsh .bash].any? { |ext| file.end_with?(ext) }
    end

    def improve_shell_file(file, code, dry_run:)
      parser = MASTER::Parser::MultiLanguage.new(code, file_path: file)
      parsed = parser.parse

      if parsed[:embedded].nil? || parsed[:embedded].empty?
        return { file: file, skipped: true,
                 reason: "no embedded Ruby" }
      end

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
          clean = TextHygiene.normalize(new_code, filename: file)
          File.write(file, clean)
        end

        @cost += total_cost
        { file: file, improved: true, cost: total_cost, dry_run: dry_run, blocks_improved: improved_blocks.size }
      else
        { file: file, improved: false, reason: "no improvements suggested" }
      end
    rescue StandardError => err
      { file: file, error: err.message }
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
