# frozen_string_literal: true

require "pathname"

module Ports
  module Openbsd
    class MakefileParser
      ASSIGNMENT = /\A([A-Z][A-Z0-9_]*)\s*(?:\?\+=|\+=|\?=|=)\s*(.*)\z/
      PLUS_ASSIGNMENT = /\A([A-Z][A-Z0-9_]*)\s*\+=\s*(.*)\z/

      def self.parse(path) = new(path).parse

      def initialize(path)
        @path = Pathname.new(path)
      end

      def parse
        return nil unless @path.file?

        vars = extract_variables
        port_name = @path.parent.basename.to_s
        category = @path.parent.parent.basename.to_s
        pkgpath = "#{category}/#{port_name}"

        {
          name: port_name,
          pkgpath: pkgpath,
          category: category,
          comment: clean_value(vars["COMMENT"]),
          maintainer: clean_value(vars["MAINTAINER"]),
          homepage: clean_value(vars["HOMEPAGE"]),
          version: extract_version(vars, port_name),
          description: read_descr,
          build_depends: parse_depends(vars["BUILD_DEPENDS"]),
          run_depends: parse_depends(vars["RUN_DEPENDS"]),
          lib_depends: parse_depends(vars["LIB_DEPENDS"]),
          permit_file_distfiles: permit_distfiles?(vars),
        }
      end

      private

      def extract_variables
        body = @path.read.gsub(/\\\r?\n/, "")
        vars = {}
        body.each_line do |line|
          line = line.strip
          next if line.blank? || line.start_with?("#", ".", "\t")

          if (match = PLUS_ASSIGNMENT.match(line))
            key, value = match.captures
            vars[key] = [ vars[key], value.strip ].compact.join(" ")
            next
          end

          match = ASSIGNMENT.match(line)
          next unless match

          key, value = match.captures
          vars[key] = value.strip
        end
        vars
      end

      def clean_value(value)
        value.to_s.strip.delete_prefix('"').delete_suffix('"')
      end

      def extract_version(vars, port_name)
        candidates = [ vars["FULLPKGNAME"], vars["PKGNAME"], vars["DISTNAME"] ].compact
        candidates.each do |raw|
          expanded = expand_vars(raw, vars)
          stripped = expanded.sub(/\A#{Regexp.escape(port_name)}-/, "")
          return stripped if stripped.present? && stripped != expanded
          return expanded if expanded.match?(/\d/)
        end
        nil
      end

      def expand_vars(value, vars)
        value.gsub(/\$\{([A-Z0-9_]+)\}/) { vars[Regexp.last_match(1)] || "" }
             .gsub(/\$([A-Z0-9_]+)/) { vars[Regexp.last_match(1)] || "" }
      end

      def parse_depends(value)
        return [] if value.blank?

        value.split(/[\s,]+/).filter_map do |token|
          token = token.gsub(/[><=].*/, "").strip
          next if token.blank? || token.include?("$") || token.include?("(")

          token
        end.uniq
      end

      def read_descr
        descr = @path.parent.join("DESCR")
        return nil unless descr.file?

        descr.read.strip
      end

      def permit_distfiles?(vars)
        %w[PERMIT_PACKAGE_CDROM_DISTFILES PERMIT_PACKAGE_FTP_DISTFILES].any? do |key|
          vars[key].to_s.strip.casecmp("yes").zero?
        end
      end
    end
  end
end
