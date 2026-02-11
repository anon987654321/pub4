# frozen_string_literal: true

module MASTER
  # Convergence - Detect plateaus, oscillations, and diminishing returns
  # Prevents infinite loops and wasted compute
  # Merged from converge.rb for DRY compliance
  module Convergence
    PLATEAU_WINDOW = 3
    MIN_DELTA = 0.02
    MAX_ITERATIONS = 25
    DIFF_THRESHOLD = 0.02

    class << self
      def track(history, current_metrics)
        history << current_metrics.merge(timestamp: Time.now)
        history.shift if history.size > MAX_ITERATIONS

        {
          iteration: history.size,
          delta: calculate_delta(history),
          plateau: plateau?(history),
          oscillating: oscillating?(history),
          should_stop: should_stop?(history),
          reason: stop_reason(history),
        }
      end

      def calculate_delta(history)
        return 1.0 if history.size < 2

        prev = history[-2]
        curr = history[-1]

        # Calculate improvement across key metrics
        deltas = []
        %i[violations complexity coverage score].each do |metric|
          if prev[metric] && curr[metric] && prev[metric] != 0
            deltas << ((curr[metric] - prev[metric]).abs / prev[metric].to_f)
          end
        end

        deltas.empty? ? 0.0 : deltas.sum / deltas.size
      end

      def plateau?(history)
        return false if history.size < PLATEAU_WINDOW

        recent = history.last(PLATEAU_WINDOW)
        deltas = recent.each_cons(2).map do |a, b|
          score_diff(a, b)
        end

        deltas.all? { |d| d.abs < MIN_DELTA }
      end

      def oscillating?(history)
        return false if history.size < 4

        # Check if metrics are bouncing back and forth
        recent = history.last(4)
        scores = recent.map { |h| h[:score] || h[:violations] || 0 }

        # A-B-A-B pattern detection
        (scores[0] - scores[2]).abs < MIN_DELTA &&
          (scores[1] - scores[3]).abs < MIN_DELTA &&
          (scores[0] - scores[1]).abs > MIN_DELTA
      end

      # Detect if recent diffs are too similar (formatter wars, refactor loops)
      def oscillating_diffs?(history)
        return false if history.size < 4
        return false unless history.last(4).all? { |h| h[:diff] }
        
        recent_diffs = history.last(4).map { |h| h[:diff] }
        
        # Compare first and third, second and fourth
        similarity_03 = diff_similarity(recent_diffs[0], recent_diffs[2])
        similarity_13 = diff_similarity(recent_diffs[1], recent_diffs[3])
        
        # If both pairs are >90% similar, we're oscillating
        similarity_03 > 0.9 && similarity_13 > 0.9
      end

      # Calculate similarity between two diffs (0.0 = completely different, 1.0 = identical)
      def diff_similarity(diff1, diff2)
        return 1.0 if diff1 == diff2
        return 0.0 if diff1.nil? || diff2.nil?
        
        # Levenshtein-based similarity
        max_len = [diff1.length, diff2.length].max
        return 0.0 if max_len == 0
        
        # Require Utils module for Levenshtein - return 0.0 (no similarity) if unavailable
        unless defined?(Utils) && Utils.respond_to?(:levenshtein)
          return 0.0
        end
        
        distance = Utils.levenshtein(diff1, diff2)
        1.0 - (distance.to_f / max_len)
      end

      def should_stop?(history)
        return false if history.empty?

        latest = history.last

        # Success: zero violations
        return true if latest[:violations]&.zero?

        # Plateau: no improvement for PLATEAU_WINDOW iterations
        return true if plateau?(history)

        # Max iterations reached
        return true if history.size >= MAX_ITERATIONS

        # Oscillation detected (score-based)
        return true if oscillating?(history)
        
        # Oscillation detected (diff-based)
        return true if oscillating_diffs?(history)

        false
      end

      def stop_reason(history)
        return nil unless should_stop?(history)

        latest = history.last

        if latest[:violations]&.zero?
          :converged
        elsif history.size >= MAX_ITERATIONS
          :max_iterations
        elsif oscillating?(history)
          :oscillation
        elsif oscillating_diffs?(history)
          :oscillation_diff
        elsif plateau?(history)
          :plateau
        end
      end

      def analyze_oscillation(history)
        return nil unless oscillating?(history)

        recent = history.last(4)
        {
          pattern: recent.map { |h| h[:violations] || h[:score] },
          suggestion: "Try different approach or freeze current state",
          cycles_detected: detect_cycle_length(history),
        }
      end

      def summary(history)
        return "No history" if history.empty?

        first = history.first
        last = history.last
        improvement = if first[:violations] && last[:violations] && first[:violations] > 0
                        ((first[:violations] - last[:violations]) / first[:violations].to_f * 100).round(1)
                      else
                        0
                      end

        "#{history.size} iterations, #{improvement}% improvement, " \
          "#{last[:violations] || 'n/a'} violations remaining"
      end

      private

      def score_diff(a, b)
        sa = a[:score] || (100 - (a[:violations] || 0))
        sb = b[:score] || (100 - (b[:violations] || 0))
        (sb - sa) / [sa.abs, 1].max.to_f
      end

      def detect_cycle_length(history)
        return nil if history.size < 4

        scores = history.map { |h| h[:score] || h[:violations] || 0 }

        (2..history.size / 2).each do |len|
          cycle = scores.last(len * 2)
          first_half = cycle.first(len)
          second_half = cycle.last(len)

          if first_half.zip(second_half).all? { |a, b| (a - b).abs < MIN_DELTA }
            return len
          end
        end

        nil
      end

      # Utility methods merged from Converge module
      
      # Calculate SHA256 hash of all Ruby files in a path
      def content_hash(path)
        require 'digest'
        files = Dir.glob(File.join(path, 'lib', '**', '*.rb'))
        content = files.sort.map { |f| File.read(f) rescue '' }.join
        Digest::SHA256.hexdigest(content)
      end

      # Calculate change ratio between two content states
      # Fixed: Now uses proper diff ratio instead of always returning 1.0
      def change_ratio(content1, content2)
        return 0.0 if content1 == content2
        
        # Use Levenshtein distance for character-level diff
        # For large strings, sample first N chars for efficiency
        max_len = 10_000
        str1 = content1[0, max_len]
        str2 = content2[0, max_len]
        
        distance = Utils.levenshtein(str1, str2)
        max_length = [str1.length, str2.length].max
        return 1.0 if max_length == 0
        
        distance.to_f / max_length
      end

      # Audit current codebase features (classes, modules, methods)
      def audit(path, compare_ref: 'HEAD~5')
        features = extract_features(path)
        {
          current_count: features.size,
          features: features
        }
      end

      # Extract feature signatures from codebase
      def extract_features(path)
        files = Dir.glob(File.join(path, 'lib', '**', '*.rb'))
        features = []

        files.each do |file|
          content = File.read(file) rescue next
          # Extract class/module definitions
          content.scan(/(?:class|module)\s+(\w+)/) { |m| features << m[0] }
          # Extract method definitions
          content.scan(/def\s+(\w+)/) { |m| features << m[0] }
        end

        features.uniq
      end
    end
  end

  # Backward compatibility alias
  Converge = Convergence
end
