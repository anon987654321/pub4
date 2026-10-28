# frozen_string_literal: true

require "set"
require_relative "../../check_focus"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # An unbounded operator-requested run ranks findings by impact in batches
        # of RANK_WINDOW files and queues each batch as it is read, so repairs run
        # while the scan continues.
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
            workers = start_workers(queue, streamed, pass, deadline)
            found = stream_violations(files, queue, streamed, deadline:)
            WORKERS.times { queue << :done }
            finish_stream(workers.sum(&:value), found, files, pass)
            found = refresh_streamed_findings(found, streamed)
            StreamCursor.write(@root, target, @stream_stopped_at)
            emit_topology(found, target)
            [found, streamed]
          ensure
            stop_workers(queue, workers)
          end

          # The scan reads the corpus mechanically and queues repairs as it goes; the semantic reads it
          # puts off are made afterwards, under the pass's budget, while the workers repair.
          def stream_violations(files, queue, streamed = Set.new, deadline: nil)
            flusher = ->(batch) { enqueue_ranked(batch, queue, streamed) }
            ranked = rank_worklist?
            worklist = Worklist.new(queue, ranked ? [] : nil, rank_window, flusher, 0)
            # Bounded early-stop runs intentionally retain scan-order selection;
            # ranked runs apply the allowance after priority is known per batch.
            cap = LawCap.new(LAW_CAP, Hash.new(0)) unless ranked

            raw = []
            put_off = []
            semantic_deferred(put_off) do
              CheckFocus.first(files).each do |path|
                break if scan_stop?(path, worklist.taken, deadline)

                rows = violations_for(path)
                raw.concat(rows)
                repairs = resolve_violations(rows)
                repairs = cap.take(repairs) if cap && !CheckFocus.covers?(path)
                worklist.add([path, repairs]) unless repairs.empty?
              end
            end

            worklist.flush
            resolve_violations(read_put_off(raw, put_off:, deadline:))
          end

          # A pass's allowance of semantic reads, by files and by seconds, whichever ends first. The
          # reads share the model lane with the repairs; unbounded, twenty of them fill a 30-minute pass
          # and leave the repairs none of it. FindingCache keeps every answer, and
          # StreamCursor.semantic_order resumes past the last file read, so a file a pass leaves unread
          # is a later pass's and every due file is still read across passes and runs.
          SEMANTIC_FILES = Integer(ENV.fetch("MASTER_FIX_SEMANTIC_FILES", 3))
          SEMANTIC_SECONDS = Integer(ENV.fetch("MASTER_FIX_SEMANTIC_SECONDS", 240))
          PENDING = "semantic read due, left for a later pass by the pass's budget"

          SemanticBudget = Struct.new(:files, :seconds, :read, :spent) do
            def self.per_pass = new(SEMANTIC_FILES, SEMANTIC_SECONDS, 0, 0.0)

            def open? = read < files && spent < seconds

            def charge(elapsed)
              self.read += 1
              self.spent += elapsed
            end
          end

          # Files whose semantic read is due and not yet made. They keep a run from DONE as an
          # inconclusive read does: a file the model has not read has not been measured clean.
          def semantic_pending = (@semantic_pending ||= {})

          def pass_semantic_budget = SemanticBudget.per_pass

          # A runner without a scan phase, as a unit test's is, reads as it always did.
          def semantic_deferred(into, &) = @scan_phase ? @scan_phase.deferring_semantic(into, &) : yield
          def semantic_budgeted(budget, &) = @scan_phase ? @scan_phase.budgeting_semantic(budget, &) : yield

          # A file read here has its rows replaced by the whole reading. Its new findings go to the rule
          # stage after the stream rather than to a worker, which may hold the file now.
          def read_put_off(raw, put_off:, deadline:, advance_cursor: true)
            due = StreamCursor.semantic_order(@root, put_off.uniq)
            budget = pass_semantic_budget
            read = []
            semantic_budgeted(budget) do
              due.each do |path|
                break unless semantic_turn?(budget, deadline)

                raw = replace_rows(raw, violations_for(path), path:)
                read << path
              end
            end

            settle_semantic(due, read, advance_cursor:)
            raw
          end

          # A preview measures deterministic findings across the corpus but makes only
          # one pass-budget of semantic reads. Pending files remain visible as gaps.
          # Unlike repair, preview must not move the persistent cursor used by future runs.
          def preview_violations(files)
            paths = Array(files)
            @scan_total = paths.size
            put_off = []
            raw = semantic_deferred(put_off) do
              paths.flat_map { |path| violations_for(path) }
            end
            resolve_violations(
              read_put_off(raw, put_off:, deadline: nil, advance_cursor: false),
            )
          end
          public :preview_violations

          def semantic_turn?(budget, deadline)
            budget.open? && !RunBudget.stopping && !(deadline && Time.now >= deadline)
          end

          def replace_rows(raw, rows, path:)
            relative = path.delete_prefix("#{@root}/")
            raw.reject { |row| row[:file].to_s == relative } + rows
          end

          def settle_semantic(due, read, advance_cursor: true)
            return if due.empty?

            StreamCursor.mark_semantic(@root, read.last) if advance_cursor && read.any?
            note_pending(due - read)
            read.each { |path| semantic_pending.delete(path.delete_prefix("#{@root}/")) }
            Master::Trace::Dmesg.status(
              "scan0", "semantic: read #{read.size} of #{due.size} put-off file(s); the rest wait for later passes"
            )
          end

          def note_pending(paths)
            paths.each { |path| semantic_pending[path.delete_prefix("#{@root}/")] = PENDING }
          end

          # A limited run stops reading once it holds its files: the semantic scan costs a model call
          # or more per file, and reading all of a 1,666-file tree first kept the first repair hours
          # away. Every run stops at its deadline and records the file it stopped at.
          def scan_stop?(path, taken, deadline)
            limit = rank_worklist? ? nil : RunLedger.max_files
            return true if limit && taken >= limit
            return false unless RunBudget.stopping || (deadline && Time.now >= deadline)

            @stream_stopped_at ||= path
            true
          end

          # Repairs per law per ranked batch. LONG_LINE alone fired on 2,699 lines of one scan, and every one went
          # to the model before any other law got a turn. Priority is established before the cap is applied;
          # excess findings still count and report, and red-check files are never capped.
          LAW_CAP = Integer(ENV.fetch("MASTER_FIX_LAW_CAP", 25))

          LawCap = Struct.new(:limit, :counts) do
            def take(rows) = rows.select { |row| (counts[row[:law].to_s] += 1) <= limit }
          end

          # Queues each scanned file, or holds it for ranking and queues the batch once it is full.
          Worklist = Struct.new(:queue, :ranked, :window, :flusher, :taken) do
            def add(item)
              self.taken += 1
              return queue << item unless ranked

              ranked << item
              flush if ranked.size >= window
            end

            def flush
              flusher.call(ranked.slice!(0..)) if ranked&.any?
            end
          end

          # Files ranked together before they are queued. Ranking the whole corpus first held every
          # repair until a model had read every file, hours on a large tree, while the workers' budget ran
          # out; a window keeps severity order within each batch and repairs begin after the first one.
          # A run limited by --max-files with MASTER_FIX_RANK=1 still ranks the full scan.
          RANK_WINDOW = Integer(ENV.fetch("MASTER_FIX_RANK_WINDOW", 20))

          def rank_window = RunLedger.max_files ? Float::INFINITY : RANK_WINDOW

          # Unbounded runs rank rolling windows by impact, so repair can begin
          # before the full scan ends. --max-files keeps early-stop behavior
          # unless MASTER_FIX_RANK=1 explicitly requests a full ranked scan.
          def rank_worklist?
            return true if ENV["MASTER_FIX_RANK"] == "1"
            return false if RunLedger.max_files

            ENV.fetch("MASTER_FIX_RANK", "1") != "0"
          end

          # What users meet comes first (LawOrder.impact: runtime, then rendered, then code), then a
          # file a red check names (CheckFocus). Then severity before volume: one error is more urgent
          # than many style findings; weighted impact, count and the stable path break ties. LawOrder
          # separately enforces the declared dependency order inside each file's repair.
          def enqueue_ranked(ranked, queue, streamed)
            ordered = ranked.sort_by do |path, rows|
              peak, total, count = worklist_priority(rows)
              [LawOrder.file_impact(rows), CheckFocus.covers?(path) ? 0 : 1, -peak, -total, -count, path]
            end

            # The stream intentionally starts repairs before the whole corpus has
            # been scanned. Enforce the law allowance within each ranked batch,
            # after priority is known, so scan order cannot starve urgent findings.
            cap = LawCap.new(LAW_CAP, Hash.new(0))
            ordered = ordered.filter_map do |path, rows|
              selected = CheckFocus.covers?(path) ? rows : cap.take(rows)
              [path, selected] unless selected.empty?
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
              "worklist batch ranked by impact (severity, weighted findings, stable path); #{detail}",
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
            Array.new(WORKERS) { Thread.new { drain_repairs(queue, streamed:, pass:, run_deadline: budget) } }
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

            # Mechanical, as the scan was: a repaired file's text is new, so its model read is due
            # again and waits for the next pass's budget instead of one read per repaired file here.
            later = []
            fresh = semantic_deferred(later) do
              touched.flat_map { |relative| violations_for(File.expand_path(relative, @root)) }
            end

            note_pending(later.uniq)
            untouched = found.reject { |finding| touched.include?(finding[:file].to_s) }
            resolve_violations(untouched + fresh)
          end

          # The pass budget starts when the worker receives its first file, not when the scan starts:
          # a budget that began before a long scan expired before any file arrived.
          def drain_repairs(queue, streamed:, pass:, run_deadline:)
            rules = @law_order.ordered(violation_counts: @violation_counts)
            stream = Stream.new(streamed, pass, Hash.new(0))
            fixed = 0
            deadline = nil
            while (item = queue.pop) != :done
              deadline ||= [Time.now + PASS_BUDGET_SECONDS, run_deadline].min
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
              context_files: context[:files], context_root: context[:context_root],
              expected_target_sha256: context[:target_sha256]
            )
            repair.lock_interface! if context[:interface_locked]
            result = repair.run(path)
            # Only what the model was asked counts: a split filtered out before the
            # call is no decline, and counting it kept those rules from retiring.
            repair_memory.record(path, repair.asked_rules, result[:breakdown])
            tally_rule_results([[repair.scope, result]], breakdown: stream.breakdown, pass: stream.pass)
          end

          # The graph is built once per run, and the run itself changes files: RuboCop, earlier passes,
          # another writer. A file indexed under older bytes, or not at all, rebuilds the graph once
          # (under a lock, and only if the file changed after the last build) instead of parking the
          # file for a person.
          GRAPH_LOCK = Mutex.new
          GRAPH_REBUILT = "dependency graph rebuilt: files changed since it was indexed"
          NOT_INDEXED = "target source not indexed at its current content, even after a graph rebuild"

          def indexed_at?(graph, path, digest) = graph.includes_path?(path) && graph.source_digest(path) == digest

          def refresh_graph_for(graph, path)
            GRAPH_LOCK.synchronize do
              next unless File.mtime(path).to_f > (@graph_built_at || 0)

              graph.build(refresh: true)
              @graph_built_at = Time.now.to_f
              Master::Trace::Dmesg.status("understand0", GRAPH_REBUILT)
            end
          end

          # The dependency graph is built from complete current files before an
          # operator-requested run starts. Read all direct inbound/outbound file
          # relationships in full; never truncate a dependency to fit a prompt.
          # If a file is missing, unreadable, unindexed or the context is too
          # large, the caller is sent to HUMAN_DECISION rather than edited blind.
          def repair_context(path)
            graph = @reference_graph
            return { complete: true, files: [] } unless graph # isolated unit tests only; requested /fix always wires it
            target_source = File.read(path, encoding: "UTF-8")
            target_sha256 = Digest::SHA256.hexdigest(target_source)
            refresh_graph_for(graph, path) unless indexed_at?(graph, path, target_sha256)
            return incomplete_repair_context(NOT_INDEXED) unless indexed_at?(graph, path, target_sha256)

            relative = graph.relative(path)
            radius = graph.blast_radius(path)
            inbound = Array(radius[:inbound]) - [relative]
            lock_reasons = interface_lock_reasons(graph:, path:, relative:, inbound:)
            total_bytes = target_source.bytesize
            if total_bytes > REPAIR_CONTEXT_MAX_BYTES
              return incomplete_repair_context(
                "complete target source is #{total_bytes} bytes, exceeding #{REPAIR_CONTEXT_MAX_BYTES}; no excerpt-only repair was attempted",
              )
            end

            outbound = Array(radius[:outbound]) - [relative] - inbound
            room = REPAIR_CONTEXT_MAX_BYTES - total_bytes
            entries, omitted = related_sources(graph:, inbound:, outbound:, room:)
            lock_reasons << "#{omitted.size} related file(s) not shown, over the context budget" unless omitted.empty?

            {
              complete: true,
              files: entries,
              context_root: graph.root,
              target_sha256:,
              interface_locked: !lock_reasons.empty?,
              lock_reasons:,
            }
          rescue IncompleteContext => e
            incomplete_repair_context(e.message)
          rescue StandardError => e
            incomplete_repair_context("#{e.class}: #{e.message}")
          end

          IncompleteContext = Class.new(StandardError)

          # The callers first, then the dependencies, each smallest first so the most files fit. A file past
          # the budget is left out and said so; the repair is then held to the names it has. A related file
          # that is a symlink, gone or changed since the graph was read still refuses the repair.
          def related_sources(graph:, inbound:, outbound:, room:)
            ordered = [inbound, outbound].flat_map do |group|
              group.sort_by { |rel| File.size?(File.expand_path(rel, graph.root)).to_i }
            end

            entries = []
            omitted = []

            ordered.each do |rel|
              source = read_related(graph, rel)
              if source.bytesize > room
                omitted << rel
              else
                room -= source.bytesize
                entries << { path: rel, source:, sha256: Digest::SHA256.hexdigest(source) }
              end
            end

            [entries, omitted]
          end

          def read_related(graph, rel)
            full = File.expand_path(rel, graph.root)
            raise IncompleteContext, "dependency is a symlink: #{rel}" if File.symlink?(full)
            raise IncompleteContext, "dependency disappeared since graph refresh: #{rel}" unless File.file?(full)

            source = File.read(full, encoding: "UTF-8")
            return source if graph.source_digest(full) == Digest::SHA256.hexdigest(source)

            raise IncompleteContext, "dependency changed since graph refresh: #{rel}"
          end

          # Define-style calls make methods; they never call the target by a name this graph cannot see.
          DYNAMIC_DEFINERS = %w[define_method define_singleton_method].freeze

          # Callers the graph cannot see: a dynamic call in the target or in a file that calls it, a
          # name-based caller whose receiver is unknown, an import in the target that did not resolve.
          # None refuses the repair. Each means the repair may not change what the file defines, which
          # FileRepair holds it to: a change to the body cannot break a caller, a change to the name can.
          # What the target itself calls outward is not here: editing the target cannot change its callees.
          def interface_lock_reasons(graph:, path:, relative:, inbound:)
            dynamic_lock_reasons(graph:, files: [relative] + inbound) +
              unresolved_lock_reasons(graph:, path:, relative:, inbound:)
          end

          def dynamic_lock_reasons(graph:, files:)
            sites = files.flat_map { |rel| graph.dynamic_for(File.join(graph.root, rel)) }
            calls = sites.reject { |site| DYNAMIC_DEFINERS.include?(site[:name].to_s) }
            calls.map { |site| "dynamic #{site[:name]} at #{site[:file]}:#{site[:line]}" }
          end

          def unresolved_lock_reasons(graph:, path:, relative:, inbound:)
            callers = (inbound + [relative]).to_set
            rows = graph.unresolved_for(path).select do |row|
              callers.include?(row[:from_file]) && (row[:from_file] != relative || row[:kind] == :import)
            end
            rows.map { |row| "unresolved #{row[:kind]} #{row[:name]} at #{row[:from_file]}:#{row[:line]}" }
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
            return false if Time.now >= deadline || circuit_open? || reload_due? || RunBudget.stopping
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
