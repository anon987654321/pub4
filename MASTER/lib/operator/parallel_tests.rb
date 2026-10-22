# frozen_string_literal: true

require "fileutils"

module Operator
  # The MASTER suite across several processes. One process ran its 3,600 tests in turn for about
  # twenty minutes on a machine with cores to spare; the files are dealt out to MASTER_TEST_JOBS
  # workers (3 by default, which fits an 8 GB machine beside its other work), largest first onto
  # the lightest worker.
  module ParallelTests
    # Each worker runs verbose, and its per-test result lines pass through as they land, so a
    # watcher still sees each failure as it happens. When all have finished, each worker's report
    # (its failure blocks and summary) is printed whole, so the names stay under their headers.

    LOG_DIR = File.expand_path("../../.master/check", __dir__)
    RESULT_LINE = /\A\S+#\S+ = [\d.]+ s = [.FES]\s*\z/
    REPORT_START = /\AFinished in /

    module_function

    def jobs = [Integer(ENV.fetch("MASTER_TEST_JOBS", "3"), exception: false) || 3, 1].max

    def deal(files, count)
      buckets = Array.new(count) { [] }
      loads = Array.new(count, 0)

      # Weighed by bytes, plus one so equal or unreadable files still spread.
      weight = ->(path) { File.size?(path).to_i + 1 }
      files.sort_by { |path| -weight.call(path) }.each do |path|
        lightest = loads.index(loads.min)
        buckets[lightest] << path
        loads[lightest] += weight.call(path)
      end
      buckets.reject(&:empty?)
    end

    # command builds a worker's argv from its files; true when every worker passed.
    def run(files, command:, out: $stdout)
      FileUtils.mkdir_p(LOG_DIR)
      workers = deal(files, jobs).each_with_index.map do |bucket, index|
        start(bucket, log: File.join(LOG_DIR, "test-worker-#{index + 1}.log"), command:)
      end

      stop = false
      relay = Thread.new { relay_results(workers, out) { stop } }
      statuses = workers.map { |worker| Process.wait2(worker.fetch(:pid)).last }
      stop = true
      relay.join
      report(workers, out)
      statuses.all?(&:success?)
    end

    def start(bucket, log:, command:)
      pid = Process.spawn(*command.call(bucket), out: log, err: %i[child out], in: File::NULL)
      { pid:, log:, offset: 0 }
    end

    # Each result line once, as soon as its worker writes it.
    # Until the block says stop, then once more for what the workers wrote last.
    def relay_results(workers, out)
      until yield
        relay_once(workers, out)
        sleep 1
      end
      relay_once(workers, out)
    end

    def relay_once(workers, out)
      workers.each { |worker| fresh_lines(worker).grep(RESULT_LINE).each { |line| out.puts line } }
      out.flush
    end

    def fresh_lines(worker)
      text = File.open(worker.fetch(:log), "rb") { |file| file.seek(worker.fetch(:offset)) && file.read.to_s }
      complete = String.new(text[/\A.*\n/m].to_s)
      worker[:offset] += complete.bytesize
      complete.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
    end

    def report(workers, out)
      workers.each_with_index do |worker, index|
        lines = File.read(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace).lines
        start = lines.index { |line| line.match?(REPORT_START) } || [lines.size - 40, 0].max
        out.puts "", "worker #{index + 1} of #{workers.size}:", *lines.drop(start).map(&:chomp)
      end
    end
  end
end
