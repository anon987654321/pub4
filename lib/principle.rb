# frozen_string_literal: true
module Master
  class Principle
    attr_reader :id, :name, :tier, :priority, :smells, :anti_patterns, :auto_fixable

    def initialize(id:, name:, tier: nil, priority: 5, smells: [], anti_patterns: {}, auto_fixable: false)
      @id, @name, @tier, @priority = id, name, tier, priority
      @smells, @anti_patterns, @auto_fixable = smells, anti_patterns, auto_fixable
    end

    def self.load_all
      dir = File.join(Master::ROOT, "lib", "principles")
      files = Dir["#{dir}/*.md"] + Dir["#{dir}/extended/*.md"]
      files.sort.map { |f| parse(f) }
    end

    def self.parse(path)
      content = File.read(path, encoding: "UTF-8")
      name = content.lines.first&.sub(/^#\s*/, "")&.strip || File.basename(path, ".md")
      id = File.basename(path)[/^\d+/].to_i
      tier = content[/tier:\s*(\w+)/, 1]
      priority = content[/priority:\s*(\d+)/, 1]&.to_i || 5
      auto_fixable = content.include?("auto_fixable: true")
      
      # Parse anti-patterns from ### headers
      anti_patterns = {}
      smells = []
      content.scan(/###\s+(\w+)\n(.*?)(?=###|\z)/m) do |smell_name, details|
        smells << smell_name
        smell_text = details.strip
        smell_data = {}
        smell_data[:smell] = smell_text[/\*\*Smell\*\*:\s*(.+)/, 1]
        smell_data[:example] = smell_text[/\*\*Example\*\*:\s*(.+)/, 1]
        smell_data[:fix] = smell_text[/\*\*Fix\*\*:\s*(.+)/, 1]
        anti_patterns[smell_name.to_sym] = smell_data
      end
      
      # Fallback to old format if no ### headers
      if smells.empty?
        smells = content[/smells:\s*\[([^\]]+)\]/, 1]&.split(",")&.map(&:strip) || []
      end
      
      new(id: id, name: name, tier: tier, priority: priority, 
          smells: smells, anti_patterns: anti_patterns, auto_fixable: auto_fixable)
    end

    def to_s = "[#{@id.to_s.rjust(3, '0')}] #{@name}"

    def to_h
      {
        id: @id,
        name: @name,
        tier: @tier,
        priority: @priority,
        smells: @smells,
        anti_patterns: @anti_patterns,
        auto_fixable: @auto_fixable
      }
    end
  end
end
