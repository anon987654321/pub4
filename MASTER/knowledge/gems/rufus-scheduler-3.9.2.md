require 'rufus-scheduler'

scheduler = Rufus::Scheduler.new

scheduler.in '3s' { puts 'Hello... Rufus' }

scheduler.join   # blocks until the scheduler shuts down (remove in web apps)
