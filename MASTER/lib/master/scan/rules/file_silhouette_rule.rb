# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hashes each file's structural skeleton (header order, section markers, blank-line
      # cadence) into a 6-byte fingerprint. Clusters fingerprints across the repo; the
      # smallest clusters are visual outliers — files that don't look like the dominant
      # silhouette. Codifies the dominant rather than asking the operator to write rules.
      class FileSilhouetteRule < Rule
        FINGERPRINT_KEYS = %i[frozen requires constants attrs init publics privates].freeze
        OUTLIER_THRESHOLD = 0.10  # bottom 10% of cluster sizes = outliers

        def initialize
          super
          @id          = "file_silhouette"
          @description = "Structural skeleton diverges from repo-dominant file shape"
          @severity    = :info
          @axiom_tags  = %i[POLA_PRINCIPLE IMPORTANCE_ORDER]
          @cluster_mutex = Mutex.new
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          fp = fingerprint(code)
          clusters = clusters_for(File.dirname(path))
          return [] if clusters.empty?
          dominant = clusters.max_by { |_, count| count }&.first
          return [] if fp == dominant
          mine = clusters[fp] || 1
          total = clusters.values.sum
          return [] unless mine.to_f / total < OUTLIER_THRESHOLD
          [finding(line: 1, 
message: "silhouette #{fp.inspect} differs from dominant #{dominant.inspect} (#{mine}/#{total} files)")]
        end

        private

        def fingerprint(code)
          lines = code.lines
          {
            frozen:    lines.first.to_s.match?(/frozen_string_literal:\s*true/),
            requires:  lines.count { |l| l =~ /\Arequire/ },
            constants: lines.count { |l| l =~ /\A\s*[A-Z][A-Z0-9_]*\s*=/ },
            attrs:     lines.count { |l| l =~ /\A\s*attr_/ },
            init:      lines.any? { |l| l =~ /\A\s*def\s+initialize/ },
            publics:   lines.count { |l| l =~ /\A\s*def\s/ } - lines.count { |l| l =~ /\A\s*def\s+self\./ },
            privates:  lines.count { |l| l.strip == "private" }
          }.transform_values { |v| bucket(v) }.values.freeze
        end

        def bucket(v)
          case v
          when true, false then v
          when 0 then 0
          when 1..3 then 1
          when 4..10 then 2
          else 3
          end
        end

        def clusters_for(dir)
          @cluster_mutex.synchronize do
            @clusters ||= {}
            @clusters[dir] ||= compute_clusters(dir)
          end
        end

        def compute_clusters(dir)
          counts = Hash.new(0)
          Dir.glob(File.join(dir, "*.rb")).each do |f|
            counts[fingerprint(File.read(f, encoding: "UTF-8"))] += 1
          rescue StandardError
            next
          end
          counts
        end
      end
    end
  end
end
