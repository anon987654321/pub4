# frozen_string_literal: true

module Master
  module Fix
    # Finds high-confidence maintenance opportunities that a syntax/rule scan
    # cannot express. These are evidence-backed prompts for the normal Council +
    # RuleLoop path, not a second fixer.
    class OpportunityPass
      RULE_ID = "CONVERGENCE_OPPORTUNITY"
      TEXT_FILES = %w[.md .rb .rake .yml .yaml .erb .html .js .css .scss].freeze
      SOURCE_ROOTS = %w[MASTER RAILS OPENBSD STUDIO].freeze
      PATH_RE = /\b(?:MASTER|RAILS|OPENBSD|STUDIO)\/[A-Za-z0-9_./-]+\.(?:rb|yml|yaml|md|js|css|scss|erb|html)\b/.freeze
      GLOB_RE = /(?:FileList|Dir\.glob)\s*\[(.*?)\]/.freeze
      STRING_RE = /["']([^"']+)["']/.freeze
      MAX_FINDINGS = 20
      SPRAWL_LIMITS = {
        "MASTER/Rakefile" => 650,
        "MASTER/lib/operator/ratchets.rb" => 600,
      }.freeze

      Rule = Data.define(:id) do
        def severity = :warning
      end

      Finding = Data.define(:file, :line, :message, :fix) do
        def to_h
          {
            rule: OpportunityPass::RULE_ID,
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

      def run(target:, files:)
        return Result.ok(findings: []) unless applicable?(target)

        findings = []
        roots = target_roots(target)
        roots.each { |root| collect_stale_paths(root, findings) }
        collect_dead_rake_globs(findings) if roots.include?("MASTER")
        collect_duplicate_tool_names(findings) if roots.include?("MASTER")
        collect_visual_duplicates(findings) if roots.include?("RAILS")
        collect_sprawl(findings, roots)
        findings = findings.first(MAX_FINDINGS)

        @bus&.publish(
          "fix_loop:opportunities",
          target: repo_relative(target),
          findings: findings.size,
          rules: findings.map { |f| f.message[/\A[^:]+/] }.uniq,
        )
        Result.ok(findings: findings.map(&:to_h))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.opportunity_pass", event_bus: @bus)
        Result.err("convergence opportunities: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
      end

      private

      def target_roots(target)
        relative = repo_relative(target)
        SOURCE_ROOTS.select { |root| relative == root || relative.start_with?("#{root}/") }
                    .then { |rows| rows.empty? ? SOURCE_ROOTS : rows }
      end

      def collect_stale_paths(root, findings)
        files_for_root(root).each do |path|
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
              matches = Dir.glob(File.join(@root, "MASTER", glob))
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
        path = File.join(repo_root, "RAILS", "gates", "visual_contract.rb")
        return unless File.file?(path)
        return unless File.read(path, encoding: "UTF-8").include?("selenium-webdriver")

        probe = File.join(repo_root, "RAILS", "gates", "support", "geometry_probe.rb")
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
