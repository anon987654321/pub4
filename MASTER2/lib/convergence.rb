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

      def should_stop?(history)
        return false if history.empty?

        latest = history.last

        # Success: zero violations
        return true if latest[:violations]&.zero?

        # Plateau: no improvement for PLATEAU_WINDOW iterations
        return true if plateau?(history)

        # Max iterations reached
        return true if history.size >= MAX_ITERATIONS

        # Oscillation detected
        return true if oscillating?(history)

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

      # Methods merged from converge.rb
      def run(path = MASTER.root)
        iteration = 0
        prev_hash = nil

        loop do
          iteration += 1
          return Result.err("Max iterations reached") if iteration > MAX_ITERATIONS

          current_hash = content_hash(path)

          if prev_hash && change_ratio(prev_hash, current_hash) < DIFF_THRESHOLD
            return Result.ok({
              iterations: iteration,
              status: "converged",
              hash: current_hash
            })
          end

          prev_hash = current_hash
          yield(iteration, current_hash) if block_given?
        end
      end

      def content_hash(path)
        require "digest"
        files = Dir.glob(File.join(path, "lib", "**", "*.rb"))
        content = files.sort.select { |f| File.readable?(f) }.map { |f| File.read(f) }.join
        Digest::SHA256.hexdigest(content)
      end

      def change_ratio(hash1, hash2)
        return 0.0 if hash1 == hash2
        # Simple: if hashes differ, assume 100% change
        # For real diff ratio, would need content comparison
        1.0
      end

      def audit(current_path, compare_ref: "HEAD~5")
        current = extract_features(current_path)
        
        {
          current_count: current.size,
          features: current
        }
      end

      def extract_features(path)
        files = Dir.glob(File.join(path, "lib", "**", "*.rb"))
        features = []

        files.each do |file|
          begin
            content = File.read(file)
            # Extract class/module definitions
            content.scan(/(?:class|module)\s+(\w+)/) { |m| features << m[0] }
            # Extract method definitions
            content.scan(/def\s+(\w+)/) { |m| features << m[0] }
          rescue StandardError
            next
          end
        end

        features.uniq
      end
    end
  end

  # Backward compatibility alias
  Converge = Convergence
end
