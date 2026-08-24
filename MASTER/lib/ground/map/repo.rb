# frozen_string_literal: true

module Master
  module Ground
    module Map
      class Repo

        DEFAULT_IGNORES = %w[
          .git tmp log vendor node_modules coverage .bundle storage public/assets
          knowledge/awesome knowledge/vendor
        ].freeze

        LANGUAGE_BY_EXT = {
          ".rb" => :ruby,
          ".js" => :javascript,
          ".ts" => :typescript,
          ".css" => :css,
          ".html" => :html,
          ".erb" => :erb,
          ".yml" => :yaml,
          ".yaml" => :yaml,
          ".json" => :json,
          ".md" => :markdown,
          ".sh" => :shell,
        }.freeze

        FileEntry = Struct.new(:path, :language, :bytes, :mtime, :score, keyword_init: true)
        DEFAULT_TOKEN_LIMIT = 1_024
        TOKEN_BYTES = 4.0

        attr_reader :root, :roots

        def initialize(root: Master::ROOT, ignores: DEFAULT_IGNORES, roots: nil)
          @root = root
          @ignores = ignores
          @roots = Array(roots).map { |path| File.expand_path(path, @root) }.uniq
          @roots = [@root] if @roots.empty?
        end

        def files
          @roots.flat_map { |base| files_in_root(base) }
        end

        def relevant(query, limit: 30)
          terms = query.to_s.downcase.scan(/[a-z0-9_\-]+/)
          term_weights = terms.tally
          now = Time.now
          files.map do |entry|
            text = entry.path.downcase
            basename = File.basename(entry.path).downcase
            term_score = term_weights.sum do |term, count|
              hits = text.scan(Regexp.new(Regexp.escape(term))).size + basename.scan(Regexp.new(Regexp.escape(term))).size
              count * (hits.zero? ? 0 : (2 + hits))
            end
            lang_bonus = entry.language == :ruby ? 1 : 0
            entry.score = term_score + lang_bonus + recent_edit_bonus(entry.mtime, now) - size_penalty(entry.bytes)
            entry
          end.sort_by { |entry| -entry.score }.first(limit)
        end

        def brief(query = nil, limit: 20, token_limit: DEFAULT_TOKEN_LIMIT)
          rows = query ? relevant(query, limit:) : files.first(limit)
          budgeted_rows(rows, token_limit:)
        end

        private

        def budgeted_rows(rows, token_limit:)
          tokens = 0.0
          rows.filter_map do |entry|
            line = "#{entry.path} #{entry.language} #{entry.bytes}B score=#{format('%.2f', entry.score || 0)}"
            estimate = line.bytesize / TOKEN_BYTES
            next if tokens + estimate > token_limit.to_f

            tokens += estimate
            line
          end
        end

        def files_in_root(base)
          Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH)
             .select { |path| File.file?(path) }
             .reject { |path| ignored?(path, base) }
             .map { |path| entry(path, base) }
        end

        def entry(path, base)
          relative_path = relative(path, base)
          FileEntry.new(
            path: relative_path,
            language: LANGUAGE_BY_EXT.fetch(File.extname(path), :other),
            bytes: File.size(path),
            mtime: File.mtime(path),
            score: 0,
          )
        end

        def ignored?(path, base = @root)
          rel = relative(path, base)
          @ignores.any? { |ignore| rel == ignore || rel.start_with?("#{ignore}/") }
        end

        def relative(path, base = @root)
          rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
          return rel if base == @root || @roots.size == 1

          "#{File.basename(base)}/#{rel}"
        end

        def size_penalty(bytes)
          return 0.0 if bytes < 20_000

          [bytes / 80_000.0, 3.0].min
        end

        def recent_edit_bonus(mtime, now)
          age_hours = [(now - mtime) / 3600.0, 0].max
          return 2.0 if age_hours < 2
          return 1.5 if age_hours < 24
          return 1.0 if age_hours < 72
          return 0.5 if age_hours < 168

          0.0
        end
      end
    end
  end
end
