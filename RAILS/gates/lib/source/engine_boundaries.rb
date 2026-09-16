# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # One brgen vertical reaching into another's constants.
  #
  # Each vertical under brgen/engines is an engine with `isolate_namespace`, and
  # that isolates tables, routes and helpers — not constants. Nothing stops
  # `Dating::Match` from naming `Marketplace::Order`, and once two engines share a
  # model neither can be mounted, tested or removed alone. Packwerk exists to hold
  # this line and brings a C extension through better_html; a text read holds it
  # while the count is one.
  #
  # Comment-only lines are skipped, because the engines cite each other's fixed
  # defects by name in prose, and that is documentation rather than coupling.
  class EngineBoundariesGate
    ROOT = File.expand_path("../../../..", __dir__)
    SOURCE_GLOB = "{app,lib,config,db,test}/**/*.{rb,erb,rake}"
    NAMESPACE = /isolate_namespace\s+([A-Z]\w*)/

    # Engine directory => { relative path => engines it may name }. The courier
    # layer on the maps page plots the viewer's own takeaway orders that are out
    # for delivery, which is a read of another vertical's data by design.
    EXEMPT = {
      "maps" => { "app/controllers/maps/home_controller.rb" => %w[Takeaway] },
    }.freeze

    def self.run(root: ROOT, exempt: EXEMPT)
      new(root:, exempt:).run
    end

    def initialize(root: ROOT, exempt: EXEMPT)
      @root = root
      @exempt = exempt
    end

    def run
      result = GateResult.new
      engines = namespaces
      return result.inconclusive!("engine_boundaries: no isolate_namespace under RAILS/brgen/engines — nothing was read") if engines.empty?

      used = []
      engines.each do |dir, own|
        result.checked!
        foreign = engines.values - [own]
        reference = /(?<![A-Za-z0-9_])(#{foreign.join('|')})::[A-Z]/
        Dir.glob(File.join(engines_root, dir, SOURCE_GLOB)).sort.each do |path|
          rel = path.delete_prefix("#{File.join(engines_root, dir)}/")
          allowed = @exempt.dig(dir, rel) || []
          File.foreach(path).with_index(1) do |line, number|
            next if line.lstrip.start_with?("#", "<%#")

            line.scan(reference).flatten.uniq.each do |other|
              if allowed.include?(other)
                used << [dir, rel, other]
                next
              end

              result.fail("engine_boundaries: #{dir}/#{rel}:#{number} names #{other}:: — " \
                          "#{own} reaches into another engine; go through the host app, or " \
                          "declare the read in EXEMPT with its reason")
            end
          end
        end
      end
      stale_exemptions(used).each do |dir, rel, other|
        result.fail("engine_boundaries: EXEMPT #{dir}/#{rel} => #{other} matches no reference — delete the row")
      end
      result
    end

    private

    def engines_root = File.join(@root, "RAILS", "brgen", "engines")

    # A row whose read has gone excuses the next crossing someone adds to that file.
    def stale_exemptions(used)
      declared = @exempt.flat_map { |dir, files| files.flat_map { |rel, others| others.map { |other| [dir, rel, other] } } }
      declared - used
    end

    def namespaces
      Dir.glob(File.join(engines_root, "*", "lib", "*", "engine.rb")).sort.each_with_object({}) do |path, out|
        name = File.read(path)[NAMESPACE, 1] or next
        out[path.delete_prefix("#{engines_root}/").split("/").first] = name
      end
    end
  end
end
