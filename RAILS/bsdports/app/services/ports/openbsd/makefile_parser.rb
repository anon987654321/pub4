# frozen_string_literal: true

require "pathname"

module Ports
  module Openbsd
    class MakefileParser
      # make(1) operators: = and := assign, += appends, ?= assigns only when the
      # variable is unset. != runs a shell command and is not evaluated here.
      ASSIGNMENT = /\A([A-Z][A-Z0-9_]*)\s*(\+=|\?=|:=|=)\s*(.*)\z/

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
          permit_file_distfiles: permit_distfiles?(vars)
        }
      end

      private

      def extract_variables
        body = @path.read.gsub(/\\\r?\n/, "")
        vars = {}
        body.each_line do |line|
          line = line.strip
          next if line.blank? || line.start_with?("#", ".", "\t")

          match = ASSIGNMENT.match(line)
          next unless match

          key, operator, value = match.captures
          value = value.strip
          case operator
          when "+=" then vars[key] = [ vars[key].presence, value ].compact.join(" ")
          when "?=" then vars[key] = value unless vars.key?(key)
          else vars[key] = value
          end
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

      # bsd.port.mk(5): PERMIT_DISTFILES is "Yes" or the reason it may not be
      # mirrored, and defaults to "Yes" when PERMIT_PACKAGE is "Yes".
      def permit_distfiles?(vars)
        value = vars.key?("PERMIT_DISTFILES") ? vars["PERMIT_DISTFILES"] : vars["PERMIT_PACKAGE"]
        value.to_s.strip.casecmp?("yes")
      end
    end
  end
end
