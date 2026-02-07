# frozen_string_literal: true

module MASTER
  # Converge - Low-level convergence detection
  module Converge
    extend self

    MAX_ITERATIONS = 10
    DIFF_THRESHOLD = 0.02

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
            status: 'converged',
            hash: current_hash
          })
        end

        prev_hash = current_hash
        yield(iteration, current_hash) if block_given?
      end
    end

    def content_hash(path)
      require 'digest'
      files = Dir.glob(File.join(path, 'lib', '**', '*.rb'))
      content = files.sort.map { |f| File.read(f) rescue '' }.join
      Digest::SHA256.hexdigest(content)
    end

    def change_ratio(hash1, hash2)
      return 0.0 if hash1 == hash2
      # Simple: if hashes differ, assume 100% change
      # For real diff ratio, would need content comparison
      1.0
    end

    def audit(current_path, compare_ref: 'HEAD~5')
      current = extract_features(current_path)
      
      {
        current_count: current.size,
        features: current
      }
    end

    private

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
