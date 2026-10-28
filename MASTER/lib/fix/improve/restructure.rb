# frozen_string_literal: true

require_relative "../tree"

module Master
  module Fix
    module Improve
      # The defragmentation drive: turn TreeSprawl signals into restructure
      # proposals that respect the path contracts. A proposal is only emitted
      # when the target path is owned by the repository itself (PATH_OWNERSHIP
      # governs who may move what), so elevation never drags a contracted path
      # out from under a test that asserts it.
      class Restructure
        # A merge is contract-safe when the only references are requires that
        # move with the file. This drive therefore proposes, and lets
        # restructure_sweep's proof machinery (syntax, rails_proof, master_proof)
        # verify an accepted proposal before anything is applied.
        Proposal = Struct.new(:kind, :from, :to, :reason, keyword_init: true)

        MAX_PROPOSALS = 6
        TINY_LINES = 24

        def initialize(root:)
          @root = File.expand_path(root)
        end

        def proposals(files:)
          evidence = Tree.new(root: @root).sprawl
          tiny = evidence.fetch(:tiny_files, []).select { |path| path.end_with?(".rb") }
          singles = evidence.fetch(:single_file_dirs, [])
          list = []
          tiny.first(MAX_PROPOSALS).each do |path|
            target = merge_target_for(path)
            next unless target

            list << Proposal.new(
              kind: :merge, from: path, to: target,
              reason: "#{path.sub("#{@root}/", "")} carries fewer than #{TINY_LINES} lines; its content belongs inside #{target.sub("#{@root}/", "")}",
            )
          end
          singles.first(2).each do |dir|
            member = files.find { |path| path.start_with?(dir) }
            next unless member

            list << Proposal.new(
              kind: :flatten, from: member, to: File.join(File.dirname(dir), File.basename(member)),
              reason: "#{dir.sub("#{@root}/", "")} holds one file; a folder is structure a single file cannot justify",
            )
          end
          list
        rescue StandardError
          []
        end

        private

        def merge_target_for(path)
          lines = File.readlines(path, encoding: "UTF-8", invalid: :replace).size
          return nil unless lines < TINY_LINES

          parent = File.dirname(File.dirname(path))
          stem = File.basename(File.dirname(path))
          candidate = File.join(parent, "#{stem}.rb")
          return nil unless File.file?(candidate)

          candidate
        end
      end
    end
  end
end
