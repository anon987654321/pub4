# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "tree_sprawl"

module Master
  module Fix
  # Asks for simpler tree layouts, ranking them by legibility and ownership
  # rather than rewarding the smallest sketch or the fewest files alone.
  # Triggered manually via /propose-tree or by the bus on fix_loop:clean|plateau.
    class ProposeTree
      OUT_PATH = "runtime/proposals.md"
      DRAFT_N = 10
      KEEP_TOP = 3
      COOLDOWN_SECS = 86_400

      def initialize(root:, agent:, event_bus: nil)
        @root = root
        @agent = agent
        @bus = event_bus
      end

      def call(n: DRAFT_N)
        return cooldown_message if cooling_down?

        tree = current_tree
        response = @agent.ask(prompt(tree, n))
        proposals = parse(response)
        return "propose-tree: parse failed" if proposals.empty?

        top = rank(proposals).first(KEEP_TOP)
        write_report(top, proposals.size)
        @bus&.publish("propose_tree:done", drafted: proposals.size, kept: top.size)
        "propose-tree: drafted #{proposals.size}, kept top #{top.size} → #{OUT_PATH}"
      rescue StandardError => e
        @bus&.publish("propose_tree:error", error: e.message)
        "propose-tree: #{e.message}"
      end

      private

      def out_file = File.join(@root, OUT_PATH)

      def cooling_down?
        File.exist?(out_file) && (Time.now - File.mtime(out_file)) < COOLDOWN_SECS
      end

      def cooldown_message
        mins = ((COOLDOWN_SECS - (Time.now - File.mtime(out_file))) / 60).to_i
        "propose-tree: cooldown — next run in #{mins}m"
      end

      def current_tree
        entries = Dir.glob(File.join(@root, "lib", "*")).sort.flat_map { |e| describe_entry(e) }
        entries.first(120).join("\n")
      end

      def describe_entry(entry)
        return [File.basename(entry)] unless File.directory?(entry)

        subs = Dir.glob(File.join(entry, "*")).sort.map { |f| "  #{File.basename(f)}#{File.directory?(f) ? "/" : ""}" }
        ["#{File.basename(entry)}/", *subs]
      end

      def prompt(tree, n)
        <<~PROMPT
        Propose #{n} radically simplified file/folder layouts for this Ruby project (Master).
        Current lib/ structure:

        #{tree}

        For each proposal return a YAML map with keys: name, summary, wins, costs, sketch.
        - name: kebab-case identifier
        - summary: one line
        - wins: 2-3 lines (pros, separated by " · ")
        - costs: 2-3 lines (cons, separated by " · ")
        - sketch: ASCII tree, ≤18 lines, indented with 2 spaces per level

        Prefer a shallow, legible tree with one clear owner per concept.
        Treat ugly names, concept scatter, deep important concepts and root clutter as
        measurable costs; fewer lines or files is not a quality score by itself.
        Respect PATH_OWNERSHIP.yml, the boot load order, the core fold boundary,
        Zeitwerk contracts and tested public paths. Do not move a protected boundary
        merely to make the sketch smaller. Name require/autoload/external-consumer
        evidence and migration costs for every proposed move.
        Make decisive proposals, but preserve behavior and reversibility. No prose outside YAML.
        Return a YAML array of #{n} entries.
      PROMPT
      end

      def parse(text)
        body = text.sub(/\A.*?(?=^- |\A- )/m, "").sub(/\n```.*\z/m, "").sub(/\A```ya?ml\n/, "")
        data = YAML.safe_load(body, aliases: false)
        data.is_a?(Array) ? data.select { |e| e.is_a?(Hash) && e["name"] } : []
      rescue Psych::Exception => e
        Master::Ground::Swallow.log(e, context: "ProposeTree.parse")
        []
      end

      def rank(proposals)
        proposals.sort_by { |proposal| sketch_score(proposal["sketch"]) }
      end

      def sketch_score(sketch)
        rows = sketch.to_s.lines.filter_map do |line|
          next if line.strip.empty?

          depth = line[/\A\s*/].to_s.length / 2
          name = line.strip.sub(/\A[│├└─|\x60+\-]+\s*/, "").sub(/\/+\z/, "").strip
          [depth, name]
        end
        return [0, 0, 0, 0, 0, 0] if rows.empty?

        child_counts = Hash.new(0)
        stack = []
        rows.each_with_index do |(depth, name), index|
          stack = stack.first(depth)
          parent = stack.last || :root
          child_counts[parent] += 1
          stack << "#{index}:#{name}"
        end

        ugly = rows.count do |_depth, name|
          stem = File.basename(name, File.extname(name))
          TreeSprawl::UGLY_NAME_PATTERN.match?(stem)
        end
        buried = rows.count do |depth, name|
          stem = File.basename(name, File.extname(name))
          depth > TreeSprawl::MAX_CONCEPT_DEPTH && TreeSprawl::IMPORTANT_CONCEPTS.include?(stem)
        end
        too_wide = child_counts.values.count { |count| count > TreeSprawl::WIDE }
        root_clutter = child_counts.fetch(:root, 0) > TreeSprawl::ROOT_FILE_LIMIT ? 1 : 0
        max_depth = rows.map(&:first).max

        [ugly, buried, too_wide, root_clutter, max_depth, rows.size]
      end

      def write_report(top, total)
        FileUtils.mkdir_p(File.dirname(out_file))
        body = ["# tree proposals — #{Time.now.utc.iso8601}", "",
                "drafted: #{total} · kept top: #{top.size}", ""]
        top.each_with_index do |p, i|
          body << "## #{i + 1}. #{p["name"]}" << ""
          body << p["summary"].to_s << ""
          body << "wins: #{p["wins"]}" << "costs: #{p["costs"]}" << ""
          body << "```" << p["sketch"].to_s.rstrip << "```" << ""
        end
        File.write(out_file, body.join("\n"))
      end
    end
  end
end
