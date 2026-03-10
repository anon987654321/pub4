require_relative "../analyzer"

module MASTER
  module Analyzers
    Duplication = lambda do |code|
      lines = code.lines
      seen = {}
      dupes = []

      lines.each do |l|
        seen[l] ||= 0
        seen[l] += 1
        dupes << l if seen[l] == 2
      end
      dupes
    end

    Analyzer.register(:duplication, Duplication)
  end
end
