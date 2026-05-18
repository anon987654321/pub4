# frozen_string_literal: true

module Master
  module Ground
  class Constitution
    DIR = File.join(Master::ROOT, "data", "principles").freeze
    MAX_PRINCIPLES = 40
    MAX_BODY_CHARS = 320

    def initialize(dir: DIR)
      @dir = dir
      @principles = load
    end

    def empty? = @principles.empty?

    def system_prompt
      return nil if @principles.empty?
      lines = @principles.map { |p| "- #{p[:name]}: #{p[:body]}" }
      "Constitutional principles (operator-declared, override defaults):\n#{lines.join("\n")}"
    end

    def list
      @principles.map { |p| "#{p[:type]}: #{p[:name]} — #{p[:description]}" }
    end

    def reload!
      @principles = load
      self
    end

    YAML_FRONT_MATTER_MARKER = "---".freeze
    YAML_FRONT_MATTER_RE     = /^---\s*$/.freeze

    private

    def load
      return [] unless File.directory?(@dir)
      Dir.glob(File.join(@dir, "*.md")).sort.filter_map { |f| parse(f) }.first(MAX_PRINCIPLES)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "constitution.load", dir: @dir)
      []
    end

    def parse(path)
      raw = File.read(path, encoding: "UTF-8")
      return nil unless raw.start_with?(YAML_FRONT_MATTER_MARKER)
      _, frontmatter, body = raw.split(YAML_FRONT_MATTER_RE, 3)
      meta = YAML.safe_load(frontmatter.to_s) || {}
      {
        name:        meta["name"].to_s,
        description: meta["description"].to_s,
        type:        meta["type"].to_s,
        body:        body.to_s.strip[0, MAX_BODY_CHARS]
      }
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "constitution.parse", path:)
      nil
    end
  end
  end
end
