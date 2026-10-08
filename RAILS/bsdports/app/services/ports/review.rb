# frozen_string_literal: true

require "pathname"

module Ports
  class Review
    Result = Data.define(:issues, :source_status, :source_path, :mismatches)

    def self.call(port:, tree_path: nil)
      new(port:, tree_path:).call
    end

    def initialize(port:, tree_path: nil)
      @port = port
      @tree_path = tree_path
    end

    def call
      issues = metadata_issues
      root = TreeLocator.resolve(platform: @port.platform, override: @tree_path)
      return Result.new(issues:, source_status: :unavailable, source_path: nil, mismatches: []) unless root

      port_dir = port_directory(root)
      return Result.new(issues: issues + [ :missing_port_directory ], source_status: :missing, source_path: port_dir.to_s, mismatches: []) unless port_dir&.directory?

      makefile = port_dir.join("Makefile")
      return Result.new(
        issues: issues + [ :missing_makefile ],
        source_status: :missing,
        source_path: makefile.to_s,
        mismatches: []
      ) unless makefile.file?

      source = Openbsd::MakefileParser.parse(makefile)
      return Result.new(issues: issues + [ :unreadable_makefile ], source_status: :invalid, source_path: makefile.to_s, mismatches: []) unless source

      mismatches = metadata_mismatches(source)
      issues.concat(mismatch_issue_keys(mismatches))
      issues.concat(empty_patch_issues(port_dir))
      issues.uniq!

      Result.new(
        issues:,
        source_status: :available,
        source_path: makefile.to_s,
        mismatches:
      )
    end

    private

    def metadata_issues
      [
        (:missing_homepage if @port.homepage.blank?),
        (:weak_comment if @port.comment.to_s.strip.length < 20)
      ].compact
    end

    def port_directory(root)
      relative = @port.pkgpath.to_s.strip
      return nil if relative.blank?

      root_path = File.expand_path(root.to_s)
      candidate = File.expand_path(relative, root_path)
      return nil unless candidate.start_with?("#{root_path}/")
      return nil if candidate == root_path

      Pathname.new(candidate)
    end

    def metadata_mismatches(source)
      {
        comment: [ @port.comment.to_s.strip, source[:comment].to_s.strip ],
        homepage: [ @port.homepage.to_s.strip, source[:homepage].to_s.strip ],
        maintainer: [ @port[:maintainer].to_s.strip, source[:maintainer].to_s.strip ],
        version: [ normalized_version(@port.version), normalized_version(source[:version]) ]
      }.select do |_field, (indexed, source_value)|
        indexed.present? && source_value.present? && indexed != source_value
      end
    end

    def normalized_version(value)
      value.to_s.strip
    end

    def mismatch_issue_keys(mismatches)
      mismatches.keys.map { |field| :"source_#{field}_mismatch" }
    end

    def empty_patch_issues(port_dir)
      files = port_dir.join("files")
      return [] unless files.directory?

      empty = Dir.glob(files.join("patch-*").to_s).select { |path| File.file?(path) && File.zero?(path) }
      empty.empty? ? [] : [ :empty_patch ]
    end
  end
end
