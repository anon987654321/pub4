# frozen_string_literal: true

module Master
  class Persona
    attr_reader :name, :traits, :style, :focus, :sources, :rules

    def initialize(name:, traits: [], style: nil, focus: nil, sources: [], rules: [])
      @name = name
      @traits = traits
      @style = style
      @focus = focus
      @sources = sources
      @rules = rules
    end

    def self.load_all
      dir = File.join(Master::ROOT, "lib", "personas")
      Dir["#{dir}/*.md"].map { |f| parse(f) }
    end

    def self.load(name)
      path = File.join(Master::ROOT, "lib", "personas", "#{name}.md")
      return nil unless File.exist?(path)
      parse(path)
    end

    def self.parse(path)
      content = File.read(path, encoding: "UTF-8")
      name = File.basename(path, ".md")
      
      traits = content[/traits:\s*\[([^\]]+)\]/, 1]&.split(",")&.map(&:strip) || []
      style = content[/style:\s*(.+)/, 1]&.strip
      focus = content[/focus:\s*(.+)/, 1]&.strip
      
      # Extract sources from ## Sources section
      sources = []
      if content =~ /## Sources\n(.*?)(?=\n##|\z)/m
        sources = $1.scan(/- (.+)/).flatten.map(&:strip)
      end
      
      # Extract rules from ## Rules section
      rules = []
      if content =~ /## Rules\n(.*?)(?=\n##|\z)/m
        rules = $1.scan(/- (.+)/).flatten.map(&:strip)
      end
      
      new(name: name, traits: traits, style: style, focus: focus, sources: sources, rules: rules)
    end

    def to_prompt
      prompt = "PERSONA: #{@name}\n"
      prompt += "TRAITS: #{@traits.join(', ')}\n" if @traits.any?
      prompt += "FOCUS: #{@focus}\n" if @focus
      prompt += "STYLE: #{@style}\n" if @style
      prompt += "SOURCES: #{@sources.join(', ')}\n" if @sources.any?
      prompt += "RULES:\n#{@rules.map { |r| "- #{r}" }.join("\n")}\n" if @rules.any?
      prompt
    end

    def to_s
      "#{@name}: #{@traits.join(', ')}"
    end
  end
end
