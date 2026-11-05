# frozen_string_literal: true

require "yaml"
require "json"
require "set"
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
      MAX_TREE_ENTRIES = 240
      DirectoryEntry = Struct.new(:path, :files, :bytes, :depth, keyword_init: true)

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
        "propose-tree: drafted #{proposals.size}, kept top #{top.size} -> #{OUT_PATH}"
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
        "propose-tree: cooldown - next run in #{mins}m"
      end

      # Show a bounded recursive inventory, not just one directory level.
      # The summary comes from the same TreeSprawl implementation as /fix.
      def current_tree
        lib_root = File.join(@root, "lib")
        entries = Dir.glob(File.join(lib_root, "**", "*")).sort
        relative_entries = entries.map { |path| path.delete_prefix("#{lib_root}/") }
        files = entries.select { |path| File.file?(path) }
        relative_files = files.map { |path| "lib/#{path.delete_prefix("#{lib_root}/")}" }
        directories = relative_files.group_by { |path| File.dirname(path) }.map do |directory, members|
          relative_directory = directory.delete_prefix("lib").delete_prefix("/")
          depth = relative_directory.empty? ? 0 : relative_directory.count("/") + 1
          DirectoryEntry.new(
            path: directory,
            files: members.size,
            bytes: members.sum { |member| File.size(File.join(@root, member)) },
            depth:
          )
        end
        sizes = relative_files.to_h do |path|
          [path, File.size(File.join(@root, path))]
        end
        sprawl = TreeSprawl.new(files: relative_files, directories:, sizes:, root_prefix: "lib").to_h
        counts = sprawl.transform_values(&:size)

        lines = ["lib/"] + relative_entries.first(MAX_TREE_ENTRIES).map do |path|
          depth = path.count("/") + 1
          "#{ "  " * depth }#{File.basename(path)}#{File.directory?(File.join(lib_root, path)) ? "/" : ""}"
        end
        lines << "  ... #{relative_entries.size - MAX_TREE_ENTRIES} more entries" if relative_entries.size > MAX_TREE_ENTRIES
        ["files=#{relative_files.size} dirs=#{directories.size} sprawl=#{JSON.generate(counts)}", *lines].join("\n")
      end

      def prompt(tree, n)
        <<~PROMPT
        Propose #{n} candidate file/folder layouts for this Ruby project (Master).
        Current recursive lib/ structure and measured sprawl:

        #{tree}

        For each proposal return a YAML map with keys: name, summary, wins, costs, sketch.
        - name: kebab-case identifier
        - summary: one line
        - wins: 2-3 lines (pros, separated by " - ")
        - costs: 2-3 lines (cons, separated by " - ")
        - sketch: ASCII tree, <=18 lines, indented with 2 spaces per level

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
          raw_name = line.strip.sub(/\A[│├└─|\x60+\-]+\s*/, "")
          directory = raw_name.end_with?("/")
          name = raw_name.sub(/\/+\z/, "").strip
          [depth, name, directory]
        end
        return [0, 0, 0, 0, 0, 0, 0] if rows.empty?

        child_counts = Hash.new(0)
        stack = []
        ancestors = []
        rows.each_with_index do |(depth, name, _directory), index|
          stack = stack.first(depth)
          ancestors << stack.dup
          parent = stack.last || :root
          child_counts[parent] += 1
          stack << "#{index}:#{name}"
        end

        ugly = rows.count do |_depth, name, _directory|
          stem = File.basename(name, File.extname(name))
          TreeSprawl::UGLY_NAME_PATTERN.match?(stem)
        end
        owners_by_stem = Hash.new { |hash, stem| hash[stem] = Set.new }
        rows.each_with_index do |(_depth, name, directory), index|
          next if directory || File.extname(name).empty?

          owner = ancestors[index][1] || :root
          owners_by_stem[File.basename(name, File.extname(name))] << owner
        end
        scatter = owners_by_stem.count { |_stem, owners| owners.size >= 3 }
        buried = rows.count do |depth, name, _directory|
          stem = File.basename(name, File.extname(name))
          depth > TreeSprawl::MAX_CONCEPT_DEPTH && TreeSprawl::IMPORTANT_CONCEPTS.include?(stem)
        end
        too_wide = child_counts.values.count { |count| count > TreeSprawl::WIDE }
        root_files = rows.count { |depth, _name, directory| depth == 1 && !directory }
        root_clutter = root_files > TreeSprawl::ROOT_FILE_LIMIT ? 1 : 0
        max_depth = rows.map(&:first).max

        [ugly, scatter, buried, too_wide, root_clutter, max_depth, rows.size]
      end

      def write_report(top, total)
        FileUtils.mkdir_p(File.dirname(out_file))
        body = ["# tree proposals - #{Time.now.utc.iso8601}", "",
                "drafted: #{total} - kept top: #{top.size}", ""]
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
