# frozen_string_literal: true

module Ports
  module Openbsd
    class IndexParser
      def self.parse_line(line)
        parts = line.strip.split("|")
        return nil if parts.size < 4

        pkgpath = parts[1].to_s.strip
        return nil if pkgpath.blank?

        category, name = pkgpath.split("/", 2)
        return nil if name.blank?

        {
          name: name,
          pkgpath: pkgpath,
          category: category,
          comment: parts[2].to_s.strip,
          maintainer: parts[3].to_s.strip,
          full_pkgname: parts[0].to_s.strip,
        }
      end

      def self.parse_file(path)
        File.readlines(path, chomp: true).filter_map { |line| parse_line(line) }
      end
    end
  end
end
