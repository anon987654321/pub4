# frozen_string_literal: true

require "set"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # An unbounded operator-requested run completes the eligible finding
        # scan before repairs start, then queues files by impact. This replaces
        # alphabetical/easiest-first selection with a traceable importance order.
        # An explicit --max-files cap retains early-stop behavior unless
        # MASTER_FIX_RANK=1 requests full-scan ranking under that cap.
        module StreamStage
          STREAM = ENV.fetch("MASTER_FIX_STREAM", "1") != "0"
          # Files repaired at once. One worker left the machine waiting on one
          # model call at a time; files are disjoint, so workers never share one.
          WORKERS = Integer(ENV.fetch("MASTER_FIX_STREAM_WORKERS", 3))
          # One call per file for every finding it holds (FileRepair); 0 keeps
          # the older call per rule.
          FILE_REPAIR = ENV.fetch("MASTER_FIX_FILE_REPAIR", "1") != "0"
          RESOURCE_CHECK_SECONDS = 30
          # The repair prompt must contain the complete source and every direct
          # file relationship the current graph can prove. If the combined input
          # exceeds this bound, do not silently clip it and proceed with a guess.
          REPAIR_CONTEXT_MAX_BYTES = Integer(ENV.fetch("MASTER_FIX_CONTEXT_MAX_BYTES", 180_000))

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
            found = stream_violations(files, queue, streamed)
            WORKERS.times { queue << :done }
            finish_stream(workers.sum(&:value), found, files, pass)
            found = refresh_streamed_findings(found, streamed)
            StreamCursor.write(@root, target, @stream_stopped_at)
            emit_topology(found, target)
            [found, streamed]
          ensure
            stop_workers(queue, workers)
          end

          def stream_violations(files, queue, streamed = Set.new)
            raw = []
            ranked = []
            rank = rank_worklist?
            limit = rank ? nil : RunLedger.max_files
            taken = 0
            files.each do |path|
              # A limited run stops reading once it holds its files: the semantic scan
              # costs a model call or more per file, and reading all of a 1,666-file
              # tree first kept the first repair hours away.
              break if limit && taken >= limit

              rows = violations_for(path)
              raw.concat(rows)
              next if rows.empty?

              item = [path, resolve_violations(rows)]
              rank ? ranked << item : queue << item
              taken += 1
            end
            enqueue_ranked(ranked, queue, streamed) if rank
            resolve_violations(raw)
          end

          # An unbounded operator-requested run completes the eligible scan before
          # it starts repairs, then orders its worklist by impact. An explicit
          # --max-files bound keeps its early-stop behavior unless ranking was
          # explicitly requested, so bounded runs do not silently become full scans.
          def rank_worklist?
            return true if ENV["MASTER_FIX_RANK"] == "1"
            return false if RunLedger.max_files

            ENV.fetch("MASTER_FIX_RANK", "1") != "0"
          end

          # Severity wins before volume: one error is more urgent than many style
          # findings. Weighted total impact and finding count break ties, then the
          # stable path makes the order reproducible. LawOrder separately enforces
          # the declared dependency order inside each file's repair.
          def enqueue_ranked(ranked, queue, streamed)
            ordered = ranked.sort_by do |path, rows|
              peak, total, count = worklist_priority(rows)
              [-peak, -total, -count, path]
            end
            limit = RunLedger.max_files
            taken, left = limit ? ordered.partition.with_index { |_, index| index < limit } : [ordered, []]
            taken.each { |item| queue << item }
            left.each { |path, rows| rows.each { |row| streamed << [path.delete_prefix("#{@root}/"), row[:law].to_s] } }

            detail = if left.empty?
                       "#{taken.size} file(s)"
                     else
                       "#{taken.size} prioritized file(s), #{left.size} deferred (--max-files #{limit})"
                     end
            Master::Trace::Dmesg.status(
              "fix0",
              "worklist ranked by impact (severity, weighted findings, stable path); " \
              "full eligible scan completed before repair; #{detail}",
            )
          end

          SEVERITY_WEIGHT = {
            veto: 100_000,
            critical: 50_000,
            error: 10_000,
            warning: 1_000,
            warn: 1_000,
            info: 100,
          }.freeze

          def worklist_priority(rows)
            weights = Array(rows).map do |row|
              value = row.is_a?(Hash) ? (row[:severity] || row["severity"]) : nil
              SEVERITY_WEIGHT.fetch(value.to_s.downcase.to_sym, 500)
            end
            [weights.max || 0, weights.sum, weights.size]
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

            @pass_progress = true
            @committer.commit_if_dirty("fix_loop: stream-fix [pass #{pass}]", findings: found, owned_paths: files)
          end

          # Workers repair concurrently with the scan, so the original finding
          # list can be stale by the time convergence is judged. Re-read only
          # files that a worker actually attempted; untouched files keep the
          # original scan result, preserving the streaming speedup.
          def refresh_streamed_findings(found, streamed)
            touched = streamed.map(&:first).uniq
            return found if touched.empty?

            fresh = touched.flat_map { |relative| violations_for(File.expand_path(relative, @root)) }
            untouched = found.reject { |finding| touched.include?(finding[:file].to_s) }
            resolve_violations(untouched + fresh)
          end
          def drain_repairs(queue, streamed, pass, deadline)
            rules = @law_order.ordered(violation_counts: @violation_counts)
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
            ids = rows.map { |row| row[:law].to_s }.uniq - ConflictResolver::DRY_LAWS
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

            context = repair_context(path)
            unless context[:complete]
              @human_decision_required = true
              @bus&.publish("fix_loop:repair_context_incomplete", file: rel, reason: context[:reason])
              Master::Trace::Dmesg.status("understand0", "HUMAN_DECISION, #{rel}: #{context[:reason]}"[0, 200])
              RunLedger.declined("dependency_context_incomplete", file: rel, law: ids.join("+"), detail: context[:reason])
              return 0
            end

            repair = FileRepair.new(
              findings:, rules: runnable, agent: @agent, scanner: @scanner, root: @root,
              bus: @bus, learnings: @learnings, committer: @committer,
              context_files: context[:files], expected_target_sha256: context[:target_sha256],
            )
            result = repair.run(path)
            # Only what the model was asked counts: a split filtered out before the
            # call is no decline, and counting it kept those rules from retiring.
            repair_memory.record(path, repair.asked_rules, result[:breakdown])
            tally_rule_results([[repair.scope, result]], breakdown: stream.breakdown, pass: stream.pass)
          end

          # The dependency graph is built from complete current files before an
          # operator-requested run starts. Read all direct inbound/outbound file
          # relationships in full; never truncate a dependency to fit a prompt.
          # If a file is missing, unreadable, unindexed or the context is too
          # large, the caller is sent to HUMAN_DECISION rather than edited blind.
          def repair_context(path)
            graph = @reference_graph
            return { complete: true, files: [] } unless graph # isolated unit tests only; requested /fix always wires it
            return incomplete_repair_context("target source is not indexed") unless graph.includes_path?(path)

            target_source = File.read(path, encoding: "UTF-8")
            target_sha256 = Digest::SHA256.hexdigest(target_source)
            return incomplete_repair_context("target source changed since dependency graph refresh") \
              unless graph.source_digest(path) == target_sha256

            dynamic_sites = graph.dynamic_for(path)
            unless dynamic_sites.empty?
              site = dynamic_sites.first
              return incomplete_repair_context(
                "target contains unresolved dynamic behavior at #{site[:line]} (#{site[:name]}: #{site[:reason]})",
              )
            end

            radius = graph.blast_radius(path)
            related = (Array(radius[:inbound]) + Array(radius[:outbound])).uniq - [relative]
            adjacent = (related + [relative]).to_set
            unresolved = graph.unresolved_for(path).select { |reference| adjacent.include?(reference[:from_file]) }
            unless unresolved.empty?
              site = unresolved.first
              return incomplete_repair_context(
                "dependency/caller relationship remains unresolved at #{site[:from_file]}:#{site[:line]} " \
                "(#{site[:kind]} #{site[:name]})",
              )
            end

            entries = []
            total_bytes = target_source.bytesize
            if total_bytes > REPAIR_CONTEXT_MAX_BYTES
              return incomplete_repair_context(
                "complete target source is #{total_bytes} bytes, exceeding #{REPAIR_CONTEXT_MAX_BYTES}; no excerpt-only repair was attempted",
              )
            end

            related.sort.each do |rel|
              full = File.expand_path(rel, graph.root)
              return incomplete_repair_context("dependency is a symlink: #{rel}") if File.symlink?(full)
              return incomplete_repair_context("dependency disappeared since graph refresh: #{rel}") unless File.file?(full)

              source = File.read(full, encoding: "UTF-8")
              source_sha256 = Digest::SHA256.hexdigest(source)
              return incomplete_repair_context("dependency changed since graph refresh: #{rel}") \
                unless graph.source_digest(full) == source_sha256

              total_bytes += source.bytesize
              if total_bytes > REPAIR_CONTEXT_MAX_BYTES
                return incomplete_repair_context(
                  "complete source plus #{entries.size + 1} direct dependencies exceeds " \
                  "#{REPAIR_CONTEXT_MAX_BYTES} bytes; no excerpt-only repair was attempted",
                )
              end
              entries << { path: rel, source:, sha256: source_sha256 }
            end

            {
              complete: true,
              files: entries,
              target_sha256:,
            }
          rescue StandardError => e
            incomplete_repair_context("#{e.class}: #{e.message}")
          end

          def incomplete_repair_context(reason)
            { complete: false, reason: reason.to_s[0, 240], files: [] }
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
            rows.select { |row| ids.include?(row[:law].to_s) }.map { |row| row.merge(file: path) }
          end

          def run_streamed_rules(runnable, path, rel, stream)
            results = runnable.map do |rule|
              stream.streamed << [rel, rule.id.to_s]
              [rule, run_law_once(rule, [path], stream.pass)]
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

            found.reject { |violation| streamed.include?([violation[:file].to_s, violation[:law].to_s]) }
          end
        end
      end
    end
  end
end
