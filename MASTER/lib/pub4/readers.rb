# frozen_string_literal: true

require "set"

module Pub4
  # Who reaches a file, across all four trees, by every spelling this repo
  # actually uses.
  #
  # This exists because "its only reader is X" has been wrong four times, and
  # each time it was wrong the same way: someone counted readers with a grep
  # that could not see the reference that mattered.
  #
  #   hash_dig_compat.rb  merged into MASTER/test/test_helper.rb as "its only
  #                       reader". STUDIO's dilla/lib/music_gems.rb required it
  #                       by File.expand_path from another tree, inside a
  #                       `rescue LoadError`, so it did not even raise — dilla
  #                       rendered without coltrane for days.
  #   RepoMap             renamed on a reader count that missed a same-named
  #                       class in a different namespace.
  #   _search_loading     deleted as unused; it is the shared partial a contract
  #                       test asserts.
  #   Log::Evidence       deleted as dead; specified-but-unused is not dead, and
  #                       it had a test.
  #
  # The spellings below are the ones that defeated those greps. A basename
  # search alone finds none of the path-built requires; a `require_relative`
  # search alone finds none of the runtime `File.expand_path` ones.
  class Readers
    TREES = %w[MASTER RAILS OPENBSD STUDIO bin dotfiles].freeze

    # knowledge/ and output/ are vendored or generated and are never committed;
    # a word in someone else's system prompt is not a reader.
    SKIP = %r{/(\.git|vendor|node_modules|tmp|log|coverage|\.bundle|knowledge|output)/}

    Reference = Struct.new(:path, :line, :text, :kind, keyword_init: true)

    def self.find(root:, target:)
      new(root: root, target: target).run
    end

    def initialize(root:, target:)
      @root = root
      @target = target
      @absolute = File.expand_path(target, root)
      @basename = File.basename(target)
      # Every extension, not just the last: a Rails partial is
      # _search_loading.html.erb and is rendered as "shared/search_loading",
      # so a stem of "_search_loading.html" matches neither the file nor the
      # render.
      @stem = @basename.sub(/\..*\z/, "")
      # Partials are declared with a leading underscore and referenced without
      # one. _search_loading was deleted as unused on a grep for the filename;
      # every caller spells it search_loading.
      @partial = @stem.sub(/\A_/, "")
      # The Zeitwerk name, computed once. A prefilter on the snake form alone
      # misses every multi-word constant: code_metrics.rb is reached as
      # Master::Review::Scan::CodeMetrics, and "codemetrics" does not contain
      # "code_metrics" at any casing. That was a false negative on a file the
      # Rakefile uses in four places, which is the one failure this tool is not
      # allowed to have.
      @camel = @partial.split(/[_\-]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join
    end

    # Every distinct way this tree names a file. Kept as one list so a new
    # spelling is added once and every caller gets it.
    #
    # `constant` is the Zeitwerk inverse: lib/ground/policy/sandbox.rb is
    # Ground::Policy::Sandbox, and a file can be reached by that name with no
    # textual reference to its path at all.
    def patterns
      camel = @camel
      {
        basename: /#{Regexp.escape(@basename)}/,
        stem: /\b#{Regexp.escape(@stem)}\b/,
        partial: /\b#{Regexp.escape(@partial)}\b/,
        quoted: /["'][^"']*#{Regexp.escape(@stem)}[^"']*["']/,
        constant: /\b#{Regexp.escape(camel)}\b/,
      }
    end

    def run
      hits = []
      each_file do |path|
        next if File.expand_path(path) == @absolute

        body = File.read(path, encoding: "UTF-8")
        # Case-insensitive, and on the partial form. This is only a speed
        # filter, but it was narrower than the patterns it guards: @stem is
        # "sandbox" and the constant reference reads Ground::Policy::Sandbox,
        # so a case-sensitive include? skipped the file before any pattern ran.
        # Same for a partial, where @stem is "_search_loading" and every caller
        # writes "shared/search_loading". A prefilter that rejects what the
        # matcher would have accepted is just a silent false negative.
        next unless body.downcase.include?(@partial.downcase) ||
                    body.include?(@camel)

        body.each_line.with_index(1) do |line, lineno|
          kind = classify(line, path)
          next unless kind

          hits << Reference.new(path: rel(path), line: lineno, text: line.strip, kind: kind)
        end
      rescue ArgumentError
        next # binary
      end
      hits
    end

    private

    def rel(path) = path.sub("#{@root}/", "")

    # Ordered: the most specific spelling wins, so a `require_relative` line is
    # not also reported as a bare mention.
    def classify(line, path)
      # Prose cannot break. A constant named in DEBT.md or DECISIONS.md is a
      # record of a decision, not a caller, and counting it as one puts every
      # well-documented file above the threshold — which would make the number
      # at the bottom of this report useless exactly where the repo is at its
      # most careful.
      prose = path.match?(/\.(md|markdown|txt|yml|yaml|json)\z/)
      pats = patterns
      return :require if line.match?(/\brequire(_relative)?\b/) &&
                         (line.match?(pats[:basename]) || line.match?(pats[:stem]))
      # The one that hid hash_dig_compat: a path assembled at runtime, with the
      # extension left off, inside a require.
      # The stem has to be inside a quoted string on the line, not merely on it.
      # Without that, Constitution.load(data_dir: File.expand_path(...), sandbox:)
      # counted as a path reference to ground/policy/sandbox.rb, because the
      # keyword argument happens to share the word.
      return :path_build if line.match?(/File\.(expand_path|join)/) && line.match?(pats[:quoted])
      # A view rendered by name breaks exactly as hard as a require does.
      return :render if line.match?(/\brender\b|\bpartial:/) && line.match?(pats[:partial])
      return(prose ? :mention : :constant) if line.match?(pats[:constant])
      # A test that names the file is the tripwire that fires on delete, even
      # when nothing in the app reaches it. _search_loading has no renderer at
      # all — its only reference is deploy_gates_contract_test asserting it is
      # there — and reporting that as an ordinary mention is how it got deleted.
      # The basename only. Matching the bare word here made `def
      # constitution(sandbox: nil)` a reference to ground/policy/sandbox.rb —
      # 54 of them in MASTER's tests, all keyword arguments. A test that names
      # a file spells the filename.
      return :test if path.match?(%r{/(test|spec)/|_test\.rb\z|_spec\.rb\z}) &&
                      line.match?(pats[:basename])
      return :mention if line.match?(pats[:basename])

      nil
    end

    def each_file(&block)
      TREES.each do |tree|
        base = File.join(@root, tree)
        next unless File.exist?(base)

        Dir.glob(File.join(base, "**", "*")).each do |path|
          next if path.match?(SKIP)
          next unless File.file?(path)
          next if File.size(path) > 2_000_000

          block.call(path)
        end
      end
    end
  end
end
