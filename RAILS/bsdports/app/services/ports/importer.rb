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

    # No local tree is the NORMAL case, not a fatal one. platform.tree_path is
    # /usr/ports, which a base OpenBSD install does not ship and vm23 does not
    # have, and BSDPORTS_TREE_PATH is set nowhere in this repo. The old order
    # raised on a nil root *before* the FTP fallback line, so the fallback built
    # for exactly this situation could only ever run when a tree existed and
    # yielded zero ports. That is why bsdports.org has shown "Ingen porter
    # funnet" since launch: the import failed into an ImportRun row every night
    # and the site has no surface that reports one.
    # Three sources, best metadata first. Each is tried only if the one above
    # produced nothing, and the run fails loudly if all three do.
    #
    #   1. a local ports tree           full metadata, needs /usr/ports
    #   2. ports.tar.gz over HTTPS      full metadata, needs ~2 GB free disk
    #   3. the published package index  names + versions only, needs 1 MB
    #
    # No local tree is the NORMAL case, not a fatal one: platform.tree_path is
    # /usr/ports, which a base OpenBSD install does not ship and vm23 does not
    # have, and BSDPORTS_TREE_PATH is set nowhere in this repo. The old order
    # raised on a nil root *before* the fallback line, so the fallback built for
    # exactly this situation could only ever run when a tree existed and yielded
    # zero ports. That is why bsdports.org has shown "Ingen porter funnet" since
    # launch: the import failed into an ImportRun row every night, and the site
    # has no surface that reports one.
    def call
      @import_run = platform.import_runs.create!(status: "running", started_at: Time.current)
      root = TreeLocator.resolve(platform:, override: tree_path)
      source = nil

      if root
        import_from_tree(root)
        source = root.to_s
      end

      if ports_count.zero? && use_ftp_fallback
        source = import_from_tarball || import_from_package_index
      end

      if ports_count.zero?
        raise "no ports imported for #{platform.slug} " \
              "(tree=#{root || 'none'}, remote_fallback=#{use_ftp_fallback})"
      end

      resolve_dependencies
      rebuild_fts
      @import_run.mark_succeeded!(ports_count:, source_revision: source.to_s)
      Result.new(platform:, import_run: @import_run, ports_count:, tree_path: source.to_s)
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

    # Full metadata over the wire, when the host can spare the disk.
    def import_from_tarball
      index = Openbsd::PackageIndexFetcher.new(platform:)
      tarball = Openbsd::PortsTarball.new(platform:, release: safe_release(index))
      imported = nil
      tarball.with_tree do |tree_root|
        import_from_tree(tree_root)
        imported = tarball.url
      end
      ports_count.zero? ? nil : imported
    end

    # Names and versions only — see PackageIndexParser on why that is all the
    # mirror publishes. A catalogue with thin rows beats an empty page, and the
    # rows are marked "uncategorised" rather than given an invented category.
    def import_from_package_index
      fetcher = Openbsd::PackageIndexFetcher.new(platform:)
      entries = fetcher.each_entry
      return nil if entries.nil? || entries.empty?

      entries.each { |metadata| upsert_port(metadata) }
      fetcher.index_url
    end

    def safe_release(fetcher)
      fetcher.release
    rescue StandardError => e
      Rails.logger.warn("bsdports release detection failed: #{e.message}")
      nil
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
