require "tty-command"

# TTY::Command – a thin wrapper around system commands that captures
# stdout, stderr and the exit status in a consistent Result object.
# It provides a clean, test‑friendly API and works on all platforms
# supported by Ruby (including OpenBSD).

# ----------------------------------------------------------------------
# Create a reusable command runner.
# ----------------------------------------------------------------------
# You may pass options to customise behaviour:
#   :dry_run      – log the command but don’t execute it
#   :verbose      – echo the command before running
#   :color        – colourise output (true by default)
#   :raise_on_error – raise a TTY::Command::ExitError on non‑zero status
#
# Example:
#   cmd = TTY::Command.new(dry_run: false, verbose: true)

cmd = TTY::Command.new

# ----------------------------------------------------------------------
# Run a command; returns a TTY::Command::Result.
# ----------------------------------------------------------------------
# Result#out          – captured STDOUT (String)
# Result#err          – captured STDERR (String)
# Result#exit_status  – integer exit code
# Result#success?     – true if exit_status == 0
#
# The Result object implements #to_s returning the stdout, making it
# easy to interpolate in logs.

result = cmd.run("ls -la")
puts result.out   #=> directory listing
puts result.err   #=> any error output (empty on success)

# ----------------------------------------------------------------------
# Grab the tuple directly.
# ----------------------------------------------------------------------
# When you only need stdout/err you can destructure the Result.
out, err = cmd.run("echo Hello!")
puts out          #=> "Hello!\n"
puts err          #=> ""

# ----------------------------------------------------------------------
# Handling failures.
# ----------------------------------------------------------------------
# You can either inspect #exit_status or enable :raise_on_error.
# The raised exception carries the same Result for deeper inspection.
#
#   cmd = TTY::Command.new(raise_on_error: true)
#   begin
#     cmd.run("false")
#   rescue TTY::Command::ExitError => e
#     puts e.result.exit_status   #=> 1
#     puts e.result.err           #=> error message
#   end

# ----------------------------------------------------------------------
# Running commands with environment variables or in a specific directory.
# ----------------------------------------------------------------------
# Pass a hash as the second argument to set env vars, or use :chdir.
#
#   cmd.run("printenv FOO", env: { "FOO" => "bar" })
#   cmd.run("pwd", chdir: "/tmp")

# ----------------------------------------------------------------------
# Asynchronous execution.
# ----------------------------------------------------------------------
# #run returns a Result immediately, but you can also use #run_async
# which yields a thread that streams output in real time.
#
#   thread = cmd.run_async("sleep 2 && echo done")
#   thread.join
#   puts thread.value.out   #=> "done\n"

# ----------------------------------------------------------------------
# Integration with testing.
# ----------------------------------------------------------------------
# Stub external commands in your test suite by injecting a fake
# command runner that returns a pre‑crafted Result.
#
#   fake = TTY::Command.new
#   def fake.run(*); TTY::Command::Result.new(out: "stub", err: "", exit_status: 0); end
#   # use `fake` instead of the real runner in your unit tests.

# ----------------------------------------------------------------------
# Further reading
# ----------------------------------------------------------------------
# * https://github.com/piotrmurach/tty-command – full documentation
# * TTY::Command::Result – inspect all result fields
# * TTY::Command::ExitError – exception raised on failure when
#   :raise_on_error is enabled.