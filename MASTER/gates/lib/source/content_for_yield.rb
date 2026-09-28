# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Every view-owned content_for value must have a consumer in the layout that
  # renders that view. content_for without a matching yield is valid Rails, but
  # it is also perfectly valid dead code: the view fills a slot nobody reads.
  class ContentForYieldGate
    ROOT = File.expand_path("../../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    PRODUCER = /content_for\s*(?:\(\s*)?:([a-zA-Z_][a-zA-Z0-9_]*)|content_for\s*(?:\(\s*)?["']([a-zA-Z_][a-zA-Z0-9_]*)["']/
    CONSUMER = /yield\s*(?:\(\s*)?:([a-zA-Z_][a-zA-Z0-9_]*)|yield\s*(?:\(\s*)?["']([a-zA-Z_][a-zA-Z0-9_]*)["']|content_for\s*\(\s*:([a-zA-Z_][a-zA-Z0-9_]*)\s*\)/
    
    def self.run(root: ROOT)
      new(root:).run
    end

    def initialize(root:)
      @root = root
      @rails = File.join(root, "RAILS")
    end

    def run
      @result = GateResult.new
      APPS.each { |app| check_app(app) }
      @result
    end

    private

    def check_app(app)
      producer_files = view_files(app)
      producer_keys = producer_files.flat_map do |path|
        File.read(path).scan(PRODUCER).flat_map { |one, two| [one, two].compact }
      end.uniq

      consumers = layout_files(app).map { |path| File.read(path) }.join("\n")
      consumer_keys = consumers.scan(CONSUMER).flat_map { |one, two, three| [one, two, three].compact }.uniq

      producer_keys.each do |key|
        @result.checked!
        next if consumer_keys.include?(key)

        @result.fail("content_for_yield: #{app} produces :#{key} but no layout consumes it")
      end
    end

    def view_files(app)
      roots = [ File.join(@rails, app, "app", "views") ]
      if app == "brgen"
        roots.concat(Dir.glob(File.join(@rails, "brgen", "engines", "*", "app", "views")))
      end

      roots.flat_map do |root|
        Dir.glob(File.join(root, "**", "*.{erb,html}")).reject do |path|
          path.include?("/layouts/")
        end
      end
    end

    def layout_files(app)
      roots = [ File.join(@rails, app, "app", "views", "layouts") ]
      if app == "brgen"
        roots.concat(Dir.glob(File.join(@rails, "brgen", "engines", "*", "app", "views", "layouts")))
      end

      roots.flat_map { |root| Dir.glob(File.join(root, "**", "*.{erb,html}")) }
    end
  end
end
