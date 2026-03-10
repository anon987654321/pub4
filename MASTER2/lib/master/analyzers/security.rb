require_relative "../analyzer"

module MASTER
  module Analyzers
    Security = lambda do |target|
      results = []

      target.each_line do |line|
        if line.include?("eval(")
          results << "dangerous eval detected"
        end
      end
      results
    end

    Analyzer.register(:security, Security)
  end
end
