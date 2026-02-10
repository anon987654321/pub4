require 'fileutils'

module MASTER
  # AutoIterate - Loops refactoring until code quality converges
  # Implements convergence detection and safety limits
  class AutoIterate
    attr_reader :iterations, :scores, :improvements

    def initialize(options = {})
      @max_iterations = options[:max_iterations] || 10
      @max_time = options[:max_time] || 600 # 10 minutes
      @max_cost = options[:max_cost] || 10.0 # $10
      @convergence_threshold = options[:convergence_threshold] || 0.01 # 1%
      @convergence_window = options[:convergence_window] || 3
      @target_score = options[:target_score] || 95
      
      @iterations = 0
      @scores = []
      @improvements = []
      @start_time = Time.now
      @total_cost = 0.0
    end

    # Iterate on a path until convergence
    def self.converge(path, options = {}, &block)
      iterator = new(options)
      iterator.converge(path, &block)
    end

    def converge(path, &block)
      puts "🔄 Starting auto-iteration on #{path}"
      puts "   Max iterations: #{@max_iterations}"
      puts "   Convergence threshold: #{@convergence_threshold * 100}%"
      puts "   Target score: #{@target_score}"
      puts ""

      initial_score = calculate_score(path)
      @scores << initial_score
      
      while should_continue?
        @iterations += 1
        
        iteration_data = run_iteration(path)
        @scores << iteration_data[:score]
        @improvements << iteration_data[:changes]
        
        if block_given?
          yield IterationResult.new(
            number: @iterations,
            score: iteration_data[:score],
            improvements: iteration_data[:changes],
            files_changed: iteration_data[:files_changed],
            elapsed_time: Time.now - @start_time
          )
        end

        # Check convergence conditions
        break if converged?
        break if iteration_data[:score] >= @target_score
        
        sleep 0.5 # Brief pause between iterations
      end

      summary = generate_summary
      puts "\n" + summary
      summary
    end

    private

    def should_continue?
      return false if @iterations >= @max_iterations
      return false if (Time.now - @start_time) >= @max_time
      return false if @total_cost >= @max_cost
      true
    end

    def run_iteration(path)
      puts "📊 Iteration #{@iterations + 1}..."
      
      changes = 0
      files_changed = []
      engine = Engine.new
      
      files = if File.directory?(path)
        Dir.glob(File.join(path, '**', '*.rb'))
      else
        [path]
      end

      files.each do |file|
        next unless File.exist?(file)
        
        begin
          code = File.read(file)
          result = engine.refactor(code)
          
          if result[:success] && result[:code] != code
            # Create backup
            backup_file = "#{file}.iter#{@iterations + 1}.backup"
            FileUtils.cp(file, backup_file)
            
            # Apply changes
            File.write(file, result[:code])
            changes += 1
            files_changed << file
            
            # Track cost if available
            if result[:analysis] && result[:analysis][:cost]
              @total_cost += result[:analysis][:cost]
            end
            
            puts "   ✓ Updated #{file}"
          end
        rescue => e
          puts "   ✗ Error processing #{file}: #{e.message}"
        end
      end

      score = calculate_score(path)
      
      {
        score: score,
        changes: changes,
        files_changed: files_changed
      }
    end

    def calculate_score(path)
      # Calculate a quality score based on various metrics
      # This is a simplified version - in production, would use more sophisticated metrics
      
      total_score = 0
      file_count = 0
      
      files = if File.directory?(path)
        Dir.glob(File.join(path, '**', '*.rb'))
      else
        [path]
      end

      files.each do |file|
        next unless File.exist?(file)
        
        code = File.read(file)
        file_score = 100
        
        # Penalize long files
        lines = code.lines.count
        file_score -= 5 if lines > 500
        file_score -= 10 if lines > 1000
        
        # Penalize long methods
        max_method_length = code.scan(/def\s+\w+.*?^end/m).map { |m| m.lines.count }.max || 0
        file_score -= 5 if max_method_length > 30
        file_score -= 10 if max_method_length > 50
        
        # Penalize complex conditionals
        complex_conditionals = code.scan(/if.*?(\&\&|\|\|).*?(\&\&|\|\|)/).count
        file_score -= complex_conditionals * 2
        
        # Penalize missing documentation
        has_module_docs = code =~ /^# \w+/
        file_score -= 5 unless has_module_docs
        
        total_score += [file_score, 0].max
        file_count += 1
      end

      file_count > 0 ? (total_score.to_f / file_count).round(2) : 0
    end

    def converged?
      return false if @scores.size < @convergence_window + 1
      
      # Check if improvement is less than threshold for convergence_window iterations
      recent_scores = @scores.last(@convergence_window + 1)
      improvements = recent_scores.each_cons(2).map do |a, b|
        if a == 0
          # From 0 to 0: no change; from 0 to non-zero: treat as maximal improvement
          b == 0 ? 0.0 : 1.0
        else
          ((b - a) / a.abs.to_f).abs
        end
      end
      
      improvements.all? { |imp| imp < @convergence_threshold }
    end

    def no_changes_for(window)
      return false if @improvements.size < window
      @improvements.last(window).all?(&:zero?)
    end

    def generate_summary
      summary = []
      summary << "=" * 60
      summary << "Auto-Iteration Complete"
      summary << "=" * 60
      summary << ""
      summary << "Iterations: #{@iterations}"
      summary << "Initial score: #{@scores.first}"
      summary << "Final score: #{@scores.last}"
      summary << "Improvement: #{(@scores.last - @scores.first).round(2)} points"
      summary << "Total changes: #{@improvements.sum}"
      summary << "Elapsed time: #{(Time.now - @start_time).round(2)}s"
      summary << ""
      
      if converged?
        summary << "✓ Converged: Improvements < #{@convergence_threshold * 100}% for #{@convergence_window} iterations"
      elsif @scores.last >= @target_score
        summary << "✓ Target score reached: #{@scores.last} >= #{@target_score}"
      elsif @iterations >= @max_iterations
        summary << "⚠ Stopped: Maximum iterations reached"
      elsif (Time.now - @start_time) >= @max_time
        summary << "⚠ Stopped: Time limit reached"
      elsif @total_cost >= @max_cost
        summary << "⚠ Stopped: Cost limit reached"
      end
      
      summary << ""
      summary << "Score progression: #{@scores.map { |s| s.round(1) }.join(' → ')}"
      summary << "=" * 60
      
      summary.join("\n")
    end
  end

  # Represents the result of a single iteration
  class IterationResult
    attr_reader :number, :score, :improvements, :files_changed, :elapsed_time

    def initialize(number:, score:, improvements:, files_changed:, elapsed_time:)
      @number = number
      @score = score
      @improvements = improvements
      @files_changed = files_changed
      @elapsed_time = elapsed_time
    end

    def no_changes_for(window)
      # This would need to track history across iterations
      # For now, just return false
      false
    end

    def to_s
      "Iteration #{@number}: Score #{@score}/100, #{@improvements} changes"
    end
  end
end
