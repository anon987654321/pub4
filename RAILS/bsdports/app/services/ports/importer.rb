# frozen_string_literal: true

module Ports
  class Importer
    Result = Data.define(:platform, :import_run, :ports_count, :tree_path)

    def self.call(platform:, tree_path: nil, use_ftp_fallback: true)
      new(platform:, tree_path:, use_ftp_fallback:).call
    end

    def initialize(platform:, tree_path: nil, use_ftp_fallback: true)
      @platform = platform
      @tree_path = tree_path
      @use_ftp_fallback = use_ftp_fallback
      @pending_deps = []
      @ports_count = 0
    end

    def call
      @import_run = platform.import_runs.create!(status: "running", started_at: Time.current)
      root = TreeLocator.resolve(platform:, override: tree_path)
      raise "ports tree not found for #{platform.slug}" unless root

      import_from_tree(root)
      import_from_ftp if ports_count.zero? && use_ftp_fallback
      resolve_dependencies
      rebuild_fts
      @import_run.mark_succeeded!(ports_count:, source_revision: root.to_s)
      Result.new(platform:, import_run: @import_run, ports_count:, tree_path: root.to_s)
    rescue StandardError => e
      @import_run&.mark_failed!(e.message)
      raise
    end

    private

    attr_reader :platform, :tree_path, :use_ftp_fallback, :pending_deps, :ports_count

    def import_from_tree(root)
      TreeLocator.each_port(root) do |_category, _name, makefile|
        metadata = Openbsd::MakefileParser.parse(makefile)
        next unless metadata

        upsert_port(metadata)
      end
    end

    def import_from_ftp
      fetcher = Openbsd::FtpIndexFetcher.new(platform:)
      %w[devel archivers www editors lang security].each { |category| import_category_index(fetcher, category) }
    end

    def import_category_index(fetcher, category)
      index_path = fetcher.fetch_category_index(category)
      return unless index_path

      Openbsd::IndexParser.parse_file(index_path).each do |metadata|
        upsert_port(metadata.merge(version: metadata[:full_pkgname].to_s.split("-", 2).last))
      end
    end

    def upsert_port(metadata)
      category = upsert_category(metadata[:category])
      maintainer = upsert_maintainer(metadata[:maintainer])
      port = Port.find_or_initialize_by(platform:, pkgpath: metadata[:pkgpath])
      old_version = port.version
      port.assign_attributes(
        name: metadata[:name],
        category: category,
        comment: metadata[:comment],
        description: metadata[:description],
        homepage: metadata[:homepage],
        version: metadata[:version].presence || "unknown",
        permit_file_distfiles: metadata[:permit_file_distfiles] == true,
        last_updated: Date.current
      )
      port[:maintainer] = metadata[:maintainer]
      port.maintainer_id = maintainer&.id
      port.save!
      record_version_change(port, old_version)
      queue_dependencies(port, metadata)
      @ports_count += 1
    end

    def upsert_category(name)
      Category.find_or_create_by!(platform:, name:) do |category|
        category.slug = name.parameterize
        category.description = "#{platform.name} #{name} ports"
      end
    end

    def upsert_maintainer(raw)
      return nil if raw.blank?

      Maintainer.find_or_create_by!(name: raw.strip)
    end

    def record_version_change(port, old_version)
      return if old_version.blank? || old_version == port.version

      port.port_updates.create!(
        old_version: old_version,
        new_version: port.version,
        commit_message: "import sync",
        committed_at: Time.current
      )
    end

    def queue_dependencies(port, metadata)
      {
        "build" => metadata[:build_depends],
        "run" => metadata[:run_depends],
        "lib" => metadata[:lib_depends]
      }.each do |dep_type, pkgpaths|
        Array(pkgpaths).each do |pkgpath|
          pending_deps << { port:, pkgpath:, dep_type: }
        end
      end
    end

    def resolve_dependencies
      unresolved = []
      pending_deps.each do |entry|
        depends_on = Port.find_by(platform:, pkgpath: entry[:pkgpath])
        unless depends_on
          unresolved << entry[:pkgpath]
          next
        end

        entry[:port].dependencies.find_or_create_by!(depends_on:, dep_type: entry[:dep_type])
      end
      return if unresolved.empty?

      message = "unresolved dependencies: #{unresolved.uniq.sort.first(12).join(', ')}"
      message += " (+#{unresolved.uniq.size - 12} more)" if unresolved.uniq.size > 12
      Rails.logger.warn("bsdports import: #{message}")
      @import_run&.update!(error_message: [ @import_run.error_message, message ].compact.join(" | "))
    end

    def rebuild_fts
      Port.connection.execute("INSERT INTO ports_fts(ports_fts) VALUES('rebuild')")
    rescue StandardError => e
      Rails.logger.warn("bsdports fts rebuild skipped: #{e.message}")
    end
  end
end
