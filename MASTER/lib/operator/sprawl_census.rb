# frozen_string_literal: true

# Shape census over every tracked file in all three governed trees. The tree's shape is
# conduct: a directory bought for one file, a name that repeats its parent, a
# name that says nothing, and a path deeper than its neighbours all cost a
# reader something. FILE_SPRAWL in the scan registry measures the first two for
# MASTER's .rb files only, and skips law/, core/ and test/ besides. This
# is the same law over the whole repo and every file type.
#
#   ruby MASTER/tools/sprawl_census.rb            # counts against the ceilings
#   ruby MASTER/tools/sprawl_census.rb --list     # what was counted, per kind
#   ruby MASTER/tools/sprawl_census.rb --ratchet  # record a new low
#
# Mandated paths are excluded rather than priced, because they can never fall:
# Zeitwerk resolves a constant FROM its path, so engines/dating/app/services/
# dating/ is the depth Rails requires and lib/io/base.rb is named after the
# constant it defines. Everything else is counted, the way dup_census counts the
# per-app error pages it cannot collapse -- the ceiling prices what is here, and
# the next one that arrives is a +1 nobody has to notice by hand.
#
# The uncalibrated version of this file called 130 RAILS paths too deep and 26
# names vague. Both were the rule misreading correct markup, which is the same
# way 596 of 981 design findings died. Check a class against a real file before
# adding it.

require "yaml"
require "digest"
require "open3"

