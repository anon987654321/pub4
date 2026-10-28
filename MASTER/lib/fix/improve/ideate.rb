# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../tree_sprawl"
require_relative "../../io/atomic_write"

module Master
  module Fix
    module Improve
      # Ideation: /fix does not only close gaps it can name — it proposes what
      # to build. Ideas come from three mechanical sources, each checkable:
      # the tree's own sprawl (what the shape asks to fix), the code's repeated
      # shapes (what wants to become shared), and the wishlist personas (what a
      # newcomer, an operator and a reviewer each still miss). Ideas are written
      # to a ledger the next /fix reads through the orientation layer, so a run
      # that only ideates still moves the next one.
      class Ideate
        include ::Master::Io::AtomicWrite

        LEDGER_PATH = ".master/fix_ideas.json"
        SCHEMA = 1
        MAX_IDEAS = 12

        Idea = Struct.new(:title, :source, :evidence, :kind, keyword_init: true)

        def initialize(root:)
          @root = File.expand_path(root)
        end

        def generate(files:)
          ideas = sprawl_ideas + twin_ideas(files) + persona_ideas(files)
          write_ledger(ideas.first(MAX_IDEAS))
          ideas
        end

        private

        def sprawl_ideas
          tree = Tree.new(root: @root)
          sprawl = tree.sprawl
          out = []
          Array(sprawl[:single_file_dirs]).first(3).each do |dir|
            out << Idea.new(
              title: "Fold #{dir} into its parent — a folder for one file is a label pretending to be a structure",
              source: "tree_sprawl.single_file_dirs", evidence: dir, kind: :restructure,
            )
          end
          Array(sprawl[:name_twins]).first(2).each do |twin|
            out << Idea.new(
              title: "Merge name twins #{File.basename(twin, '.*')}.* — one concept split across files without a reason",
              source: "tree_sprawl.name_twins", evidence: twin, kind: :restructure,
            )
          end
          out
        rescue StandardError
          []
        end

        def twin_ideas(files)
          repeats = files.group_by { |path| File.basename(path) }
                         .select { |_name, paths| paths.size > 2 && !paths.first.start_with?("RAILS/") }
          repeats.first(2).map do |name, paths|
            Idea.new(
              title: "#{name} appears #{paths.size} times across trees — extract the shared part or state why each copy differs",
              source: "duplication.basename", evidence: paths.first(4).join(", "), kind: :deduplicate,
            )
          end
        end

        # The three personas from the wishlist: what each would still ask for.
        def persona_ideas(files)
          names = files.map { |path| File.basename(path).downcase }
          out = []
          out << Idea.new(
            title: "No top-level ARCHITECTURE.md — a newcomer cannot see how MASTER, RAILS, OPENBSD and STUDIO relate",
            source: "persona.newcomer", evidence: "missing docs/ARCHITECTURE.md", kind: :document,
          ) unless files.any? { |path| path =~ %r{\Adocs/ARCHITECTURE\.md\z} || path =~ %r{\AARCHITECTURE\.md\z} }
          out << Idea.new(
            title: "A single 'make check' style entry: one command that runs MASTER and RAILS suites in order",
            source: "persona.operator", evidence: names.grep(/\bcheck\b/).first(3).join(", "), kind: :tooling,
          )
          out
        end

        def write_ledger(ideas)
          path = File.join(@root, LEDGER_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          payload = {
            schema: SCHEMA,
            generated_at: Time.now.utc.iso8601,
            ideas: ideas.map(&:to_h).map { |hash| hash.transform_keys(&:to_s) },
          }
          write_atomic(path, JSON.pretty_generate(payload) + "\n")
          path
        rescue StandardError
          nil
        end
      end
    end
  end
end
