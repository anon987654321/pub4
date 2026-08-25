# frozen_string_literal: true

module Master
  module Autonomy
    class TaskGraph
      def initialize(tasks)
        @tasks = Array(tasks)
        validate!
      end

      def ready
        @tasks.select { |task| task.state == :ready || (task.state == :pending && dependencies_met?(task)) }
      end

      def terminal?
        @tasks.all? { |task| %i[succeeded failed].include?(task.state) }
      end

      def success?
        @tasks.any? && @tasks.all? { |task| task.state == :succeeded }
      end

      def task(id)
        @tasks.find { |task| task.id == id }
      end

      def replace(task)
        @tasks = @tasks.map { |candidate| candidate.id == task.id ? task : candidate }
        validate!
      end

      def to_a = @tasks.dup

      private

      # A task is ready when its own parent has succeeded, and that is the whole
      # rule. The first clause here also required that nothing depend on the
      # task — which makes every parent permanently unready and inverts the
      # graph: the child waits for the parent, not the parent for the child.
      # With both clauses `ready` returned [] for the two-task case in
      # test_task_graph, so nothing could ever start.
      def dependencies_met?(task)
        @tasks.none? { |candidate| candidate.id == task.parent_id && candidate.state != :succeeded }
      end

      def validate!
        ids = @tasks.map(&:id)
        raise "duplicate task id" unless ids.uniq.length == ids.length

        @tasks.each do |task|
          next unless task.parent_id
          raise "unknown parent #{task.parent_id}" unless ids.include?(task.parent_id)
          raise "task cannot depend on itself" if task.parent_id == task.id
        end

        detect_cycles!
      end

      def detect_cycles!
        @tasks.each do |task|
          seen = {}
          cursor = task
          while cursor&.parent_id
            raise "task dependency cycle at #{cursor.id}" if seen[cursor.id]
            seen[cursor.id] = true
            cursor = @tasks.find { |candidate| candidate.id == cursor.parent_id }
          end
        end
      end
    end
  end
end
