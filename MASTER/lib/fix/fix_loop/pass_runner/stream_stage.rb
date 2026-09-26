# frozen_string_literal: true

require "set"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Model repairs start as each file's scan lands, not after the whole
        # target is read: a 1,227-file MASTER scan kept every repair waiting
        # half an hour. The scanner hands each file's findings to a queue and
        # one worker repairs them, rule by rule, while the scan moves on.
        # Duplication findings wait for the full scan, because whether they
        # count at all depends on every other file.
        module StreamStage
          STREAM = ENV.fetch("MASTER_FIX_STREAM", "1") != "0"
          # Files repaired at once. One worker left the machine waiting on one
          # model call at a time; files are disjoint, so workers never share one.
          WORKERS = Integer(ENV.fetch("MASTER_FIX_STREAM_WORKERS", 3))
          # One call per file for every finding it holds (FileRepair); 0 keeps
          # the older call per rule.
          FILE_REPAIR = ENV.fetch("MASTER_FIX_FILE_REPAIR", "1") != "0"
          RESOURCE_CHECK_SECONDS = 30

          # What one stream carries from file to file.
          Stream = Struct.new(:streamed, :pass, :breakdown)

          private

          # Returns [found, streamed]: every finding of the scan, and the
          # [file, rule] pairs the worker already took a repair pass at.
          def streaming_observation(files, target, pass, deadline)
            return [run_observation_stage(files, target), Set.new] unless STREAM && files.any?

            streamed = Set.new
            queue = Queue.new
            @stream_stopped_at = nil
            workers = start_workers(queue, streamed, pass, [Time.now + PASS_BUDGET_SECONDS, deadline].min)
            found = stream_violations(files, queue)
            WORKERS.times { queue << :done }
            finish_stream(workers.sum(&:value), found, files, pass)
            found = refresh_streamed_findings(found, streamed)
            StreamCursor.write(@root, target, @stream_stopped_at)
            emit_topology(found, target)
            [found, streamed]
          ensure
            stop_workers(queue, workers)
          end

          def stream_violations(files, queue)
            raw = []
            files.each do |path|
              rows = violations_for(path)
              raw.concat(rows)
              next if rows.empty?

              queue << [path, resolve_violations(rows)]
            end
            resolve_violations(raw)
          end

          def start_workers(queue, streamed, pass, budget)
            Array.new(WORKERS) { Thread.new { drain_repairs(queue, streamed, pass, budget) } }
          end

          # A scan that raised leaves the worker mid-queue: it finishes the
          # file in hand and takes no other, so no write is cut in half.
          def stop_workers(queue, workers)
            live = Array(workers).select(&:alive?)
            return if live.empty?

            queue.clear
            live.size.times { queue << :done }
            live.each(&:join)
          end

          def finish_stream(fixed, found, files, pass)
            return if fixed.zero?

            @committer.commit_if_dirty("fix_loop: stream-fix [pass #{pass}]", findings: found, owned_paths: files)
          end

          # Workers repair concurrently with the scan, so the original finding
          # list can be stale by the time convergence is judged. Re-read only
          # files that a worker actually attempted; untouched files keep the
          # original scan result, preserving the streaming speedup.
          def refresh_streamed_findings(found, streamed)
            touched = streamed.map(&:first).uniq
            return found if touched.empty?

            fresh = touched.flat_map do |relative|
              path = File.expand_path(relative, @root)
              File.exist?(path) ? violations_for(path) : []
            end
            untouched = found.reject { |finding| touched.include?(finding[:file].to_s) }
            resolve_violations(untouched + fresh)
          end
          def drain_repairs(queue, streamed, pass, deadline)
            rules = @rule_order.ordered(violation_counts: @violation_counts)
            stream = Stream.new(streamed, pass, Hash.new(0))
            fixed = 0
            while (item = queue.pop) != :done
              unless stream_repairs_allowed?(pass, deadline)
                # The first file the budget or a reload left unrepaired: the
                # next run starts there.
                @stream_stopped_at ||= item.first if Time.now >= deadline || reload_due?
                next
              end

              fixed += repair_scanned_file(*item, rules, stream)
            end
            report_skip_breakdown(stream.breakdown, pass:)
            fixed
          end

          def repair_scanned_file(path, rows, rules, stream)
            ids = rows.map { |row| row[:rule].to_s }.uniq - ConflictResolver::DRY_RULES
            runnable = rules.select { |rule| ids.include?(rule.id.to_s) }
            return 0 if runnable.empty?

            rel = path.delete_prefix("#{@root}/")
            fixed = if FILE_REPAIR then repair_file(path, rows, runnable, rel, stream)
                    else run_streamed_rules(runnable, path, rel, stream)
                    end
            Master::Trace::Dmesg.status("fix0", "pass #{stream.pass}, #{rel}: #{fixed} of #{rows.size} fixed in stream")
            fixed
          end

          # Every finding of the runnable rules, in one FileRepair.
          def repair_file(path, rows, runnable, rel, stream)
            ids = runnable.map { |rule| rule.id.to_s }
            ids.each { |id| STREAMED_LOCK.synchronize { stream.streamed << [rel, id] } }
            repair_memory.sync_detectors(runnable)
            findings = repair_memory.fresh(path, findings_of(rows, ids, path))
            return 0 if findings.empty?

            repair = FileRepair.new(findings:, rules: runnable, agent: @agent, scanner: @scanner, root: @root,
                                    bus: @bus, learnings: @learnings, committer: @committer)
            result = repair.run(path)
            # Only what the model was asked counts: a split filtered out before the
            # call is no decline, and counting it kept those rules from retiring.
            repair_memory.record(path, repair.asked_rules, result[:breakdown])
            tally_rule_results([[repair.scope, result]], breakdown: stream.breakdown, pass: stream.pass)
          end

          def repair_memory = @repair_memory ||= RepairMemory.new(root: @root)

          # MASTER's own code changed on origin/main: stop taking files.
          def reload_due? = CodeWatch.stale?(@root)

          # The rule stage after the scan asks per rule; it is spared what the
          # model already declined and the rules it has retired, as the stream is.
          def unremembered(found)
            found.group_by { |violation| violation[:file].to_s }.flat_map do |file, violations|
              repair_memory.fresh(File.expand_path(file, @root), violations)
            end
          end

          STREAMED_LOCK = Mutex.new

          def findings_of(rows, ids, path)
            rows.select { |row| ids.include?(row[:rule].to_s) }.map { |row| row.merge(file: path) }
          end

          def run_streamed_rules(runnable, path, rel, stream)
            results = runnable.map do |rule|
              stream.streamed << [rel, rule.id.to_s]
              [rule, run_rule_once(rule, [path], stream.pass)]
            end
            @human_decision_required ||= results.any? { |_rule, result| result[:status] == :human_decision }
            tally_rule_results(results, breakdown: stream.breakdown, pass: stream.pass)
          end

          # Disk and memory are read at most every thirty seconds; the budget's
          # measure shells out, and a file lands every second or two.
          def stream_repairs_allowed?(pass, deadline)
            return false if Time.now >= deadline || circuit_open? || reload_due?
            fresh = @stream_resources_at && Time.now - @stream_resources_at < RESOURCE_CHECK_SECONDS
            return @stream_resources_ok if fresh

            @stream_resources_at = Time.now
            @stream_resources_ok = llm_stage_resources_ok?(pass)
          end

          # What the worker already attempted is not attempted again after the
          # scan; everything else still goes to the council and the rule stage.
          def unstreamed(found, streamed)
            return found if streamed.empty?

            found.reject { |violation| streamed.include?([violation[:file].to_s, violation[:rule].to_s]) }
          end
        end
      end
    end
  end
end
