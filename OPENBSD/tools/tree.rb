#!/usr/bin/env ruby
# frozen_string_literal: true

# OPENBSD/tools/tree.rb
#
# Constitution-aware project tree for pub4.
# Respects skip_dirs from MASTER/data/rules.yml + aggressive pruning for overview.
# Usage: ruby tree.rb [root] [--max-depth=3] [--summary]
#
# Shell entry: OPENBSD/tree.sh (operator wrapper for vm23 / local use).

require "yaml"
require "optparse"

class ProjectTree
  DEFAULT_SKIP = %w[
    .git vendor tmp var node_modules .bundle coverage log dist
    knowledge github_repos
    OPENBSD/var RAILS
  ].freeze

  NOISE_SEGMENTS = %w[
    vendor tmp log storage node_modules .bundle coverage dist .master knowledge output
    weights .kamal .cursor .codex .claude sockets pids cache tts_cache
  ].freeze

  def initialize(root:, max_depth: 4, summary: false, overview: false, pillar: nil)
    @root = File.expand_path(root)
    @max_depth = max_depth
    @summary = summary
    @overview = overview
    @pillar = pillar
    @skip = load_skip_dirs
    @skip -= ["RAILS"] if @overview && @pillar != :master
    @counts = Hash.new(0)
  end

  def run
    label = File.basename(@root) + "/"
    puts "#{label} (constitution-aware tree, skips: #{@skip.join(', ')})"
    puts

    walk(@root, "", 0)

    if @summary
      puts
      puts "Summary:"
      puts "  Total files: #{@counts['files']}"
      puts "  Total dirs:  #{@counts['dirs']}"

      if @overview
        case @pillar
        when :pub4 then print_pub4_alignment
        when :master then print_master_alignment
        when :deploy then print_deploy_alignment
        end
      end

      # Special useful breakdown for MASTER work
      if @root.end_with?("MASTER") || File.basename(@root) == "MASTER"
        lib_dir = File.join(@root, "lib")
        if Dir.exist?(lib_dir)
          puts
          puts "  lib/ breakdown (key for KISS/DRY redesign):"
          breakdown_lib(lib_dir)
        end
      end
    end
  end

  def print_pub4_alignment
    puts
    puts "Alignment read (far-away):"
    puts "  ✓ SENSIBLE  4 pillars: OPENBSD (prod), MASTER (agent), bin (CLI), lora (training)"
    puts "  ✓ SENSIBLE  RAILS: 7 apps + shared engine + apps.yml inventory"
    puts "  ✓ SENSIBLE  brgen verticals: dating maps marketplace playlist takeaway tv + social core"
    puts "  ✓ SENSIBLE  MASTER/lib: now judge loop reach ground trace voice (constitutional spine)"
    puts "  ⚠ DRIFT     MASTER/data: ~50 root yml + runtime/ shard — merge target (see START_HERE)"
    puts "  ⚠ DRIFT     OPENBSD + MASTER duplicate DECISIONS/EXAMPLES/REPAIR/DEBT md pairs"
    puts "  ⚠ DRIFT     brgen SCSS: many _vertical_* partials — visual split matches domains (ok)"
    puts "  ✗ NOISE     lora/*.jpg at repo root — move under lora/exports/"
    puts "  → Pillar views: --master-overview | --deploy-overview"
  end

  def print_master_alignment
    puts
    puts "MASTER alignment (far-away):"
    puts "  ✓ SENSIBLE  START_HERE.md is the single orientation doc (agent contract + runtime map)"
    puts "  ✓ SENSIBLE  lib/ spine: now → judge → loop → reach → trace → ground → voice"
    puts "  ✓ SENSIBLE  core/ + kernel/ isolated from lib/ until absorption cutover"
    puts "  ✓ SENSIBLE  data/soul.yml + rules/*.yml shards — law tier, do not blind-merge"
    puts "  ⚠ DRIFT     data/ root: ~45 yml + runtime/ (14 shards) — merge per START_HERE tiers"
    puts "  ⚠ DRIFT     Duplicate MD pairs with OPENBSD: DECISIONS, EXAMPLES, REPAIR, DEBT"
    puts "  ⚠ DRIFT     tools/ + web/ + bin/ — three faces; acceptable but watch overlap"
    puts "  ✗ NOISE     .master/ runtime (cache, tts, melodic) — local-only, never commit"
    puts "  → Deep dive: ruby tree.rb MASTER --master-lib"
  end

  def print_deploy_alignment
    puts
    puts "OPENBSD alignment (far-away):"
    puts "  ✓ SENSIBLE  openbsd/etc + rc.d — production truth for vm23 (relayd, pf, acme)"
    puts "  ✓ SENSIBLE  rails/apps.yml inventory + shared engine — multi-tenant spine"
    puts "  ✓ SENSIBLE  brgen: social core + vertical engines (dating, maps, playlist, tv…)"
    puts "  ✓ SENSIBLE  openbsd/*.rb gates + openbsd/tools/ Ruby helpers; sh/ is shell-only"
    puts "  ✓ SENSIBLE  Gate scripts at rails/*.rb + bin/check* — deploy safety net"
    puts "  ⚠ DRIFT     Duplicate MD pairs with MASTER: DECISIONS, EXAMPLES, REPAIR, DEBT"
    puts "  ⚠ DRIFT     apps.horizon.yml — agent-ignore; keep out of contributor path"
    puts "  ⚠ DRIFT     archive/recovery — legacy pub2/pub3 installers; document-only"
    puts "  ✗ NOISE     rails/node_modules, log/, storage/, app/assets/builds/"
    puts "  → Gates: OPENBSD/bin/check-full | check-rails --profile=contributor"
  end

  def breakdown_lib(lib_root)
    subdirs = Dir.entries(lib_root)
                 .select { |e| !e.start_with?(".") && File.directory?(File.join(lib_root, e)) }
                 .sort

    subdirs.each do |sub|
      full = File.join(lib_root, sub)
      files = Dir.glob(File.join(full, "**/*")).select { |f| File.file?(f) }
      file_count = files.size

      small_file_count = files.count do |f|
        begin
          lines = File.readlines(f).size
          lines <= 30
        rescue StandardError
          false
        end
      end

      line = "    #{sub}/ : #{file_count} files"
      if small_file_count > 5
        line += "  [KISS warning: #{small_file_count} tiny files — strong consolidation candidate]"
      elsif small_file_count > 2
        line += "  (#{small_file_count} small files)"
      end
      puts line
    end
  end

  # Called when --redesign-audit is active
  def redesign_audit
    puts "=== MASTER Redesign Audit (KISS/DENSITY focus) ==="
    puts "Using rules thresholds: small files + fragmented policy dirs are high-priority targets."
    puts

    lib_root = File.join(@root, "lib")
    return unless Dir.exist?(lib_root)

    tiny_files = []

    Dir.glob(File.join(lib_root, "**/*.rb")).each do |file|
      next if should_skip?(file)
      begin
        lines = File.readlines(file).size
        if lines <= 30
          tiny_files << [file.sub(lib_root + "/", ""), lines]
        end
      rescue StandardError
      end
    end

    puts "Tiny files (≤ 30 lines) — strong KISS/DENSITY violation candidates:"
    if tiny_files.any?
      tiny_files.sort_by { |_, l| l }.each do |path, lines|
        puts "  #{path} (#{lines} lines)"
      end
    else
      puts "  (none found in this scan)"
    end

    puts
    puts "Ground/ policy fragmentation check:"
    ground_dir = File.join(lib_root, "ground")
    if Dir.exist?(ground_dir)
      policy_files = Dir.glob(File.join(ground_dir, "*_policy.rb")).size
      puts "  #{policy_files} separate *_policy.rb files in ground/"
      if policy_files > 6
        puts "  → Strong recommendation: Consolidate using Ground::Policy (see recent progress)"
      end
    end

    puts
    puts "now/stages/ check:"
    stages_dir = File.join(lib_root, "now/stages")
    if Dir.exist?(stages_dir)
      stage_files = Dir.glob(File.join(stages_dir, "*.rb")).size
      puts "  #{stage_files} files in now/stages/"
      if stage_files > 8
        puts "  → Good progress with trivial.rb — continue this pattern aggressively."
      end
    end
  end

  private

  def load_skip_dirs
    rules_path = [
      File.join(@root, "data/rules.yml"),
      File.join(@root, "MASTER/data/rules.yml")
    ].find { |p| File.exist?(p) }
    return DEFAULT_SKIP unless rules_path

    begin
      data = YAML.safe_load_file(rules_path, permitted_classes: [Symbol], aliases: true) || {}
      from_yml = data.dig("paths", "skip_dirs") || []
      (from_yml + DEFAULT_SKIP).map(&:to_s).uniq
    rescue StandardError
      DEFAULT_SKIP
    end
  end

  def should_skip?(path)
    rel = path.sub(@root + "/", "")
    return true if noise_path?(rel)
    @skip.any? { |s| rel.start_with?(s) || rel == s }
  end

  LAW_YML = %w[soul.yml rules.yml limits.yml voice.yml style.yml].freeze

  def collapse_data_files(files)
    law = files.select { |f| LAW_YML.include?(f) }.sort
    prose = files.select { |f| f.end_with?(".md", ".jsonl") }.sort
    registries = files - law - prose
    out = prose + law
    out << "[#{registries.size} registry *.yml]" if registries.any?
    out
  end

  def noise_path?(rel)
    parts = rel.split("/")
    return true if parts.any? { |p| NOISE_SEGMENTS.include?(p) }
    return true if rel.include?("public/assets/") || rel.include?("public/packs/")
    return true if rel.include?("app/assets/builds/")

    false
  end

  def depth_limit_for(dir, depth)
    return @max_depth unless @overview

    rel = dir.sub(@root + "/", "")

    case @pillar
    when :master
      return 0 if rel.match?(%r{^data/runtime})
      return 1 if rel == "data" || rel.start_with?("data/")
      return 1 if rel == "lib" || rel.match?(%r{^lib/[^/]+$})
      return 0 if rel == "test" || rel.start_with?("test/")
      return 0 if rel == "spec" || rel.start_with?("spec/")
      return 1 if rel == "tools" || rel.match?(%r{^tools/[^/]+$})
      return 1 if rel == "web" || rel.match?(%r{^web/[^/]+$})
      return 1 if rel == "kernel"
    when :deploy
      return 0 if rel.match?(%r{^rails/[^/]+/app/[^/]+})
      return 1 if rel.match?(%r{^rails/[^/]+/app$})
      return 1 if rel.match?(%r{^rails/[^/]+$})
      return 0 if rel == "rails/test" || rel.start_with?("rails/test/")
      return 1 if rel == "openbsd/etc"
      return 1 if rel.start_with?("openbsd/sh")
      return 1 if rel.start_with?("openbsd/tools")
      return 1 if rel == "archive/recovery"
    end

    # pub4-wide (root = repo) or fallback
    return 0 if rel.match?(%r{^RAILS/[^/]+/app/[^/]+})
    return 1 if rel.match?(%r{^RAILS/[^/]+/app$})
    return 1 if rel.match?(%r{^RAILS/[^/]+$}) && !rel.end_with?("/shared")
    return 1 if rel == "MASTER/data" || rel.start_with?("MASTER/data/runtime")
    return 2 if rel == "MASTER/lib"
    return 1 if rel == "OPENBSD/etc"

    @max_depth
  end

  def walk(dir, prefix, depth)
    limit = depth_limit_for(dir, depth)
    return if depth > limit

    entries = begin
      Dir.entries(dir).sort
    rescue StandardError
      return
    end

    entries.reject! { |e| e.start_with?(".") && !%w[. ..].include?(e) } # hide most dots for clean overview
    entries.reject! { |e| %w[. ..].include?(e) }

    files = []
    dirs = []

    entries.each do |e|
      full = File.join(dir, e)
      next if should_skip?(full)

      if File.directory?(full)
        dirs << e
      else
        files << e
      end
    end

    files = collapse_data_files(files) if @pillar == :master && File.basename(dir) == "data"

    # Print files first (importance order style)
    files.each_with_index do |f, i|
      last = (i == files.size - 1) && dirs.empty?
      branch = last ? "└── " : "├── "
      puts "#{prefix}#{branch}#{f}"
      @counts["files"] += 1
    end

    # Then subdirs
    dirs.each_with_index do |d, i|
      last = i == dirs.size - 1
      branch = last ? "└── " : "├── "
      full_path = File.join(dir, d)
      puts "#{prefix}#{branch}#{d}/"

      @counts["dirs"] += 1

      new_prefix = prefix + (last ? "    " : "│   ")
      walk(full_path, new_prefix, depth + 1)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { max_depth: 4, summary: false, root: nil, focus: nil, overview: false, pillar: nil }

  OptionParser.new do |opts|
    opts.on("--max-depth=N", Integer) { |n| options[:max_depth] = n }
    opts.on("--summary", "Show directory breakdown") { options[:summary] = true }
    opts.on("--focus=WHAT", "Focus on a subdirectory (e.g. lib, MASTER/lib, data)") { |w| options[:focus] = w }
    opts.on("--master-lib", "Convenience: deep focused view of MASTER/lib (best for redesign work)") do
      options[:focus] = "lib"
      options[:max_depth] = 7
      options[:summary] = true
    end
    opts.on("--stages-hotspots", "Show small-file hotspots specifically in now/stages (KISS target)") do
      options[:root] = File.join(Dir.pwd, "MASTER/lib/now/stages")
      options[:max_depth] = 1
      options[:summary] = true
    end
    opts.on("--ground-policies", "Focus on ground/ policy files (common duplication area)") do
      options[:root] = File.join(Dir.pwd, "MASTER/lib/ground")
      options[:max_depth] = 2
      options[:summary] = true
    end
    opts.on("--redesign-audit", "Deep audit mode: highlight KISS/DENSITY problems (small files, fragmented dirs) using rules thresholds") do
      options[:max_depth] = 3
      options[:summary] = true
      # We'll enhance the summary logic below for this flag
    end
    opts.on("--pub4-overview", "Far-away visual tree: all pillars, Rails apps collapsed, noise pruned") do
      options[:overview] = true
      options[:pillar] = :pub4
      options[:max_depth] = 3
      options[:summary] = true
    end
    opts.on("--master-overview", "Far-away MASTER pillar: lib/data/tools/web collapsed, .master pruned") do
      options[:overview] = true
      options[:pillar] = :master
      options[:root] = File.join(Dir.pwd, "MASTER")
      options[:max_depth] = 3
      options[:summary] = true
    end
    opts.on("--deploy-overview", "Far-away OPENBSD pillar: rails apps + config backup collapsed, noise pruned") do
      options[:overview] = true
      options[:pillar] = :deploy
      options[:root] = File.join(Dir.pwd, "OPENBSD")
      options[:max_depth] = 3
      options[:summary] = true
    end
    opts.on("-h", "--help") do
      puts opts
      puts "\nExamples:"
      puts "  tree.rb . --pub4-overview       # full repo shape (start here)"
      puts "  tree.rb --master-overview       # MASTER pillar only"
      puts "  tree.rb --deploy-overview       # OPENBSD pillar only"
      puts "  tree.rb MASTER --max-depth=5"
      puts "  tree.rb --focus lib --max-depth=6 --summary"
      puts "  tree.rb --master-lib            # best for working on the architecture"
      exit
    end
  end.parse!(ARGV)

  # Determine root
  if options[:root].nil?
    if ARGV[0] && !ARGV[0].start_with?("--")
      options[:root] = ARGV.shift
    else
      options[:root] = Dir.pwd
    end
  end

  if options[:overview]
    banner = case options[:pillar]
             when :master then "MASTER pillar"
             when :deploy then "OPENBSD pillar"
             else "pub4 overview"
             end
    puts "=== #{banner} (noise pruned: vendor, tmp, log, storage, node_modules, builds, assets, .master) ==="
    puts
  end

  tree = ProjectTree.new(
    root: options[:root],
    max_depth: options[:max_depth],
    summary: options[:summary],
    overview: options[:overview],
    pillar: options[:pillar]
  )

  # Simple focus mode (restricts walk root)
  if options[:focus]
    candidates = [
      File.join(options[:root], options[:focus]),
      File.join(options[:root], "MASTER", options[:focus])
    ].uniq

    focus_path = candidates.find { |p| Dir.exist?(p) }

    if focus_path
      puts "=== Focused view: #{focus_path.sub(ENV['HOME'] || '', '~')} ==="
      puts
      focused_tree = ProjectTree.new(
        root: focus_path,
        max_depth: options[:max_depth],
        summary: options[:summary],
        overview: options[:overview],
        pillar: options[:pillar]
      )
      focused_tree.run
      exit
    else
      warn "Focus path not found in: #{candidates.join(', ')}"
    end
  end

  tree.run
end
