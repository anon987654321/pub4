# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "yaml"
require_relative "../../../OPENBSD/lib/deploy_inventory"

module Master
  module AI
    # The compact orientation frame every model turn receives before it touches
    # project source. It is a view, not a second constitution: paths and values
    # are read from the live tree and durable state, while OperatorContract owns
    # the behavioral law.
    module Orientation
      VERSION = 3
      DEFAULT_DEPTH = 2
      MAX_ENTRIES = 80
      ATLAS_MAX_BYTES = 3_000
      LENSES = %w[
        authority topology runtime privilege security design lifecycle resources
        recovery observability provenance seams
      ].freeze
      SKIP = %w[.git .bundle vendor node_modules tmp log coverage storage .master knowledge output sockets pids cache]
                  .freeze

      module_function

      def render(root:, target: nil, depth: DEFAULT_DEPTH, max_entries: MAX_ENTRIES)
        root = File.realpath(root)
        repo_root = File.basename(root) == "MASTER" ? File.expand_path("..", root) : root
        parts = [
          "MASTER orientation v#{VERSION}",
          "repo: #{repo_root}",
          "target: #{target ? relative(target, repo_root) : relative(root, repo_root)}",
          "contract: orient → inspect → act → verify",
          "verification: evidence before completion",
          "trees: MASTER, RAILS, OPENBSD, STUDIO; MASTER/tools = canonical tool plane inside MASTER",
          "head: #{git_head(repo_root)}",
          "docs: #{key_docs(repo_root).join(", ")}",
        ]

        plan = active_plan(root)
        parts << "active plan: #{compact(plan)}" unless plan.to_s.empty?

        wishes = pending_wishes(root)
        parts << "pending wishes: #{wishes.join(", ")}" unless wishes.empty?

        atlas = repository_atlas(repo_root)
        parts << atlas unless atlas.to_s.empty?

        parts << "tree:"
        parts.concat(tree_lines(root, depth:, max_entries:))
        parts.join("\n")
      rescue StandardError => e
        "MASTER orientation unavailable: #{e.class}: #{e.message}"
      end

      def repository_atlas(repo_root)
        rails = rails_atlas(repo_root)
        openbsd = openbsd_atlas(repo_root)
        return if rails.nil? && openbsd.nil?

        lines = [
          "cross-tree atlas:",
          "lenses: #{LENSES.join(", ")}",
          rails,
          openbsd,
          "evidence_ladder: source authority → executable proof → live evidence; " +
          "disagreement means drift to diagnose, not permission to guess",
          "bridge: RAILS/apps.yml → OPENBSD/deploy_inventory.json → vps-deploy → rcctl → public health",
          "inventory_alignment: #{inventory_alignment(repo_root)}",
          "bridge: MASTER/data/soul.yml + MASTER/data/rules.yml are law; " +
          "MASTER/gates/ is the cross-tree verification plane",
          "research pointers: Rails=RAILS/CLAUDE.md + RAILS/apps.yml; " +
          "OpenBSD=OPENBSD/CLAUDE.md + OPENBSD/RUNBOOK.md + OPENBSD/data/operator.yml",
        ].compact
        atlas = []
        bytes = 0
        lines.each do |line|
          line_bytes = line.bytesize + (atlas.empty? ? 0 : 1)
          break if bytes + line_bytes > ATLAS_MAX_BYTES - 4

          atlas << line
          bytes += line_bytes
        end
        atlas << "..." if atlas.length < lines.length
        atlas.join("\n")
      end

      def rails_atlas(repo_root)
        path = File.join(repo_root, "RAILS", "apps.yml")
        return unless File.file?(path)

        data = YAML.safe_load_file(path, aliases: true)
        apps = data.is_a?(Hash) ? data.fetch("apps", {}) : {}
        rows = apps.filter_map do |name, config|
          next unless config.is_a?(Hash)

          domain = config["domain"].to_s
          port = config["port"].to_i
          label = [name.to_s, domain.empty? ? nil : domain, port.positive? ? port : nil].compact.join(":")
          label unless label.empty?
        end
        return if rows.empty? && !File.file?(File.join(repo_root, "RAILS", "CLAUDE.md"))

        "rails: feature_truth=RAILS/apps.yml; architecture=RAILS/CLAUDE.md; " +
        "shared=RAILS/shared; design=RAILS/shared/README.md; entry=RAILS/bin/triangle; " +
        "coupling=shared engine + sibling copy-tree affects every Rails app; " +
        "deployed_copy=/home/<app>/app + /home/<app>/shared; " +
        "proof=RAILS/gates/gates.yml+RAILS/bin/triangle+<app>/bin/ci; " +
        "live=OPENBSD/bin/check-vps+OPENBSD/bin/vps-state; " +
        "rendered=Chrome/CDP via rendered_suite; " +
        "visual_graph=MASTER/lib/fix/rails_visual_graph.rb; apps=#{rows.join(", ")}"
      rescue StandardError
        "rails: feature_truth=RAILS/apps.yml; architecture=RAILS/CLAUDE.md; inventory unavailable"
      end

      def inventory_alignment(repo_root)
        return "unmeasured" unless defined?(Deploy::Inventory)

        inventory = Deploy::Inventory.new(root: repo_root)
        rails_apps = inventory.apps.to_h { |app| [app.name, [app.domain, app.port]] }
        openbsd_apps = inventory.master_apps.to_h { |app| [app.name, [app.domain, app.port]] }

        rails_only = rails_apps.keys - openbsd_apps.keys
        openbsd_only = openbsd_apps.keys - rails_apps.keys
        divergent = (rails_apps.keys & openbsd_apps.keys).select { |name| rails_apps[name] != openbsd_apps[name] }
        return "clean" if rails_only.empty? && openbsd_only.empty? && divergent.empty?

        parts = ["mismatch"]
        parts << "rails_only=#{rails_only.join(",")}" unless rails_only.empty?
        parts << "openbsd_only=#{openbsd_only.join(",")}" unless openbsd_only.empty?
        parts << "divergent=#{divergent.join(",")}" unless divergent.empty?
        parts.join(" ")
      rescue StandardError
        "unmeasured"
      end
      def openbsd_atlas(repo_root)
        inventory_path = File.join(repo_root, "OPENBSD", "deploy_inventory.json")
        operator_path = File.join(repo_root, "OPENBSD", "data", "operator.yml")
        runbook_path = File.join(repo_root, "OPENBSD", "RUNBOOK.md")
        return unless [inventory_path, operator_path, runbook_path].any? { |path| File.file?(path) }

        data = JSON.parse(File.read(inventory_path, encoding: "UTF-8"))
        apps = Array(data["apps"]).filter_map do |app|
          next unless app.is_a?(Hash)

          [app["name"], app["domain"], app["port"]].compact.join(":")
        end
        face = data["master_face"]
        master = face.is_a?(Hash) ? [face["domain"], face["port"]].compact.join(":") : "inventory unavailable"
        "openbsd: deploy_identity=OPENBSD/deploy_inventory.json; " +
        "recipes=OPENBSD/data/operator.yml; runbook=OPENBSD/RUNBOOK.md; configs=OPENBSD/etc; " +
        "service_lifecycle=rcctl; privilege_boundary=doas; sandbox_model=MASTER/lib/ground/pledge.rb; " +
        "edge=pf→relayd→loopback; " +
        "runtime=Falcon+SQLite+Solid Queue/Cache; secrets=/etc/*.env; " +
        "dns_tls=httpd/acme-client/nsd; proof=OPENBSD/bin/check-openbsd+check-vps+vps-state; " +
        "live=target host diagnostics and public health; " +
        "recovery=tmux+vps-deploy; resource_guard=OPENBSD/bin/resource_guard.sh; " +
        "apps=#{apps.join(", ")}; master=#{master}"
      rescue StandardError
        "openbsd: deploy identity or operational inventory unavailable; " +
        "inspect OPENBSD/CLAUDE.md and OPENBSD/RUNBOOK.md"
      end

      def tree_lines(root, depth:, max_entries:)
        seen = 0
        truncated = false
        lines = []

        walk = lambda do |dir, indent, level|
          return if level > depth || truncated

          Dir.children(dir).sort_by do |name|
            path = File.join(dir, name)
            [File.directory?(path) ? 0 : 1, name]
          end.each do |name|
            break if seen >= max_entries

            next if SKIP.include?(name)

            path = File.join(dir, name)
            seen += 1
            lines << "#{indent}#{name}#{File.directory?(path) ? "/" : ""}"
            walk.call(path, "#{indent}  ", level + 1) if File.directory?(path)
          end

          truncated = true if seen >= max_entries
        end

        lines << "#{File.basename(root)}/"
        walk.call(root, "", 0)
        lines << "... (orientation tree truncated)" if truncated
        lines
      end

      def active_plan(root)
        path = File.join(root, "runtime", "active_plan.md")
        return unless File.file?(path)

        File.read(path, encoding: "UTF-8")[0, 900].strip
      end

      def pending_wishes(root)
        path = File.join(root, "runtime", "wishlist.md")
        return [] unless File.file?(path)

        File.readlines(path, encoding: "UTF-8", chomp: true)
            .grep(/\A###? \d+\./)
            .first(5)
            .map { |line| line.sub(/\A###? /, "").strip }
      end

      def key_docs(repo_root)
        %w[CLAUDE.md TREE.md TODO.md].select { |name| File.file?(File.join(repo_root, name)) }
      end

      def git_head(repo_root)
        git = File.join(repo_root, ".git")
        head = if File.file?(git)
          git_dir = File.read(git).strip.sub(/\Agitdir:\s*/, "")
          File.read(File.expand_path("HEAD", File.join(File.dirname(git), git_dir)))
        elsif File.directory?(git)
          File.read(File.join(git, "HEAD"))
        end
        head.to_s.strip.delete_prefix("ref: ").split("/").last || "unknown"
      rescue StandardError
        "unknown"
      end

      def relative(path, repo_root)
        full = File.expand_path(path)
        return "." if full == repo_root
        return path.to_s unless full.start_with?("#{repo_root}/")

        full.delete_prefix("#{repo_root}/")
      end

      def compact(text, limit = 500)
        body = text.to_s.gsub(/\s+/, " ").strip
        body.length > limit ? "#{body[0, limit - 1]}…" : body
      end

      def digest(root:)
        Digest::SHA256.hexdigest(render(root:))[0, 16]
      end
    end
  end
end
