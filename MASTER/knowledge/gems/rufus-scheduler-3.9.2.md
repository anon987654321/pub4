require 'rufus-scheduler'

# Initialise a scheduler instance.
scheduler = Rufus::Scheduler.new

# One‑off job: runs 3 seconds from now.
scheduler.in '3s' do
  puts 'Hello… Rufus'
end

# Keep the process alive while jobs are pending.
# In a web server you wouldn't call `join`; the server's event loop
# drives the scheduler.
scheduler.join
