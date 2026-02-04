# frozen_string_literal: true
module Master
  class Principle
    attr_reader :id, :name, :tier, :priority, :smells, :auto_fixable

    def initialize(id:, name:, tier: nil, priority: 5, smells: [], auto_fixable: false)
      @id, @name, @tier, @priority = id, name, tier, priority
      @smells, @auto_fixable = smells, auto_fixable
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
      smells = content[/smells:\s*\[([^\]]+)\]/, 1]&.split(",")&.map(&:strip) || []
      auto_fixable = content.include?("auto_fixable: true")
      new(id: id, name: name, tier: tier, priority: priority, smells: smells, auto_fixable: auto_fixable)
    end

    def to_s = "[#{@id.to_s.rjust(3, '0')}] #{@name}"
  end
end
