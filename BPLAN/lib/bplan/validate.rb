# frozen_string_literal: true

require "digest"
require "set"
require "yaml"
require_relative "../../funding_helpers"
require_relative "constants"

module Bplan
  class Validate
    PLAN_SLUGS = Constants::PLAN_ORDER

    FORBIDDEN_PHRASES = [
      "applikasjaser",
      "72–100+ forbedringsforslag",
      "72-100+ forbedringsforslag",
      "WCAG AAA",
      "Biokompatibilitetssimulering",
      "TRL 5→8",
      "dating, takeaway",
    ].freeze

    REQUIRED_APP_KEYS = %w[id file funder to subject track project draft sendable].freeze

    class << self
      def validate_all(root: File.expand_path("../..", __dir__), funding: nil, plan_defs: nil, manifest_entries: nil, helpers: nil)
        errors = []
        funding ||= FundingHelpers.load_funding(root)
        helpers ||= FundingHelpers

        plan_defs ||= PLAN_SLUGS.filter_map do |slug|
          v = funding["ventures"][slug]
          next unless v

          { slug: slug, title: v["title"] }
        end

        errors.concat(validate_funding_budgets(funding, helpers))
        errors.concat(validate_funder_fit_keys(funding))
        errors.concat(validate_legat_ceiling_explainer(funding))
        errors.concat(validate_deadline_batches(funding, root))
        warnings = validate_duplicate_deadlines(funding)
        warnings.each { |w| warn "VALIDATE WARN: #{w}" } unless warnings.empty?

        errors.concat(validate_plan_files(root, plan_defs))
        errors.concat(validate_forbidden_phrases(root))

        if manifest_entries
          errors.concat(validate_legat_files(root, manifest_entries))
          errors.concat(validate_manifest_sendable_rules(manifest_entries))
          errors.concat(validate_catalog_projects(manifest_entries, funding, helpers))
        else
          errors.concat(validate_legats(root))
          manifest = load_manifest(root)
          errors.concat(validate_catalog_projects(manifest.fetch("applications", []), funding, helpers))
        end

        errors.concat(validate_batches(root))
        errors
      end

      def validate_all!(root, funding: nil, plan_defs: nil, manifest_entries: nil, helpers: nil)
        errors = validate_all(
          root: root,
          funding: funding,
          plan_defs: plan_defs,
          manifest_entries: manifest_entries,
          helpers: helpers,
        )
        if errors.empty?
          count = (plan_defs || PLAN_SLUGS).size
          legat_note = manifest_entries ? ", #{manifest_entries.size} legats" : ""
          puts "Bplan::Validate OK (#{count} plans#{legat_note})"
        else
          errors.each { |e| warn "VALIDATE: #{e}" }
          raise "Bplan::Validate failed with #{errors.size} error(s)"
        end
        errors
      end

      def validate_funding(root)
        validate_funding_budgets(FundingHelpers.load_funding(root), FundingHelpers)
      end

      def validate_funder_fit_keys(funding)
        errors = []
        ventures = funding.fetch("ventures", {}).keys.to_set
        funding.fetch("funders", []).each do |f|
          (f["fit"] || []).each do |key|
            errors << "funder #{f['id']} fit key #{key} missing from ventures" unless ventures.include?(key)
          end
        end
        funding.fetch("new_funders_meta", []).each do |draft|
          (draft["fit"] || []).each do |key|
            errors << "new_funders_meta #{draft['id']} fit key #{key} missing from ventures" unless ventures.include?(key)
          end
        end
        errors
      end

      def validate_legat_ceiling_explainer(funding)
        text = funding.dig("portfolio", "legat_sum_explainer").to_s.strip
        return [] if text.length >= 20

        ["portfolio.legat_sum_explainer missing or too short"]
      end

      def validate_deadline_batches(funding, root)
        errors = []
        batches_path = File.join(root, "legats/batches.yml")
        return errors unless File.exist?(batches_path)

        batch_names = YAML.load_file(batches_path).fetch("batches", {}).keys.to_set
        funding.fetch("deadlines", []).each do |d|
          batch = d["batch"]
          next if batch.nil? || batch.to_s.empty?

          errors << "deadline #{d['funder']} references unknown batch #{batch}" unless batch_names.include?(batch)
        end
        errors
      end

      def validate_duplicate_deadlines(funding)
        warnings = []
        by_funder = funding.fetch("deadlines", []).group_by { |d| d["funder"].to_s.downcase }
        by_funder.each do |funder, rows|
          warnings << "multiple deadline rows for #{funder} (#{rows.size}) — consider merging" if rows.size > 1
        end
        warnings
      end

      def validate_catalog_projects(manifest_entries, funding, helpers)
        manifest_entries.filter_map do |app|
          project = app["project"]
          next if project.nil? || project.to_s.empty?

          resolved = helpers.resolve_venture(project)
          next if funding.dig("ventures", resolved)

          "#{app['id']}: project #{project} does not resolve to venture #{resolved}"
        end
      end

      def validate_funding_budgets(funding, helpers)
        errors = []
        funding["ventures"].each do |slug, v|
          total = v["project_total_nok"].to_i
          next if total.zero?

          sum = helpers.venture_breakdown(slug, funding).sum { |l| l["nok"].to_i }
          errors << "budget mismatch #{slug}: #{sum} != #{total}" unless sum == total
        end
        errors
      end

      def validate_plans(root)
        errors = []
        funding = FundingHelpers.load_funding(root)

        PLAN_SLUGS.each do |slug|
          errors << "missing venture #{slug} in funding.yml" unless funding.dig("ventures", slug)
          path = File.join(root, "#{slug}.html")
          errors << "missing plan html #{slug}.html" unless File.exist?(path)
        end

        errors << "missing index.html" unless File.exist?(File.join(root, "index.html"))
        errors
      end

      def validate_plan_files(root, plan_defs)
        errors = []
        plan_defs.each do |p|
          path = File.join(root, "#{p[:slug]}.html")
          errors << "missing plan #{path}" unless File.exist?(path)
        end
        errors << "missing index.html" unless File.exist?(File.join(root, "index.html"))
        errors
      end

      def validate_legats(root)
        errors = []
        manifest_path = File.join(root, "legats/manifest.yml")
        return ["missing legats/manifest.yml"] unless File.exist?(manifest_path)

        manifest = YAML.load_file(manifest_path)
        seen_ids = {}

        manifest.fetch("applications", []).each do |app|
          id = app["id"]
          errors << "duplicate application id #{id}" if seen_ids[id]
          seen_ids[id] = true

          REQUIRED_APP_KEYS.each do |key|
            errors << "#{id}: missing #{key}" if app[key].nil?
          end

          html = File.join(root, app["file"].to_s)
          errors << "#{id}: missing html #{app['file']}" unless File.exist?(html)

          errors << "#{id}: sendable but empty to" if app["sendable"] && app["to"].to_s.strip.empty?
        end

        errors.concat(validate_manifest_sendable_rules(manifest.fetch("applications", [])))
        errors
      end

      def validate_legat_files(root, manifest_entries)
        manifest_entries.filter_map do |e|
          path = File.join(root, e["file"].to_s)
          "missing legat #{path}" unless File.exist?(path)
        end
      end

      def validate_forbidden_phrases(root)
        errors = []
        targets = Dir.glob(File.join(root, "*.html")) +
                  Dir.glob(File.join(root, "legats", "*.html"))
        targets.each do |path|
          content = File.read(path)
          FORBIDDEN_PHRASES.each do |phrase|
            errors << "#{path} contains forbidden phrase: #{phrase}" if content.include?(phrase)
          end
        end
        errors
      end

      def validate_manifest_sendable_rules(manifest_entries)
        errors = []
        innovasjon = manifest_entries.find { |e| e["id"] == "01_innovasjon_norge_master" }
        errors << "01_innovasjon_norge_master must have sendable: false" if innovasjon && innovasjon["sendable"]

        manifest_entries.each do |e|
          next unless e["draft"] || e["to"] == Constants::APPLICANT[:email]

          errors << "#{e['id']} is draft/self-to but marked sendable" if e["sendable"]
        end

        manifest_entries.each do |e|
          next unless e["id"].to_s.start_with?("vx_") || e["low_priority"]

          errors << "#{e['id']} is vx_/low_priority but marked sendable" if e["sendable"]
        end
        errors
      end

      def validate_batches(root)
        errors = []
        batches_path = File.join(root, "legats/batches.yml")
        return ["missing legats/batches.yml"] unless File.exist?(batches_path)

        batches = YAML.load_file(batches_path).fetch("batches", {})
        index = manifest_index(root)

        batches.each do |name, batch|
          ids =
            if batch["auto"]
              resolve_auto_batch_ids(name, batch, root, index)
            else
              batch.fetch("ids", [])
            end

          ids.each do |id|
            errors << "batch #{name}: unknown id #{id}" unless index[id]
          end
        end

        errors
      end

      def resolve_auto_batch_ids(batch_name, batch, root, index)
        if batch["auto_from"] == "funding_deadlines"
          funding = FundingHelpers.load_funding(root)
          return funding.fetch("deadlines", []).filter_map do |d|
            next unless d["batch"] == batch_name

            d["legat_id"]
          end.uniq
        end

        apps = load_manifest(root).fetch("applications", [])
        apps = apps.reject { |a| a["draft"] } if batch["exclude_drafts"]
        apps = apps.select { |a| a["sendable"] } if batch["exclude_self"]
        apps = apps.reject { |a| a["low_priority"] } if batch["exclude_low_priority"]
        apps = apps.reject { |a| a["id"].to_s.start_with?("vx_") } if batch["exclude_vx"]
        apps.map { |a| a["id"] }
      end

      def manifest_index(root)
        load_manifest(root).fetch("applications", []).to_h { |a| [a["id"], a] }
      end

      def load_manifest(root)
        YAML.load_file(File.join(root, "legats/manifest.yml"))
      end

      def write_build_id!(root)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        digest = Digest::SHA256.file(File.join(root, "funding.yml")).hexdigest[0, 12]
        build_id = "#{stamp}-#{digest}"
        File.write(File.join(root, "BUILD_ID"), "#{build_id}\n")
        puts "wrote BUILD_ID (#{build_id})"
        build_id
      end
    end
  end
end