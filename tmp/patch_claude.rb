path = "/home/dev/pub4/CLAUDE.md"
c = File.read(path, encoding: "utf-8")
c = c.sub("Write script to /tmp: `doas tee /tmp/patch.rb <<'EOF' ... EOF`\nRun it: `ruby /tmp/patch.rb`\nNever use `ruby -i` with heredoc — will empty file on script error.", "Write script to pub4/tmp: `doas tee /home/dev/pub4/tmp/patch.rb <<'EOF' ... EOF`\nRun it: `ruby /home/dev/pub4/tmp/patch.rb`\nNever use `ruby -i` with heredoc — will empty file on script error.\n`~` in the Claude CLI session = Android proot, not VPS. Always use absolute VPS paths: `/home/dev/pub4/...`")
File.write(path, c)
puts "done"
