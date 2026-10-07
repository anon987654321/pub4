# Sourced by the face bundle build scripts — not executable on its own.
#
# Every one of them ends by printing what it just wrote, raw and gzipped, and
# that line is the only signal a build gives about a bundle growing. The label
# is the artifact's own basename, so a script that renames its output cannot
# report the old name.
report_bundle_size() {
  _bundle_path=$1
  _bundle_raw=$(ruby -e 'puts File.size(ARGV.fetch(0))' "$_bundle_path")
  _bundle_gz=$(ruby -rzlib -e 'puts Zlib.gzip(File.binread(ARGV.fetch(0))).bytesize' "$_bundle_path")
  echo "$(basename "$_bundle_path") raw=${_bundle_raw} gzip=${_bundle_gz}"
}
