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
            worker = Thread.new { drain_repairs(queue, streamed, pass, [Time.now + PASS_BUDGET_SECONDS, deadline].min) }
            found = @loop_scanner.violations(files) { |path, rows| queue << [path, rows] }
            queue << :done
            finish_stream(worker.value, found, files, pass)
            emit_topology(found, target)
            [found, streamed]
          ensure
            stop_worker(queue, worker)
          end

          # A scan that raised leaves the worker mid-queue: it finishes the
          # file in hand and takes no other, so no write is cut in half.
          def stop_worker(queue, worker)
            return unless worker&.alive?

            queue.clear
            queue << :done
            worker.join
          end

          def finish_stream(fixed, found, files, pass)
            return if fixed.zero?

            @committer.commit_if_dirty("fix_loop: stream-fix [pass #{pass}]", findings: found, owned_paths: files)
          end

          def drain_repairs(queue, streamed, pass, deadline)
            rules = @rule_order.ordered(violation_counts: @violation_counts)
            stream = Stream.new(streamed, pass, Hash.new(0))
            fixed = 0
            while (item = queue.pop) != :done
              next unless stream_repairs_allowed?(pass, deadline)

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
            fixed = run_streamed_rules(runnable, path, rel, stream)
            Master::Trace::Dmesg.status("fix0", "pass #{stream.pass}, #{rel}: #{fixed} of #{rows.size} fixed in stream")
            fixed
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
            return false if Time.now >= deadline || circuit_open?
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
