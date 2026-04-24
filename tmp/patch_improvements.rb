# encoding: utf-8
# frozen_string_literal: true

BASE = "/home/dev/pub4/MASTER"

# === 1. Memory: cosine similarity with proper IDF ===

memory_rb = File.read(File.join(BASE, "lib/master/memory.rb"), encoding: "utf-8")

old_tfidf = <<~'OLD'
    # Log-weighted term frequency similarity — no external gem required.
    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty?
      freq = doc_terms.tally
      query_terms.sum { |t| Math.log(1.0 + freq.fetch(t, 0).to_f) }
    end
OLD

new_cosine = <<~'NEW'
    # TF-IDF with proper IDF and cosine similarity.
    def tfidf_score(query_terms, doc_terms)
      return 0.0 if doc_terms.empty? || query_terms.empty?

      corpus = @store.map do |k, v|
        val = v.is_a?(Hash) ? v["value"].to_s : v.to_s
        tokenize("#{k} #{val}")
      end
      n_docs = [corpus.size, 1].max

      df = Hash.new(0)
      corpus.each { |doc| doc.uniq.each { |t| df[t] += 1 } }

      idf = ->(term) { Math.log(n_docs.to_f / (1.0 + df.fetch(term, 0))) }

      tfidf_vec = ->(terms) do
        freq = terms.tally
        vec = Hash.new(0.0)
        freq.each { |t, count| vec[t] = (1.0 + Math.log(count)) * idf.call(t) }
        vec
      end

      q_vec = tfidf_vec.call(query_terms)
      d_vec = tfidf_vec.call(doc_terms)

      all_terms = (q_vec.keys + d_vec.keys).uniq
      dot = all_terms.sum { |t| q_vec[t] * d_vec[t] }
      mag_q = Math.sqrt(q_vec.values.sum { |v| v * v })
      mag_d = Math.sqrt(d_vec.values.sum { |v| v * v })
      denom = mag_q * mag_d
      denom.zero? ? 0.0 : dot / denom
    end
NEW

if memory_rb.include?("Log-weighted term frequency")
  memory_rb.sub!(old_tfidf.strip, new_cosine.strip)
  File.write(File.join(BASE, "lib/master/memory.rb"), memory_rb)
  puts "memory.rb: upgraded to cosine similarity with proper IDF"
else
  puts "memory.rb: tfidf_score already changed"
end

# === 2. Undo: persistent journal + multi-level undo ===

undo_content = <<~'UNDO'
# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  class Undo
    MAX_JOURNAL = 50

    def initialize(session:, event_bus: nil, root: Dir.pwd)
      @session = session
      @bus     = event_bus
      @root    = root
      @journal = File.join(root, ".master", "undo_journal.jsonl")
      @stack   = load_journal
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
      @stack.shift while @stack.size > MAX_JOURNAL
      persist_journal
      Result.ok(path)
    rescue => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!(steps: 1)
      return Result.err("nothing to undo", category: :validation) if @stack.empty?

      steps = [steps, @stack.size].min
      paths = []

      steps.times do
        entry = @stack.pop
        restore(entry["path"], entry["content"])
        paths << entry["path"]
        @bus&.publish("undo:applied", path: paths.last)
      end

      persist_journal
      Result.ok(paths.size == 1 ? paths.first : paths)
    end

    def depth = @stack.size

    def history(limit: 10)
      @stack.last(limit).reverse.map.with_index(1) do |entry, i|
        time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
        "#{i}. #{entry["path"]} (#{time})"
      end
    end

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end

    def load_journal
      return [] unless File.exist?(@journal)
      File.readlines(@journal).filter_map do |line|
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end
    rescue StandardError
      []
    end

    def persist_journal
      FileUtils.mkdir_p(File.dirname(@journal))
      File.open(@journal, "w") do |f|
        @stack.each { |entry| f.puts(JSON.generate(entry)) }
      end
    end
  end
end
UNDO

File.write(File.join(BASE, "lib/master/undo.rb"), undo_content)
puts "undo.rb: persistent journal + multi-level undo + history"

