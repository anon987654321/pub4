# Sourced by the face bundle build scripts — not executable on its own.
#
# Every one of them ends by printing what it just wrote, raw and gzipped. The
# label is the artifact's own basename, so a script that renames its output
# cannot report the old name. A bundle with a budget in
# config/bundle_budgets.yml that gzips past it stops the build: a printed size
# nobody reads let three.face.module.js reach 514 KB raw.
report_bundle_size() {
  ruby -ryaml -rzlib -e '
    path, budgets = ARGV
    name = File.basename(path)
    gzip = Zlib.gzip(File.binread(path)).bytesize
    budget = File.file?(budgets) ? YAML.safe_load_file(budgets)[name] : nil
    puts "#{name} raw=#{File.size(path)} gzip=#{gzip}#{" budget=#{budget}" if budget}"
    over = budget && gzip > budget
    abort "#{name}: gzip #{gzip} bytes is over its #{budget}-byte budget in config/bundle_budgets.yml" if over
  ' "$1" "$ROOT/config/bundle_budgets.yml"
}
