# frozen_string_literal: true

module MASTER
  module Metz
    # Sandi Metz Rules:
    # 1. Classes can be no longer than 100 lines
    # 2. Methods can be no longer than 5 lines
    # 3. Pass no more than 4 parameters
    # 4. Controllers can instantiate only one object

    def self.check_file(filepath)
      content = File.read(filepath)
      results = []
      
      # Check class lengths
      content.scan(/class\s+(\w+).*?(?=\nclass\s|\nmodule\s|\z)/m).each do |match|
        class_name = match[0]
        class_body = match[0]
        lines = class_body.lines.count
        if lines > 100
          results << { rule: "class_length", class: class_name, lines: lines, max: 100 }
        end
      end
      
      # Check method lengths
      content.scan(/def\s+(\w+).*?\n\s*end/m).each do |match|
        method_name = match[0]
        method_body = match[0]
        lines = method_body.lines.count
        if lines > 5
          results << { rule: "method_length", method: method_name, lines: lines, max: 5 }
        end
      end
      
      # Check parameter counts
      content.scan(/def\s+\w+\((.*?)\)/).each do |match|
        params = match[0].split(',').length
        if params > 4
          results << { rule: "parameter_count", params: params, max: 4 }
        end
      end
      
      results
    end

    def self.check_code(code)
      results = []
      lines = code.lines.count
      
      if lines > 100
        results << { rule: "code_block_length", lines: lines, max: 100 }
      end
      
      results
    end

    def self.score(violations)
      return 1.0 if violations.empty?
      
      # Deduct points per violation type
      deductions = violations.map do |v|
        case v[:rule]
        when "class_length" then 0.2
        when "method_length" then 0.1
        when "parameter_count" then 0.1
        when "code_block_length" then 0.15
        else 0.05
        end
      end.sum
      
      [0.0, 1.0 - deductions].max
    end
  end
end
