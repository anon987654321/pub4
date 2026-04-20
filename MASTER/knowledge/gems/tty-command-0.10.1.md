require "tty-command"
cmd = TTY::Command.new
cmd.run("ls -la")
out, err = cmd.run("echo Hello!")
