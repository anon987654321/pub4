# frozen_string_literal: true

require_relative "../boot/paths"
require "digest"
require "json"
require_relative "design_audit"

module Master
  module Fix
    # Finds high-confidence maintenance opportunities that a syntax/rule scan
    # cannot express. These are evidence-backed prompts for the normal Council +
    # RepairLoop path, not a second fixer.
    class OpportunityPass
      LAW_ID = "CONVERGENCE_OPPORTUNITY"
      TEXT_FILES = %w[.md .rb .rake .yml .yaml .erb .html .js .css .scss].freeze
      SOURCE_ROOTS = MasterPaths::TREES
      # %r{} delimiters, not /.../ -- the character class needs a literal /
      # (repo-relative paths), which /.../ regex literals cannot hold
      # unescaped. Same bug as visual_pass.rb's SURFACE_RE, same fix.
      PATH_RE = %r{\b(?:MASTER|RAILS|OPENBSD)/[A-Za-z0-9_./-]+\.(?:rb|yml|yaml|md|js|css|scss|erb|html)\b}.freeze
      GLOB_RE = /(?:FileList|Dir\.glob)\s*\[(.*?)\]/.freeze
      STRING_RE = /["']([^"']+)["']/.freeze
      MAX_FINDINGS = 20
      # Room kept for design findings, so a long list of stale paths cannot crowd them out.
      DESIGN_SLOTS = 6
      SPRAWL_LIMITS = {
        "MASTER/Rakefile" => 650,
        "MASTER/lib/operator/ratchets.rb" => 600,
      }.freeze

      Law = PassLaw

      Finding = Data.define(:file, :line, :message, :fix) do
        def to_h
          {
            law: OpportunityPass::LAW_ID,
            file:,
            line:,
            severity: :warning,
            confidence: 1.0,
            reversibility: "cheap",
            blast_radius: { files_touched: 1 },
            message:,
            fix:,
          }
        end
      end

      def initialize(root:, bus: nil)
        @root = File.expand_path(root)
        @bus = bus
      end

      def applicable?(target)
        relative = repo_relative(target)
        SOURCE_ROOTS.include?(relative) || SOURCE_ROOTS.any? { |name| relative.start_with?("#{name}/") }
      end

      def run(target:, files:, plan: nil)
        return Result.ok(findings: [], assessment_evidence: { status: "not_applicable" }) unless applicable?(target)

        @assessment_gaps = []
        scope_root = plan&.root || repo_root
        scope_paths = Array(files).map { |path| File.expand_path(path.to_s, scope_root) }.uniq.sort
        before = capture_assessment_snapshot(target:, scope_paths:)
        findings = collect_findings(target:, files: scope_paths)
        after = capture_assessment_snapshot(target:, scope_paths:)
        assessment_evidence = build_assessment_evidence(
          target:, scope_paths:, plan:, before:, after:
        )
        publish_opportunities(target, findings)
        Result.ok(findings: findings.map(&:to_h), assessment_evidence:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.opportunity_pass", event_bus: @bus)
        Result.err("convergence opportunities: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
      end

      private

      # Capture the filesystem facts this heuristic pass can observe. The input
      # scope is pinned by FixPlan; auxiliary detectors are bound to a stable
      # path inventory and hashes of every file they read outside that scope.
      def capture_assessment_snapshot(target:, scope_paths:)
        inventory_paths = SOURCE_ROOTS.flat_map do |root|
          base = File.join(repo_root, root)
          next [] unless File.directory?(base)

          [base, *Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH)]
        end
        inventory = inventory_paths.uniq.filter_map do |path|
          next if %w[. ..].include?(File.basename(path))

          type = if File.symlink?(path)
                   "symlink"
                 elsif File.directory?(path)
                   "directory"
                 elsif File.file?(path)
                   "file"
                 else
                   "other"
                 end
          [repo_relative(path), type]
        end.sort

        dependencies = assessment_dependency_paths(target:, scope_paths:).filter_map do |path|
          next unless File.file?(path)

          raise "symlinked assessment dependency: #{repo_relative(path)}" if File.symlink?(path)

          before = File.stat(path)
          digest = Digest::SHA256.file(path).hexdigest
          after = File.stat(path)
          unless assessment_file_signature(before) == assessment_file_signature(after)
            raise "assessment dependency changed while read: #{repo_relative(path)}"
          end

          { path: repo_relative(path), sha256: digest, bytes: after.size }
        end
        inventory_sha256 = Digest::SHA256.hexdigest(JSON.generate(inventory))
        dependency_sha256 = Digest::SHA256.hexdigest(JSON.generate(dependencies))
        {
          status: "captured",
          digest: Digest::SHA256.hexdigest(JSON.generate([inventory_sha256, dependency_sha256])),
          inventory_sha256:,
          inventory_count: inventory.size,
          inventory:,
          dependency_sha256:,
          dependency_count: dependencies.size,
          dependencies:,
        }
      rescue StandardError => e
        {
          status: "unavailable",
          reason: "#{e.class}: #{e.message.to_s.gsub(/\s+/, " ").strip[0, 180]}",
        }
      end

      def assessment_dependency_paths(target:, scope_paths:)
        paths = scope_paths.dup
        relative = repo_relative(target)
        if relative == "MASTER"
          paths.concat(Dir.glob(File.join(repo_root, "MASTER", "lib", "**", "*.rb")))
          paths.concat(Dir.glob(File.join(repo_root, "{MASTER,RAILS,OPENBSD}", "**", "test*", "**", "*_test.rb")))
          paths.concat(Dir.glob(File.join(repo_root, "MASTER", "test", "test_*.rb")))
          paths.concat(Dir.glob(File.join(repo_root, "MASTER", "tools", "*.rb")))
          paths.concat([
            File.join(repo_root, "MASTER", "Rakefile"),
            File.join(repo_root, "MASTER", "lib", "operator", "ratchets.rb"),
          ])
        elsif relative == "RAILS"
          paths.concat([
            File.join(repo_root, "MASTER", "checks", "visual_contract.rb"),
            File.join(repo_root, "RAILS", "checks", "support", "geometry_probe.rb"),
          ])
        end
        if Array(scope_paths).empty?
          SOURCE_ROOTS.each do |root|
            paths.concat(
              Dir.glob(File.join(repo_root, root, "**", "*"))
                 .select { |path| File.file?(path) && TEXT_FILES.include?(File.extname(path).downcase) }
            )
          end
        end
        paths.map { |path| File.expand_path(path) }.uniq.sort
      end

      def build_assessment_evidence(target:, scope_paths:, plan:, before:, after:)
        reasons = []
        reasons << "active FixPlan unavailable" unless plan&.respond_to?(:sources)
        if plan
          expected_paths = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort
          reasons << "input file scope differs from FixPlan" unless scope_paths == expected_paths
          reasons << "FixPlan contains no eligible source files" if expected_paths.empty?
          absolute_target = target.to_s.start_with?("/") ? File.expand_path(target) : File.expand_path(target.to_s, repo_root)
          reasons << "assessment target differs from FixPlan target" unless absolute_target == plan.target
        end

        [before, after].each do |snapshot|
          reasons << (snapshot[:reason] || "assessment snapshot unavailable") unless snapshot[:status] == "captured"
        end
        stable_snapshot = before[:status] == "captured" && after[:status] == "captured" &&
          before[:digest] == after[:digest]
        reasons << "filesystem inventory or dependency hashes changed during assessment" if before[:status] == "captured" && after[:status] == "captured" && !stable_snapshot

        source_rows = []
        source_hashes_verified = false
        if plan && before[:status] == "captured"
          actual_by_path = before[:dependencies].to_h { |row| [File.expand_path(row[:path], repo_root), row[:sha256]] }
          source_rows = plan.sources.map do |source|
            absolute = File.expand_path(source.path, plan.root)
            { path: source.path, expected_sha256: source.sha256, actual_sha256: actual_by_path[absolute] }
          end
          source_hashes_verified = scope_paths == plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort &&
            source_rows.all? { |row| !row[:actual_sha256].to_s.empty? && row[:actual_sha256] == row[:expected_sha256] }
          reasons << "FixPlan source hashes no longer match" unless source_hashes_verified
        end
        reasons.concat(Array(@assessment_gaps))
        reasons = reasons.uniq.first(10)

        {
          schema_version: 1,
          status: reasons.empty? && stable_snapshot && source_hashes_verified ? "complete" : "inconclusive",
          target: target.to_s.start_with?("/") ? File.expand_path(target) : File.expand_path(target.to_s, repo_root),
          plan_digest: plan&.digest,
          source_digest: plan&.source_digest,
          scope_digest: plan&.scope_digest,
          eligible_files: scope_paths.size,
          source_hashes_verified: source_hashes_verified,
          snapshot_sha256: before[:digest],
          snapshot_after_sha256: after[:digest],
          inventory_sha256: before[:inventory_sha256],
          inventory_count: before[:inventory_count],
          inventory: before[:inventory],
          dependency_sha256: before[:dependency_sha256],
          dependency_count: before[:dependency_count],
          dependencies: before[:dependencies],
          source_rows:,
          reasons:,
        }
      end

      def assessment_file_signature(stat)
        [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
      end

      def collect_findings(target:, files:)
        findings = []
        relative = repo_relative(target)
        roots = target_roots(target)
        scope_files = Array(files).select { |path| File.file?(path) }
        roots.each { |root| collect_stale_paths(root, findings, scope_files:) }
        if roots.include?("MASTER") && relative == "MASTER"
          collect_dead_rake_globs(findings)
          collect_duplicate_tool_names(findings)
          collect_sprawl(findings, roots)
        elsif roots.include?("RAILS") && relative == "RAILS"
          collect_visual_duplicates(findings)
          collect_sprawl(findings, roots)
        end
        design = relative == "MASTER" ? collect_design : []
        findings.first(MAX_FINDINGS - design.size.clamp(0, DESIGN_SLOTS)) + design.first(DESIGN_SLOTS)
      end

      def collect_design
        DesignAudit.run(repo_root:).map { |row| Finding.new(row.file, row.line, row.message, row.fix) }
      end

      def publish_opportunities(target, findings)
        @bus&.publish(
          "fix_loop:opportunities",
          target: repo_relative(target),
          findings: findings.size,
          rules: findings.map { |f| f.message[/\A[^:]+/] }.uniq,
        )
      end

      def target_roots(target)
        relative = repo_relative(target)
        SOURCE_ROOTS.select { |root| relative == root || relative.start_with?("#{root}/") }
                    .then { |rows| rows.empty? ? SOURCE_ROOTS : rows }
      end

      def collect_stale_paths(root, findings, scope_files:)
        paths = scope_files.empty? ? files_for_root(root) : scope_files
        paths = paths.select { |path| path.start_with?(File.join(repo_root, root) + "/") }
        paths.each do |path|
          File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
            line.scan(PATH_RE).uniq.each do |ref|
              next if File.exist?(File.join(repo_root, ref))
              next if historical_reference?(line)

              findings << Finding.new(
                path,
                number,
                "stale repository path reference: #{ref}",
                "Verify the referenced path against the current tree. If it was renamed, update this live reference to the current path; if it is intentionally historical, leave it alone.",
              )
            end
          end
        end
      rescue ArgumentError, EncodingError => e
        @assessment_gaps << "stale-path scan failed for #{root}: #{e.class}: #{e.message.to_s[0, 160]}"
        Master::Ground::Swallow.log(e, context: "fix.opportunity_pass.paths", path: root, error: e.message)
      end

      def historical_reference?(line)
        line.match?(/\b(?:historical|history|formerly|renamed from|deleted|removed|old path|before the move|used to)\b/i)
      end

      def collect_dead_rake_globs(findings)
        path = File.join(repo_root, "MASTER", "Rakefile")
        return unless File.file?(path)

        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
          next unless line.match?(GLOB_RE)

          line.scan(GLOB_RE).each do |body|
            body[0].scan(STRING_RE).map(&:first).select { |glob| glob.include?("*") }.each do |glob|
              matches = Dir.glob(File.join(repo_root, "MASTER", glob))
              next unless matches.empty?

              findings << Finding.new(
                path,
                number,
                "dead Rake glob: #{glob} matches no files",
                "Remove the dead task/glob or repoint it to the current test/source tree. Confirm the replacement task is still reachable from the suite.",
              )
            end
          end
        end
      end

      def collect_duplicate_tool_names(findings)
        tools = Dir.glob(File.join(repo_root, "MASTER", "tools", "*.rb"))
        operators = Dir.glob(File.join(repo_root, "MASTER", "lib", "operator", "**", "*.rb"))
        operator_names = operators.to_h { |path| [File.basename(path, ".rb"), path] }

        tools.each do |path|
          name = File.basename(path, ".rb")
          next unless operator_names.key?(name)
          next unless File.readlines(path).size > 80

          findings << Finding.new(
            path,
            1,
            "parallel tool/operator implementations: #{name}.rb exists in tools/ and lib/operator/",
            "Compare the two implementations and keep one source of truth. Leave tools/ as a thin adapter and move reusable behavior into lib/operator when the logic is genuinely shared.",
          )
        end
      end

      def collect_visual_duplicates(findings)
        path = File.join(repo_root, "MASTER", "checks", "visual_contract.rb")
        return unless File.file?(path)
        return unless File.read(path, encoding: "UTF-8").include?("selenium-webdriver")

        probe = File.join(repo_root, "RAILS", "checks", "support", "geometry_probe.rb")
        return unless File.file?(probe)

        findings << Finding.new(
          path,
          1,
          "duplicate browser substrate: visual_contract uses Selenium while GeometryProbe/CDP is present",
          "Consolidate visual_contract onto GeometryProbe/CDP. Keep one browser transport for screenshot, geometry, console/runtime and rendered evidence.",
        )
      end

      def collect_sprawl(findings, roots)
        SPRAWL_LIMITS.each do |relative, limit|
          next unless roots.include?(relative.split("/", 2).first)
          path = File.join(repo_root, relative)
          next unless File.file?(path)

          body_lines = File.readlines(path, encoding: "UTF-8").count do |line|
            line.strip != "" && !line.lstrip.start_with?("#")
          end
          next unless body_lines > limit

          findings << Finding.new(
            path,
            1,
            "structural sprawl: #{relative} is #{body_lines} body lines (limit #{limit})",
            "Refactor toward one responsibility per boundary and delegate orchestration to existing lib/operator components. Preserve public behavior, tests, load order and observable side effects; do not split merely to move lines.",
          )
        end
      end

      def files_for_root(root)
        Dir.glob(File.join(repo_root, root, "**", "*"))
           .select { |path| File.file?(path) && TEXT_FILES.include?(File.extname(path).downcase) }
      end

      def repo_root
        return @root unless File.basename(@root) == "MASTER"

        File.expand_path("..", @root)
      end

      def repo_relative(target)
        raw = target.to_s
        absolute = raw.start_with?("/") ? File.expand_path(raw) : File.expand_path(raw, repo_root)
        absolute.delete_prefix("#{repo_root}/")
      end
    end
  end
end