# === 3. CodeIndex: incremental mtime-based reindex ===

ci_rb = File.read(File.join(BASE, "lib/master/code_index.rb"), encoding: "utf-8")

# Add @mtimes to initialize
ci_rb.sub!(
  "      @references = []\n      @built_at = nil",
  "      @references = []\n      @mtimes = {}\n      @built_at = nil"
)

# Replace the build method body
lines = ci_rb.lines
build_comment = lines.index { |l| l.include?("Build the entire index") }
build_def = lines.index { |l| l.include?("def build(path: nil)") }

if build_def
  # Find the end of the method (the rescue...end block)
  depth = 0
  build_end = nil
  (build_def..lines.size - 1).each do |i|
    depth += 1 if lines[i] =~ /^\s+def\s/
    if depth > 0 && lines[i].strip == "end"
      depth -= 1
      if depth == 0
        build_end = i
        break
      end
    end
  end

  # Also consume the rescue block after the end
  if build_end && lines[build_end + 1]&.include?("rescue")
    # Find the real end
    (build_end + 1..lines.size - 1).each do |i|
      if lines[i].strip == "end"
        build_end = i
        break
      end
    end
  end

  start_i = build_comment || build_def

  new_build = <<~'BUILD'
    # Build the entire index. Optional +path+ restricts to a subtree.
    # First call: full build. Subsequent calls: incremental (mtime-based).
    def build(path: nil)
      target = path ? File.expand_path(path, @root) : @root
      files = Dir.glob(File.join(target, "**", "*.rb"))
                  .reject { |f| f.include?("/vendor/") }

      if @built_at.nil?
        @symbols.clear
        @references.clear
        @mtimes.clear
        files.each do |f|
          index_file(f)
          @mtimes[f] = File.mtime(f) rescue nil
        end
      else
        changed = 0

        (@mtimes.keys - files).each do |gone|
          @symbols.delete_if { |_, s| s.file == gone }
          @references.reject! { |r| r.from_file == gone }
          @mtimes.delete(gone)
        end

        files.each do |f|
          mt = File.mtime(f) rescue nil
          next if @mtimes[f] == mt
          reindex(f)
          @mtimes[f] = mt
          changed += 1
        end

        @bus&.publish("code_index:incremental", changed: changed, total: files.size) if changed > 0
      end

      @built_at = Time.now
      @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
      self
    rescue StandardError => e
      @bus&.publish("code_index:error", error: e.message)
      self
    end
  BUILD

  if build_end
    new_lines = lines[0...start_i] + new_build.lines + lines[(build_end + 1)..]
    File.write(File.join(BASE, "lib/master/code_index.rb"), new_lines.join)
    puts "code_index.rb: incremental mtime-based reindex"
  else
    puts "code_index.rb: could not find end of build method"
  end
else
  puts "code_index.rb: build method not found"
end

# === 4. Wire root: into Undo.new in master.rb ===
master_rb = File.read(File.join(BASE, "lib/master.rb"), encoding: "utf-8")
if master_rb =~ /Undo\.new\(session:\s*session,\s*event_bus:\s*bus\)/
  master_rb.sub!(
    /Undo\.new\(session:\s*session,\s*event_bus:\s*bus\)/,
    "Undo.new(session: session, event_bus: bus, root: root)"
  )
  File.write(File.join(BASE, "lib/master.rb"), master_rb)
  puts "master.rb: Undo.new now passes root:"
elsif master_rb =~ /Undo\.new\(session:\s*session\)/
  master_rb.sub!(
    /Undo\.new\(session:\s*session\)/,
    "Undo.new(session: session, root: root)"
  )
  File.write(File.join(BASE, "lib/master.rb"), master_rb)
  puts "master.rb: Undo.new now passes root:"
else
  puts "master.rb: Undo init - checking pattern..."
  # Show what's there
  master_rb.lines.each_with_index do |l, i|
    puts "  #{i + 1}: #{l}" if l.include?("Undo.new")
  end
end

puts "\nall improvements applied."
