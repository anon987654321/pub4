# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "open3"
require "set"
require "time"
require "yaml"


module Master
  module Review
    class RepoEcology
      module CoChangeGraph
        private

        def build_co_change_graph
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "--name-only",
                                        "--pre#{?t}ty=format:#{COMMIT_SEPARATOR}",
                                        "-#{CO_CHANGE_COMMITS}")
          return {} unless status.success?

          count_co_change_pairs(out)
            .then { |pairs| graph_from_counts(pairs) }.transform_values(&:freeze).freeze
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_error", error: e.message)
          {}
        end

        def count_co_change_pairs(out)
          pair_counts = Hash.new(0)
          out.split(COMMIT_SEPARATOR).each do |chunk|
            files = chunk.lines.map(&:strip).reject(&:empty?).uniq
            next if files.size < 2
            files.combination(2) { |a, b| pair_counts[[a, b].sort] += 1 }
          end
          pair_counts
        end

        def graph_from_counts(pair_counts)
          graph = Hash.new { |h, k| h[k] = {} }
          pair_counts.each do |(a, b), count|
            next if count < CO_CHANGE_MIN_COUNT
            graph[a][b] = count
            graph[b][a] = count
          end
          graph
        end

        def load_or_build_co_change_graph
          cached = read_co_change_cache
          return cached if cached

          build_co_change_graph.tap { |graph| write_co_change_cache(graph) }
        end

        def read_co_change_cache
          path = co_change_cache_path
          return unless File.exist?(path)

          data = YAML.safe_load_file(path, aliases: true)
          return unless data.is_a?(Hash) && data["head_mtime"].to_i == git_head_mtime

          thaw_graph(data["graph"] || {})
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
          nil
        end

        def write_co_change_cache(graph)
          path = co_change_cache_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, { "head_mtime" => git_head_mtime, "graph" => graph }.to_yaml)
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
        end

        def thaw_graph(graph)
          graph.each_with_object({}) do |(file, peers), acc|
            acc[file] = (peers || {}).transform_values(&:to_i).freeze
          end.freeze
        end

        def co_change_cache_path
          File.join(@root, CO_CHANGE_CACHE_PATH)
        end

        def git_head_mtime
          File.mtime(File.join(@root, ".git", "HEAD")).to_i
        rescue StandardError
          0
        end
      end
    end
  end
end
module Master
  module Review
    class RepoEcology
      # Converts a computed scan report hash into markdown text — a separate
      # concern from RepoEcology's own file-analysis/detection responsibility.
      module ReportRendering
        def build_scan_report(records, graph)
          {
            root: @root,
            scanned_at: Time.now.utc.iso8601,
            files: records.size,
            score: score(records),
            dead_file_candidates: dead_file_candidates(records),
            dead_method_candidates: dead_method_candidates(records),
            duplicate_basenames: duplicate_basenames(records),
            similar_clusters: similar_clusters(records),
            sprawl: sprawl(records),
            large_files: large_files(records),
            extension_mix: extension_mix(records),
            co_change_pairs: co_change_pairs(graph),
          }
        end

        def render_report_sections(report)
          render_dead_and_duplicate_sections(report) + render_scale_and_coupling_sections(report)
        end

        def render_dead_and_duplicate_sections(report)
          lines = []
          lines.concat(render_section("Dead-file candidates", report[:dead_file_candidates]) do |item|
            "#{item[:path]} — #{item[:reason]}"
          end)
          lines.concat(render_section("Dead-method candidates", report[:dead_method_candidates]) do |item|
            "#{item[:path]}##{item[:method]} — #{item[:reason]}"
          end)
          lines.concat(render_section("Duplicate basenames", report[:duplicate_basenames]) do |item|
            "#{item[:basename]} ×#{item[:count]}: #{item[:paths].first(5).join(', ')}"
          end)
          lines
        end

        def render_scale_and_coupling_sections(report)
          lines = []
          lines.concat(render_section("Similar clusters", report[:similar_clusters]) do |item|
            "#{item[:signature]} ×#{item[:count]}: #{item[:paths].first(5).join(', ')}"
          end)
          lines.concat(render_section("Large files", report[:large_files]) do |item|
            "#{item[:path]} — #{item[:lines]} lines (#{item[:symbol_count]} symbols)"
          end)
          lines.concat(render_section("Co-change pairs (hidden coupling)", report[:co_change_pairs]) do |item|
            "#{item[:a]} ↔ #{item[:b]} (#{item[:count]} commits)"
          end)
          lines
        end

        def render_summary_lines(report)
          sprawl = report[:sprawl]
          [
            "sprawl: max_depth=#{sprawl[:max_depth]}, avg_depth=#{sprawl[:avg_depth]}, " \
            "orphan_dirs=#{sprawl[:orphan_dirs]}",
            "extensions: #{report[:extension_mix].map { |ext, count| "#{ext}=#{count}" }.join(', ')}",
          ]
        end

        def render_section(title, items)
          lines = ["", "## #{title}"]
          if items.empty?
            lines << "none"
          else
            items.first(12).each { |item| lines << "- #{yield(item)}" }
          end
          lines
        end
      end
    end
  end
