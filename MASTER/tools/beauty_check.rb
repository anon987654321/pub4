# frozen_string_literal: true

# Beauty Check: Detects 'Suffocation' (10+ lines without blanks) and 'Double Blanks'.
# Jaggedness is harder to detect via script without a full AST, but we'll focus on the structural.

class BeautyCheck
  def initialize(root)
    @root = root
  end

  def scan
    violations = []
    files = Dir.glob(File.join(@root, "lib/**/*.rb"))

    files.each do |path|
      lines = File.readlines(path)
      
      # Check for Suffocation (10+ lines without a blank line)
      current_block = 0
      lines.each_with_index do |line, idx|
        if line.strip.empty?
          current_block = 0
        else
          current_block += 1
          if current_block >= 10
            violations << { file: path, line: idx + 1, type: :suffocation, message: "Block of #{current_block} lines without blank line" }
          end
        end
      end

      # Check for Double Blanks
      lines.each_with_index do |line, idx|
        if idx > 0 && line.strip.empty? && lines[idx-1].strip.empty?
          violations << { file: path, line: idx + 1, type: :double_blank, message: "Consecutive blank lines" }
        end
      end
    end
    violations
  end
end

if __FILE__ == $0
  root = ARGV[0] || Dir.pwd
  checker = BeautyCheck.new(root)
  results = checker.scan

  if results.empty?
    puts "Beauty check passed! No structural violations found."
    exit 0
  else
    puts "Found #{results.size} violations:"
    results.each do |v|
      puts "#{v[:file]}:#{v[:line]} [#{v[:type]}] #{v[:message]}"
    end
    exit 1
  end
end
