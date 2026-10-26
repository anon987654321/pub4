# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "../io/atomic_write"
require_relative "reminder_time"

module Master
  module Ground
    # Subject-scoped, owner-local task board for personal work. It records steps and
    # the evidence supplied when a step is verified; it does not execute commands
    # or pretend that a recorded claim is independent proof.
    class AssistantTasks
      include Master::Io::AtomicWrite

      class Error < StandardError; end
      VERSION = 1
      MAX_TASKS = 200
      MAX_STEPS = 32
      MAX_EVENTS = 256
      MAX_FILE_BYTES = 512 * 1024
      MAX_TITLE_BYTES = 200
      MAX_DESCRIPTION_BYTES = 2_000
      MAX_NOTE_BYTES = 1_200
      TASK_STATES = %w[open in_progress blocked completed].freeze
      STEP_STATES = %w[pending in_progress blocked verified].freeze
      PRIORITIES = %w[low normal high].freeze
      MUTATIONS = %w[create update add_step start_step block_step verify_step block resume complete reminded].freeze
      # Said when a due time is accepted, so no one is told a reminder will ring that will not.
      DELIVERY = "Rings in an open interactive MASTER session (bin/master) once it is due; " \
                 "nothing rings while no session is open.".freeze

      def initialize(root: Master::ROOT, subject: nil, bus: nil, clock: -> { Time.now.utc })
        @root = File.expand_path(root)
        @subject = resolve_subject(subject)
        raise Error, "personal task subject is unavailable" if @subject.to_s.empty?

        @directory = File.join(@root, ".master", "workspace", sanitize(@subject))
        @path = File.join(@directory, "TASKS.json")
        @lock_path = File.join(@directory, "tasks.lock")
        @bus = bus
        @clock = clock
      end

      def call(action:, id: nil, title: nil, description: nil, due_at: nil, priority: nil,
               step_id: nil, step_title: nil, evidence: nil, note: nil, query: nil)
        raise Error, "personal task access is local-owner only" if Fiber[:master_visitor] == true

        action = action.to_s
        raise Error, "unknown task action: #{action}" unless (%w[list show] + MUTATIONS).include?(action)

        with_lock do
          state = read_state
          result = dispatch(state, action, id:, title:, description:, due_at:, priority:,
                            step_id:, step_title:, evidence:, note:, query:)
          if MUTATIONS.include?(action)
            append_event(state, action, result)
            persist!(state)
            @bus&.publish("assistant_task:changed", action:, task_id: result["id"] || id.to_s)
          end
          result
        end
      rescue JSON::ParserError => e
        raise Error, "task ledger is corrupt; no data was overwritten (#{e.message})"
      end

      # Tasks whose due time has passed, not completed and not yet rung.
      def due_reminders
        current = Time.iso8601(now)
        with_lock do
          read_state.fetch("tasks").select do |task|
            task["state"] != "completed" && task["reminded_at"].nil? && overdue?(task, current)
          end.map { |task| public_task(task) }
        end
      end

      private

      def dispatch(state, action, id:, title:, description:, due_at:, priority:,
                   step_id:, step_title:, evidence:, note:, query:)
        case action
        when "list" then list_tasks(state, query)
        when "show" then task!(state, id).dup
        when "create" then create!(state, title:, description:, due_at:, priority:)
        when "update" then update!(state, id, title:, description:, due_at:, priority:)
        when "add_step" then add_step!(state, id, step_id:, step_title:)
        when "start_step" then update_step!(state, id, step_id:, state_name: "in_progress", note:)
        when "block_step" then update_step!(state, id, step_id:, state_name: "blocked", note:)
        when "verify_step" then verify_step!(state, id, step_id:, evidence:)
        when "block" then block!(state, id, note:)
        when "resume" then resume!(state, id, note:)
        when "complete" then complete!(state, id, evidence:)
        when "reminded" then reminded!(state, id)
        end
      end

      def list_tasks(state, query)
        needle = query.to_s.strip.downcase
        rows = state.fetch("tasks").select do |task|
          needle.empty? || [task["id"], task["title"], task["description"], task["state"]]
            .compact.any? { |value| value.to_s.downcase.include?(needle) }
        end
        rows = rows.sort_by do |task|
          [task["state"] == "completed" ? 1 : 0, task["due_at"].to_s.empty? ? 1 : 0,
           task["due_at"].to_s, task["created_at"].to_s]
        end
        current_time = Time.iso8601(now)
        {
          "status" => "ok",
          "count" => rows.size,
          "tasks" => rows.first(50).map { |task| public_task(task).merge("overdue" => overdue?(task, current_time)) },
          "truncated" => rows.size > 50,
          "note" => "Overdue tasks are labeled when listed. #{DELIVERY}"
        }
      end

      def create!(state, title:, description:, due_at:, priority:)
        clean_title = required_text(title, "title", MAX_TITLE_BYTES)
        raise Error, "task limit reached (#{MAX_TASKS})" if state.fetch("tasks").size >= MAX_TASKS

        task = {
          "id" => SecureRandom.hex(6),
          "title" => clean_title,
          "description" => bounded_text(description, MAX_DESCRIPTION_BYTES),
          "priority" => normalize_priority(priority || "normal"),
          "due_at" => normalize_due(due_at),
          "reminded_at" => nil,
          "state" => "open",
          "steps" => [],
          "verification_note" => nil,
          "created_at" => now,
          "updated_at" => now,
          "completed_at" => nil
        }
        state["tasks"] << task
        delivered(public_task(task))
      end

      def delivered(task) = task["due_at"] ? task.merge("delivery" => DELIVERY) : task

      def reminded!(state, id)
        task = task!(state, id)
        task["reminded_at"] = now
        public_task(task)
      end

      def update!(state, id, title:, description:, due_at:, priority:)
        task = task!(state, id)
        raise Error, "completed tasks cannot be edited; reopen by creating a follow-up task" if task["state"] == "completed"
        raise Error, "blocked tasks need an explicit resume before they are edited" if task["state"] == "blocked"

        task["title"] = required_text(title, "title", MAX_TITLE_BYTES) unless title.nil?
        task["description"] = bounded_text(description, MAX_DESCRIPTION_BYTES) unless description.nil?
        task["priority"] = normalize_priority(priority) unless priority.nil?
        unless due_at.nil?
          task["due_at"] = normalize_due(due_at)
          task["reminded_at"] = nil
        end
        task["updated_at"] = now
        public_task(task)
      end

      def add_step!(state, id, step_id:, step_title:)
        task = task!(state, id)
        require_open!(task)
        steps = task.fetch("steps")
        raise Error, "step limit reached (#{MAX_STEPS})" if steps.size >= MAX_STEPS

        label = required_text(step_title, "step_title", MAX_TITLE_BYTES)
        key = step_id.to_s.strip
        key = "s#{SecureRandom.hex(3)}" if key.empty?
        raise Error, "invalid step_id" unless key.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}\z/)
        raise Error, "duplicate step_id" if steps.any? { |step| step["id"] == key }

        step = {
          "id" => key, "title" => label, "state" => "pending", "attempts" => 0,
          "evidence" => nil, "note" => nil, "updated_at" => now
        }
        steps << step
        task["updated_at"] = now
        { "task_id" => task["id"], "step" => step.dup }
      end

      def update_step!(state, id, step_id:, state_name:, note:)
        task = task!(state, id)
        require_open!(task)
        step = step!(task, step_id)
        raise Error, "verified steps are immutable; add a follow-up step if work changed" if step["state"] == "verified"

        detail = required_text(note, "note", MAX_NOTE_BYTES)
        step["state"] = state_name
        step["attempts"] = step.fetch("attempts", 0).to_i + 1 if state_name == "in_progress"
        step["note"] = detail
        step["evidence"] = nil
        step["updated_at"] = now
        task["state"] = "in_progress" if state_name == "in_progress"
        task["state"] = "blocked" if state_name == "blocked"
        task["updated_at"] = now
        { "task_id" => task["id"], "step" => step.dup }
      end

      def verify_step!(state, id, step_id:, evidence:)
        task = task!(state, id)
        require_open!(task)
        step = step!(task, step_id)
        detail = required_text(evidence, "evidence", MAX_NOTE_BYTES)
        raise Error, "a blocked step must be resumed before verification" if step["state"] == "blocked"

        step["state"] = "verified"
        step["evidence"] = detail
        step["note"] = nil
        step["updated_at"] = now
        task["state"] = "in_progress" if task["state"] == "open"
        task["updated_at"] = now
        {
          "task_id" => task["id"],
          "step" => step.dup,
          "verification_semantics" => "evidence recorded as supplied; not independently authenticated"
        }
      end

      def block!(state, id, note:)
        task = task!(state, id)
        require_open!(task)
        task["state"] = "blocked"
        task["verification_note"] = required_text(note, "note", MAX_NOTE_BYTES)
        task["updated_at"] = now
        public_task(task)
      end

      def resume!(state, id, note:)
        task = task!(state, id)
        raise Error, "only blocked tasks can be resumed" unless task["state"] == "blocked"

        task["state"] = task["steps"].any? { |step| step["state"] == "in_progress" } ? "in_progress" : "open"
        task["verification_note"] = bounded_text(note, MAX_NOTE_BYTES)
        task["updated_at"] = now
        public_task(task)
      end

      def complete!(state, id, evidence:)
        task = task!(state, id)
        require_open!(task)
        pending = task.fetch("steps").reject { |step| step["state"] == "verified" }
        raise Error, "cannot complete: #{pending.size} step(s) lack verification" if pending.any?

        task["verification_note"] = required_text(evidence, "evidence", MAX_NOTE_BYTES)
        task["state"] = "completed"
        task["completed_at"] = now
        task["updated_at"] = now
        public_task(task).merge("verification_semantics" => "completion recorded against supplied evidence; not independently authenticated")
      end

      def task!(state, id)
        key = required_text(id, "id", 40)
        state.fetch("tasks").find { |task| task["id"] == key } || raise(Error, "task not found: #{key}")
      end

      def step!(task, step_id)
        key = required_text(step_id, "step_id", 40)
        task.fetch("steps").find { |step| step["id"] == key } || raise(Error, "step not found: #{key}")
      end

      def require_open!(task)
        raise Error, "task is #{task["state"]}; resume it before changing progress" unless %w[open in_progress].include?(task["state"])
      end

      def normalize_priority(value)
        priority = value.to_s.downcase
        raise Error, "priority must be low, normal or high" unless PRIORITIES.include?(priority)

        priority
      end

      def normalize_due(value)
        return nil if value.nil? || value.to_s.strip.empty? || value.to_s.strip.downcase == "none"

        due = ReminderTime.resolve(value, zone: owner_zone, now: Time.iso8601(now))
        return due.iso8601 if due

        raise Error, "due_at must be an ISO-8601 time, a clock time such as \"tomorrow at 9\" or \"i morgen kl 9\", " \
                     "a delay such as \"in 20 minutes\", or none to clear it"
      end

      # The owner profile's timezone, else the process's own.
      def owner_zone
        Master::Device::OwnerProfile.values(root: @root, subject: @subject)["timezone"]
      rescue StandardError
        nil
      end

      def required_text(value, name, max_bytes)
        text = value.to_s.strip
        raise Error, "#{name} is required" if text.empty?
        raise Error, "#{name} is too long" if text.bytesize > max_bytes

        text
      end

      def bounded_text(value, max_bytes)
        text = value.to_s.strip
        raise Error, "text is too long" if text.bytesize > max_bytes

        text
      end

      def public_task(task)
        task.each_with_object({}) do |(key, value), out|
          out[key] = value.is_a?(Array) ? value.map(&:dup) : value
        end
      end

      def append_event(state, action, result)
        id = result.is_a?(Hash) ? result["id"] || result["task_id"] : nil
        state.fetch("events") << {
          "at" => now,
          "action" => action,
          "task_id" => id.to_s.empty? ? nil : id.to_s,
          "actor" => @subject.start_with?("local-uid-") ? "local-owner" : "paired-owner"
        }
        state["events"] = state.fetch("events").last(MAX_EVENTS)
      end

      def read_state
        raise Error, "refusing symlinked task ledger" if File.symlink?(@path)
        return { "schema" => VERSION, "tasks" => [], "events" => [] } unless File.exist?(@path)
        raise Error, "task ledger is too large to read safely" if File.size(@path) > MAX_FILE_BYTES
        raise Error, "task ledger is not a regular file" unless File.file?(@path)

        data = JSON.parse(File.read(@path, encoding: "UTF-8"))
        valid_tasks = data.is_a?(Hash) && data["schema"] == VERSION && data["tasks"].is_a?(Array) &&
                      data["events"].is_a?(Array) && data["tasks"].size <= MAX_TASKS &&
                      data["events"].size <= MAX_EVENTS &&
                      data["tasks"].all? { |task| valid_task?(task) } &&
                      data["events"].all? { |event| event.is_a?(Hash) }
        raise Error, "task ledger has an unsupported or invalid shape" unless valid_tasks

        data
      end

      def valid_task?(task)
        task.is_a?(Hash) && task["id"].is_a?(String) && task["title"].is_a?(String) &&
          TASK_STATES.include?(task["state"]) && task["steps"].is_a?(Array) && task["steps"].size <= MAX_STEPS &&
          task["steps"].all? do |step|
            step.is_a?(Hash) && step["id"].is_a?(String) && STEP_STATES.include?(step["state"])
          end
      end

      def overdue?(task, current_time)
        due = task["due_at"].to_s
        return false if due.empty? || task["state"] == "completed"

        Time.iso8601(due) < current_time
      rescue ArgumentError
        false
      end

      def persist!(state)
        write_atomic(@path, JSON.pretty_generate(state) + "\n", mode: 0o600)
      end

      def with_lock
        secure_directory!
        raise Error, "refusing symlinked task lock" if File.symlink?(@lock_path)

        File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN)
        end
      end

      def secure_directory!
        master_dir = File.join(@root, ".master")
        workspace_dir = File.join(@root, ".master", "workspace")
        raise Error, "refusing symlinked .master directory" if File.symlink?(master_dir)
        FileUtils.mkdir_p(master_dir, mode: 0o700)
        raise Error, ".master path is not a directory" unless File.directory?(master_dir)

        raise Error, "refusing symlinked personal workspace directory" if File.symlink?(workspace_dir)
        FileUtils.mkdir_p(workspace_dir, mode: 0o700)
        File.chmod(0o700, workspace_dir)
        raise Error, "refusing symlinked personal task directory" if File.symlink?(@directory)
        FileUtils.mkdir_p(@directory, mode: 0o700)
        File.chmod(0o700, @directory)
      end

      def resolve_subject(subject)
        value = subject.to_s.strip
        value = Fiber[:master_pair_subject].to_s.strip if value.empty?
        return value unless value.empty?
        return if Fiber[:master_visitor] == true

        "local-uid-#{Process.uid}"
      end

      def sanitize(subject)
        value = subject.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")[0, 32]
        raise Error, "personal task subject is invalid" if value.to_s.empty? || %w[. ..].include?(value)

        value
      end

      def now
        value = @clock.call
        raise Error, "clock must return Time" unless value.is_a?(Time)

        value.utc.iso8601(6)
      end
    end
  end
end
