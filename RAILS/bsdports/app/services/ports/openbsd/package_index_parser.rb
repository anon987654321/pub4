# frozen_string_literal: true

module Ports
  module Openbsd
    # Parses the `ls -l` listing OpenBSD mirrors publish at
    # /pub/OpenBSD/<release>/packages/<arch>/index.txt:
    #
    #   -rw-r--r--  1 0  0    83961563 Apr 25 13:24:13 2026 0ad-0.28.0.tgz
    #
    # This is the ONLY package metadata on the mirror (measured 2026-08-05: the
    # directory holds index.txt, SHA256 and SHA256.sig and nothing else), so it
    # is name and version only. Category, COMMENT, maintainer and dependencies
    # live in the ports tree and need ports.tar.gz — see PortsTarball.
    class PackageIndexParser
      # OpenBSD package names are stem-version[-flavor]. The version begins at
      # the first hyphen followed by a digit, scanning left to right: that keeps
      # p5-Net-SSLeay-1.92 (stem p5-Net-SSLeay) and 0ad-0.28.0 (stem 0ad) right.
      # It mis-splits the rare stem whose own component starts with a digit
      # (py3-2to3-1.0 reads as version "2to3-1.0"); those rows still import, with
      # a version string that looks odd rather than a missing port.
      PKGNAME = /\A(?<stem>.+?)-(?<version>\d[^\s]*)\z/
      LISTING = /\A\S+\s+\d+\s+\S+\s+\S+\s+\d+\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4}\s+(?<file>\S+\.tgz)\z/

      def self.parse_line(line)
        listing = LISTING.match(line.to_s.strip) or return nil
        parse_pkgname(listing[:file].sub(/\.tgz\z/, ""))
      end

      def self.parse_pkgname(pkgname)
        parts = PKGNAME.match(pkgname) or return nil

        stem = parts[:stem]
        {
          name: stem,
          version: parts[:version],
          full_pkgname: pkgname,
          # Namespaced so it can never collide with a real ports-tree pkgpath
          # (devel/git). PortsTarball prunes these once it knows the real one.
          pkgpath: "#{Ports::Openbsd::PackageIndexParser::SYNTHETIC_PREFIX}/#{stem}",
          category: Ports::Openbsd::PackageIndexParser::SYNTHETIC_CATEGORY,
          comment: nil,
          maintainer: nil
        }
      end

      def self.parse(io)
        io.each_line.filter_map { |line| parse_line(line) }
      end

      SYNTHETIC_PREFIX = "packages"
      # Honest label. These rows genuinely have no category — inventing a
      # plausible one would make the gap invisible on the category surface.
      SYNTHETIC_CATEGORY = "uncategorised"
    end
  end
end