module Operator
  module SprawlCensus
    ROOT = File.expand_path("../../..", __dir__)
    CEILINGS = File.join(ROOT, "MASTER", "data", "spine.yml")

    MANDATED = [
      # Zeitwerk reads the namespace off the path, so the nesting IS the name.
      %r{/engines/[^/]+/(?:app|test)/[^/]+/[^/]+/},
      %r{/engines/[^/]+/lib/[^/]+/(?:engine|version)\.rb\z},
      # Rails loads these by location, not by reference.
      %r{/db/(?:migrate|[a-z]+_migrate)/},
      %r{/config/(?:environments|initializers|locales)/},
      %r{/app/(?:channels|controllers|helpers|jobs|mailers|models|reflexes|views|javascript|assets|services|policies|serializers)/},
      # rails test:system globs test/system; a hoist lands the file in the unit
      # suite (DEFAULT_TEST_EXCLUDE misses it) and drops it from test:system.
      %r{/test/system/},
      %r{/(?:bin|lib/tasks|public|storage|log|vendor|node_modules|knowledge|output)/},
      # The locale code and the daemon's config name are not ours to choose.
      %r{/locales/[a-z]{2}(?:-[A-Z]{2})?\.yml\z},
      %r{\.(?:conf|lock|sample|keep|gitkeep|woff2|png|ico|onnx)\z},
      # A tool owns its own dotfolder. .claude/ holds one tracked file because
      # settings.local.json is per-machine and ignored, which is Claude Code's
      # shape, not ours to flatten.
      %r{\A/\.[a-z]+/},
    ].freeze

    # A name that says nothing on its own, in a stack trace or a diff.
    VAGUE = %w[base common shared misc util utils helper helpers main data
               stuff extras things new old temp tmp code lib].freeze
    # Structural anchors only: each governed tree keeps its own base contract.
    # These names do not replace any tree's authority; they catch accidental deletion
    # of the front door while leaving Rails and OpenBSD free to keep their own shape.
    BASE_TREE_ANCHORS = {
      "MASTER" => %w[AGENTS.md data/soul.yml data/rules.yml bin/operator bin/check],
      "RAILS" => %w[CLAUDE.md shared/README.md shared/design_tokens.yml apps.yml],
      "OPENBSD" => %w[CLAUDE.md PATH_OWNERSHIP.yml data/operator.yml bin/check],
    }.freeze

    def base_tree_findings
      BASE_TREE_ANCHORS.flat_map do |tree, paths|
        paths.filter_map do |path|
          "#{tree}/#{path}" unless File.file?(File.join(ROOT, tree, path))
        end
      end
    end


    module_function

    def tracked(root: ROOT)
      root = File.expand_path(root)
      return @tracked ||= git_tracked(ROOT) if root == ROOT

      git_tracked(root)
    end

    def git_tracked(root)
      out, status = Open3.capture2e("git", "-C", root, "ls-files", "-z")
      raise "sprawl_census: git ls-files failed: #{out}" unless status.success?

      out.split("\0")
        .reject { |f| MANDATED.any? { |re| "/#{f}".match?(re) } }
        .select { |f| File.file?(File.join(root, f)) }
    end

    # A directory holding one file and no subdirectories is a namespace bought
    # for nothing — unless a `.rb` of the same name sits beside it, which is how
    # Zeitwerk spells a nested constant. `RepoEcology::CoChangeGraph` can only
    # live at `repo_ecology/co_change_graph.rb`, next to `repo_ecology.rb`, so the
    # directory buys the nesting the constant already had when it was inline;
    # flattening it to `RepoEcologyCoChangeGraph` is a worse name, not less
    # sprawl. The shape comes from splitting a god class, and no lone directory
    # that predates it is forgiven by the exemption.
    def lone_dirs(root: ROOT)
      tracked(root:).group_by { |f| File.dirname(f) }
             .select { |dir, files| files.size == 1 && dir != "." && Dir.glob(File.join(root, dir, "*/")).empty? }
             .reject { |dir, _| File.file?(File.join(root, "#{dir}.rb")) }
             .values.flatten.sort
    end

    # A repeated word is not automatically a stutter. dilla/dilla.rb is the tool
    # named after its folder and reads correctly at a command line, and
    # law/law.rb is how Ruby finds the Law namespace. entry_point? below is
    # what separates those from a file that says the name twice over.
    def stutter(root: ROOT)
      tracked(root:).select do |f|
        parts = f.split("/")
        next false unless parts.size >= 2
        next false unless File.basename(f, File.extname(f)) == parts[-2]

        !entry_point?(f, root:)
      end.sort
    end

    def entry_point?(path, root: ROOT)
      full = File.join(root, path)
      return true if File.executable?(full)
      return true if path.end_with?(".sh", ".yml", ".toml")

      # The repeated word is only a stutter when the file says it twice: once
      # for the namespace and again for the thing inside it, which is how
      # lib/cli/session.rb comes to hold Master::CLI::Session. Said once, it is a module
      # root and how Ruby finds the namespace at all -- law/law.rb declares Law.
      # Said not at all, the file is a script and its folder is named after the
      # tool, which is `ruby MASTER/tools/dilla/dilla.rb` reading correctly.
      name = File.basename(path, File.extname(path))
      File.read(full).scan(/^\s*(?:module|class)\s+#{Regexp.escape(name)}\b/i).size < 2
    rescue ArgumentError
      true
    end

    def vague_names(root: ROOT)
      tracked(root:).select { |f| VAGUE.include?(File.basename(f, File.extname(f))) }.sort
    end

    TEXT_EXTENSIONS = %w[.rb .rake .js .mjs .scss .css .erb .html .md .yml .yaml .json .txt .conf .sh].freeze
    DEEP_PATH = 5
    DUPLICATE_MAX_BYTES = 1_048_576
    SHAPE_MEMBER_LIMIT = 16

    def tree_files(tree, root: ROOT)
      prefix = "#{tree}/"
      tracked(root:).select { |path| path.start_with?(prefix) }
    end

    def tree_directories(tree, root: ROOT)
      tree_files(tree, root:).flat_map do |path|
        parts = path.split("/")
        (1...parts.length).map { |index| parts[0...index].join("/") }
      end.uniq.sort
    end

    def lone_dirs_for(tree, root: ROOT)
      base = "#{tree}/"
      lone_dirs(root:).select { |path| path.start_with?(base) }
    end

    def stutter_for(tree, root: ROOT)
      base = "#{tree}/"
      stutter(root:).select { |path| path.start_with?(base) }
    end

    def vague_names_for(tree, root: ROOT)
      base = "#{tree}/"
      vague_names(root:).select { |path| path.start_with?(base) }
    end

    def deep_paths_for(tree, root: ROOT)
      tree_files(tree, root:).select do |path|
        path.count("/") >= DEEP_PATH
      end
    end

    # Exact content duplication is evidence, never a deletion verdict. A pair can
    # still have different loading semantics, so /fix must prove the chosen operation.
    def duplicate_groups_for(tree, root: ROOT)
      files = tree_files(tree, root:).select do |path|
        TEXT_EXTENSIONS.include?(File.extname(path).downcase) &&
          File.size?(File.join(root, path)).to_i <= DUPLICATE_MAX_BYTES
      end
      files.group_by do |path|
        Digest::SHA256.file(File.join(root, path)).hexdigest
      end.values.select { |group| group.size > 1 }.sort_by { |group| [-group.size, group.first] }
    rescue StandardError => e
      warn "sprawl_census: duplicate scan failed for #{tree}: #{e.class}: #{e.message}"
      []
    end

    def shape(tree, root: ROOT)
      files = tree_files(tree, root:)
      lone = lone_dirs_for(tree, root:)
      repeated = stutter_for(tree, root:)
      vague = vague_names_for(tree, root:)
      duplicates = duplicate_groups_for(tree, root:)
      deep = deep_paths_for(tree, root:)
      members = [
        *lone.map { |path| { path:, rule: "LONE_DIRECTORY", message: "one-file directory candidate" } },
        *repeated.map { |path| { path:, rule: "STUTTER", message: "directory and file repeat the same name" } },
        *vague.map { |path| { path:, rule: "VAGUE_NAME", message: "name says little on its own" } },
        *deep.map { |path| { path:, rule: "DEEP_PATH", message: "unusually deep path candidate" } },
        *duplicates.flat_map { |group| group.map { |path| { path:, rule: "DUPLICATE_CONTENT", message: "exact content duplicate group", related: group } } },
      ].uniq { |row| [row[:rule], row[:path]] }.first(SHAPE_MEMBER_LIMIT)
      {
        files: files.size,
        directories: tree_directories(tree, root:).size,
        lone_dirs: lone.size,
        stutter: repeated.size,
        vague_names: vague.size,
        duplicate_groups: duplicates.size,
        deep_paths: deep.size,
        members: members,
      }
    end

    # A census that reads nothing reports nothing and passes. MASTER/tools gate did
    # exactly that for the length of a worktree: VENDORED matched the absolute
    # path, every file was excluded, and it announced inconclusive rather than
    # failing. corpus is the floor -- the size the last ratchet saw -- so a
    # collapsed corpus refuses instead of reporting a clean tree.
    def corpus_floor = ceilings.fetch("corpus", 0)

    def check_corpus!
      n = tracked.size
      return n if n.positive? && n >= corpus_floor / 2

      abort("sprawl_census: read #{n} tracked files against a floor of #{corpus_floor} — " \
            "the corpus collapsed, so nothing below this line measured the tree")
    end

    def counts
      { "lone_dirs" => lone_dirs.size, "stutter" => stutter.size, "vague_names" => vague_names.size }
    end

    def ceilings
      return {} unless File.exist?(CEILINGS)

      YAML.safe_load_file(CEILINGS).fetch("spine", {}).fetch("sprawl_census", {})
    end

    def run(ratchet: false, list: false)
      check_corpus!
      now = counts
      missing = base_tree_findings
      missing.each { |path| warn "sprawl_census: base tree anchor missing #{path}" }
      return 1 if missing.any?

      recorded = ceilings
      now.each { |k, v| puts "sprawl_census: #{k} #{v} (ceiling #{recorded.fetch(k, v)})" }
      return list_members if list

      over = now.select { |k, v| v > recorded.fetch(k, v) }
      if ratchet && now.any? { |k, v| v < recorded.fetch(k, v) }
        merged = recorded.merge(now) { |_, old, new| [old, new].min }
        source = File.read(CEILINGS)
        values = merged.merge("corpus" => tracked.size)
        block = "  sprawl_census:\n" + values.sort_by { |key, _| key.to_s }.map { |key, value| "    " + key.to_s + ": " + value.to_s + "\n" }.join
        if source.include?("\n  sprawl_census:\n")
          source = source.sub(/\n  sprawl_census:\n(?:    [^\n]+\n)*/, "\n" + block)
        else
          source = source.sub(/^spine:\n/, "spine:\n" + block)
        end
        File.write(CEILINGS, source)
        puts "sprawl_census: recorded a new low"
        return 0
      end
      return 0 if over.empty?

      over.each { |k, v| puts "sprawl_census: #{k} rose to #{v} from #{recorded.fetch(k)} — flatten it, name it, or price the ceiling" }
      1
    end

    def list_members
      %w[MASTER RAILS OPENBSD].each do |tree|
        current = shape(tree)
        puts "\n#{tree}"
        %i[files directories lone_dirs stutter vague_names duplicate_groups deep_paths].each do |key|
          puts "  #{key}: #{current.fetch(key)}"
        end
        current[:members].each do |member|
          related = Array(member[:related]).first(3).join(", ")
          suffix = related.empty? ? "" : " [#{related}]"
          puts "  #{member[:rule]} #{member[:path]} — #{member[:message]}#{suffix}"
        end
      end
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Operator::SprawlCensus.run(ratchet: ARGV.include?("--ratchet"), list: ARGV.include?("--list"))
end
