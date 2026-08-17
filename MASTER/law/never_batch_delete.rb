# frozen_string_literal: true

# New. Restores the guard added after the 2026-01-05 incident (16 untracked
# files batch-deleted before a conversion step) that did not survive the
# master.yml -> MASTER migration. Consequence class: unrecoverable data loss.
Law.define(:NEVER_BATCH_DELETE) do
  source "master.yml v66 file_deletion_protocol — never batch-delete files"
  severity :error
  languages %i[ruby shell]
  detect do |line|
    line.match?(/\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)*[^\s;|&]*[*?{]/) ||
      line.match?(/FileUtils\.rm(_r|_rf|_f)?\(?\s*Dir\[/) ||
      line.match?(/\.each\s*\{[^}]*(?:File\.delete|FileUtils\.rm)/)
  end
  fix "Delete one named path per call and confirm first; globs and .each { rm } need an explicit operator ack."
  bad  <<~RUBY
    FileUtils.rm_rf(Dir["tmp/*.txt"])
    system("rm -f build/*.o")
    stale.each { |f| File.delete(f) }
  RUBY
  good <<~RUBY
    FileUtils.rm("tmp/session.txt")
    system("rm", "-f", "build/main.o")
    File.delete(path) if confirmed?(path)
  RUBY
end
