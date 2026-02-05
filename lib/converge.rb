# frozen_string_literal: true

module MASTER
  module Converge
    # Convergence detection thresholds
    MAX_ITERATIONS = 10
    DIFF_THRESHOLD = 0.02  # 2% change = converged

    class << self
      def run(path = '.')
        iteration = 0
        prev_hash = nil

        loop do
          iteration += 1
          return Result.err("Max iterations (#{MAX_ITERATIONS}) reached") if iteration > MAX_ITERATIONS

          # Scan and collect issues
          issues = Engine.scan(File.expand_path(path)).value || []

          # Calculate content hash
          current_hash = content_hash(path)

          # Check convergence
          if prev_hash && change_ratio(prev_hash, current_hash) < DIFF_THRESHOLD
            return Result.ok({
              iterations: iteration,
              status: 'converged',
              final_issues: issues.size
            })
          end

          # No issues = converged
          if issues.empty?
            return Result.ok({
              iterations: iteration,
              status: 'clean',
              final_issues: 0
            })
          end

          prev_hash = current_hash
          yield(iteration, issues) if block_given?
        end
      end

      def audit(current_path, compare_ref = 'HEAD~10')
        current_features = extract_features(current_path)
        historical_features = extract_historical_features(compare_ref)

        missing = historical_features - current_features
        added = current_features - historical_features

        {
          current_count: current_features.size,
          historical_count: historical_features.size,
          missing: missing,
          added: added,
          coverage: current_features.size.to_f / [historical_features.size, 1].max
        }
      end

      private

      def content_hash(path)
        files = Dir.glob(File.join(path, '**', '*.rb'))
        content = files.map { |f| File.read(f) rescue '' }.join
        Digest::SHA256.hexdigest(content)
      end

      def change_ratio(old_hash, new_hash)
        # Same hash = no change (0%), different = full change (100%)
        old_hash == new_hash ? 0.0 : 1.0
      end

      def extract_features(path)
        features = Set.new

        Dir.glob(File.join(path, '**', '*.rb')).each do |file|
          content = File.read(file) rescue next
          # Extract method names
          content.scan(/def\s+(\w+)/).each { |m| features << "method:#{m[0]}" }
          # Extract class names
          content.scan(/class\s+(\w+)/).each { |c| features << "class:#{c[0]}" }
          # Extract module names
          content.scan(/module\s+(\w+)/).each { |m| features << "module:#{m[0]}" }
        end

        features.to_a
      end

      def extract_historical_features(ref)
        features = Set.new

        # Get file list from git ref
        files = `git ls-tree -r --name-only #{ref} 2>/dev/null`.lines.map(&:chomp)
        rb_files = files.select { |f| f.end_with?('.rb') }

        rb_files.each do |file|
          content = `git show #{ref}:#{file} 2>/dev/null`
          next if content.empty?

          content.scan(/def\s+(\w+)/).each { |m| features << "method:#{m[0]}" }
          content.scan(/class\s+(\w+)/).each { |c| features << "class:#{c[0]}" }
          content.scan(/module\s+(\w+)/).each { |m| features << "module:#{m[0]}" }
        end

        features.to_a
      rescue
        []
      end
    end
  end
end
