# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Observer
        # The Observer records reality. It does not judge.
        # It produces a snapshot of the system state.
        class SystemState
          attr_reader :timestamp, :git_head, :dirty, :files_count, :processes, :ruby_version

          def initialize(root:)
            @timestamp = Time.now
            @root = root
            @git_head = capture_git_head
            @dirty = check_dirty
            @files_count = count_files
            @processes = count_processes
            @ruby_version = RUBY_VERSION
          end

          def to_h
            {
              timestamp: @timestamp,
              git_head: @git_head,
              dirty: @dirty,
              files_count: @files_count,
              processes: @processes,
              ruby_version: @ruby_version,
            }
          end

          def to_s
            "observer0:\n" \
            "  git_head=#{@git_head}\n" \
            "  dirty=#{@dirty}\n" \
            "  files=#{@files_count}\n" \
            "  processes=#{@processes}\n" \
            "  ruby=#{@ruby_version}"
          end

          private

          def capture_git_head
            `git -C #{@root} rev-parse HEAD`.strip rescue "unknown"
          end

          def check_dirty
            !`git -C #{@root} status --porcelain`.strip.empty?
          end

          def count_files
            Dir.glob(File.join(@root, "**/*")).count
          end

          def count_processes
            `ps aux | wc -l`.strip.to_i rescue 0
          end
        end
      end
    end
  end
end