end

module Master
  module Review
  # RepoEcology converts repo-gardening principles into executable analysis.
  # It never deletes or rewrites; it emits evidence for governed changes.
  # Judge and co-change integrations require council review before activation.
    class RepoEcology
      DEFAULT_IGNORE_DIRS = %w[
        .git .master node_modules vendor tmp log coverage storage .bundle dist build
      ].freeze
      DEFAULT_EXTENSIONS = %w[.rb .js .ts .erb .html .css .scss .yml .yaml .json .md .sh .zsh].freeze
      LARGE_FILE_LINES = 420
      DUPLICATE_BASENAME_LIMIT = 4
      MAX_DEAD_CANDIDATES = 40
      MAX_CLUSTERS = 20
      CO_CHANGE_COMMITS = 200
      MAX_CO_CHANGE_PAIRS = 20
      CO_CHANGE_MIN_COUNT = 2
      COMMIT_SEPARATOR = "===commit===".freeze
      CO_CHANGE_CACHE_PATH = File.join(".master", "co_change_cache.yml").freeze
      FileRecord = Data.define(:path, :full_path, :basename, :dirname, :ext, :bytes, :lines,
                               :symbol_count, :tokens, :digest, :signature, :inbound_refs)

      include CoChangeGraph
      include ReportRendering

      def initialize(root:, event_bus: nil, ignore_dirs: DEFAULT_IGNORE_DIRS, code_index: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @ignore_dirs = ignore_dirs.to_set
        @code_index = code_index
        @co_change_graph = nil
        @graph_mutex = Mutex.new
      end

      # Returns a file => Set<file> adjacency graph built from git co-change history.
      # Edges exist between files that changed together >= CO_CHANGE_MIN_COUNT times.
      # Memoized; call reindex(path) or reset_graph to invalidate.
      def co_change_graph
        @graph_mutex.synchronize { @co_change_graph ||= load_or_build_co_change_graph }
      end

      # Re-parse a single file's symbols in the code_index and invalidate the graph.
      def reindex(path)
        @code_index&.reindex(path)
        @graph_mutex.synchronize { @co_change_graph = nil }
      end

      # Returns a snapshot summary hash for the dmesg boot line.
      def snapshot
        graph = co_change_graph
        symbol_count = @code_index ? (@code_index.size rescue 0) : 0
        file_count = graph.size
        edge_count = graph.values.sum(&:size) / 2
        hotspots = graph.max_by(5) { |_, peers| peers.size }
                        .map { |file, peers| { file:, coupled_to: peers.size } }
        { symbols: symbol_count, files: file_count, edges: edge_count, hotspots: }
      end

      def scan(path: nil)
        base = path ? File.expand_path(path, @root) : @root
        files = collect_files(base)
        records = files.map { |file| analyze_file(file) }
        report = build_scan_report(records, co_change_graph)
        @bus&.publish("repo_ecology:scan", files: records.size, score: report[:score])
        report
      end

      def render(report)
        lines = []
        lines << "# Repo ecology"
        lines << "score: #{report[:score][:grade]} (#{report[:score][:value]}/100)"
        lines << "files: #{report[:files]}"
        lines << ""
        lines.concat(render_report_sections(report))
        lines << ""
        lines.concat(render_summary_lines(report))
        lines.join("\n")
      end

      private

      def collect_files(base)
        return [] unless File.exist?(base)
        files = []
        Find.find(base) do |path|
          name = File.basename(path)
          if File.directory?(path)
            Find.prune if @ignore_dirs.include?(name)
            next
          end
          next unless DEFAULT_EXTENSIONS.include?(File.extname(path).downcase)
          files << path
        end
        files.sort
      end

      def analyze_file(file)
        rel = relative(file)
        content = File.read(file, encoding: "UTF-8", invalid: :replace, undef: :replace)
        tokens = content.downcase.scan(/[a-z][a-z0-9_]{2,}/)
        FileRecord.new(**file_record_fields(file, rel, content, tokens))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "repo_ecology.analyze_file", event_bus: @bus, path: file)
        nil
      end

      def file_record_fields(file, rel, content, tokens)
        {
          path: rel,
          full_path: file,
          basename: File.basename(file),
          dirname: File.dirname(rel),
          ext: File.extname(file).downcase,
          bytes: content.bytesize,
          lines: content.lines.size,
          symbol_count: symbol_count_for(rel),
          tokens:,
          digest: Digest::SHA256.hexdigest(content),
          signature: signature(tokens, rel),
          inbound_refs: 0,
        }
      end

      def symbol_count_for(rel)
        return 0 unless @code_index

        @code_index.symbols_in(rel).size
      rescue StandardError
        0
      end

      def score(records)
        records = records.compact
        penalty = 0
        penalty += duplicate_basenames(records).sum { |item| [item[:count] - DUPLICATE_BASENAME_LIMIT, 0].max * 3 }
        penalty += similar_clusters(records).sum { |item| [item[:count] - 1, 0].max * 4 }
        penalty += large_files(records).size * 2
        penalty += sprawl(records)[:orphan_dirs] * 2
        value = [[100 - penalty, 0].max, 100].min
        { value:, grade: grade_for(value) }
      end

      def grade_for(value)
        return "excellent" if value >= 90
        return "good" if value >= 75
        return "strained" if value >= 55
        "fragmented"
      end

      def dead_file_candidates(records)
        records = records.compact
        corpus = records.map { |record| [record.path, record.tokens.join(" ")] }.to_h
        records.filter_map { |r| dead_candidate(r, corpus) }.first(MAX_DEAD_CANDIDATES)
      end

      # The stem is only half the name. A Zeitwerk caller writes
      # Master::Ground::ContextProvider, which downcases to the single token
      # `contextprovider` — the stem with its underscores gone — so a check for
      # `context_provider` finds nothing and every autoloaded file in the tree
      # reads as dead. Measured 2026-08-27: all forty candidates this produced
      # had live callers, a census that was wrong forty times out of forty.
      def dead_candidate(record, corpus)
        return if protected_path?(record.path)

        stem = File.basename(record.basename, record.ext).downcase
        names = [stem, stem.delete("_")].uniq
        inbound = corpus.count { |path, text| path != record.path && names.any? { |n| text.include?(n) } }
        return unless inbound.zero?
        return if record.lines < 3

        { path: record.path, reason: "no reference by stem or constant", lines: record.lines }
      end

      # Method-level extension of dead_file_candidates: a defined method whose
      # name never occurs as a token in any OTHER file is a dead-code
      # candidate. Same text-reachability heuristic, finer grain — misses
      # metaprogrammed/reflective calls (send, method_missing) by design;
      # those need semantic review, not a false "confirmed dead" claim.
      def dead_method_candidates(records)
        ruby_records = records.compact.select { |r| r.ext == ".rb" && !protected_path?(r.path) }
        corpus = ruby_records.map { |r| [r.path, r.tokens.join(" ")] }.to_h
        ruby_records.flat_map { |r| dead_methods_in(r, corpus) }.first(MAX_DEAD_CANDIDATES)
      end

      DEAD_METHOD_SKIP = %w[
        initialize call to_s to_str to_a to_h to_i to_f inspect eql hash coerce
        respond_to_missing method_missing each build new run perform
      ].to_set.freeze

      def dead_methods_in(record, corpus)
        return [] unless File.exist?(record.full_path)
        source = File.read(record.full_path, encoding: "UTF-8", invalid: :replace, undef: :replace)
        names = source.scan(/^\s*def\s+(?:self\.)?([a-z_][a-zA-Z0-9_]*[?!]?)/).flatten.uniq
        names.reject { |n| DEAD_METHOD_SKIP.include?(n.delete("?!")) }.filter_map do |name|
          # record.tokens never include ?/! (token regex excludes punctuation) —
          # a call site like `x.done?` tokenizes to "done", not "done?".
          bare = name.delete("?!")
          # called elsewhere in its own file — normal for private helpers
          next if record.tokens.count(bare) > 1
          inbound = corpus.count { |path, text| path != record.path && text.include?(bare) }
          next unless inbound.zero?
          { path: record.path, method: name, reason: "no call-site references found in corpus" }
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RepoEcology.dead_methods_in")
        []
      end

      def protected_path?(path)
        path == "README.md" || path == "AGENTS.md" || path.start_with?(".github/") ||
          path.include?("/test/") || path.include?("/spec/") || path.end_with?("Gemfile")
      end

      def duplicate_basenames(records)
        records.compact.group_by(&:basename)
               .filter_map do |basename, group|
          next if group.size < DUPLICATE_BASENAME_LIMIT
          { basename:, count: group.size, paths: group.map(&:path).sort }
        end.sort_by { |item| [-item[:count], item[:basename]] }
      end

      def similar_clusters(records)
        records.compact.group_by(&:signature)
               .filter_map do |sig, group|
          next if sig.empty? || group.size < 2
          next if group.map(&:digest).uniq.size == group.size && group.size < 3
          { signature: sig, count: group.size, paths: group.map(&:path).sort }
        end.sort_by { |item| [-item[:count], item[:signature]] }.first(MAX_CLUSTERS)
      end

      def signature(tokens, rel)
        important = tokens.reject { |token| token.length < 4 || token.match?(/\A\d+\z/) }
        vocabulary = important.tally.sort_by { |token, count| [-count, token] }.first(12).map(&:first)
        return "" if vocabulary.size < 4
        "#{File.extname(rel)}:#{vocabulary.sort.join('-')}"
      end

      def sprawl(records)
        dirs = records.compact.map(&:dirname)
        depths = dirs.map { |dir| dir == "." ? 0 : dir.split(File::SEPARATOR).size }
        counts = dirs.tally
        {
          max_depth: depths.max || 0,
          avg_depth: depths.empty? ? 0 : (depths.sum.to_f / depths.size).round(2),
          orphan_dirs: counts.count { |_dir, count| count == 1 },
        }
      end

      def large_files(records)
        records.compact.select { |record| record.lines >= LARGE_FILE_LINES }
               .map { |record| { path: record.path, lines: record.lines, symbol_count: record.symbol_count } }
               .sort_by { |item| -item[:lines] }
               .first(25)
      end

      def co_change_pairs(graph = co_change_graph)
        pair_counts = Hash.new(0)
        graph.each do |file_a, peers|
          peers.each do |file_b, count|
            key = [file_a, file_b].sort
            pair_counts[key] = count if file_a < file_b
          end
        end
        pair_counts.sort_by { |_, count| -count }
                   .first(MAX_CO_CHANGE_PAIRS)
                   .map { |(a, b), count| { a:, b:, count: } }
      rescue StandardError => e
        @bus&.publish("repo_ecology:co_change_error", error: e.message)
        []
      end

      def extension_mix(records)
        records.compact.map { |record| record.ext.empty? ? "[none]" : record.ext }
               .tally.sort_by { |ext, count| [-count, ext] }.to_h
      end

      def relative(file)
        File.expand_path(file).sub(%r{\A#{Regexp.escape(@root)}/?}, "")
      end
    end
  end
end
