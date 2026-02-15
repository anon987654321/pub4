# frozen_string_literal: true

module MASTER
  module Utils
    module_function

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def valid_ruby?(code)
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError
      false
    end

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      m = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      (0..a.length).each { |i| m[i][0] = i }
      (0..b.length).each { |j| m[0][j] = j }

      (1..a.length).each do |i|
        (1..b.length).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          m[i][j] = [m[i - 1][j] + 1, m[i][j - 1] + 1, m[i - 1][j - 1] + cost].min
        end
      end

      m[a.length][b.length]
    end

    def similarity(a, b)
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      max_len = [a.length, b.length].max
      1.0 - (levenshtein(a, b).to_f / max_len)
    end
  end
end
