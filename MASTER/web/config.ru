# This file is used by Rack-based servers to start the application.

# Serialize concurrent parse_file evals from Falcon --threaded workers
($rails_init_mutex ||= Thread::Mutex.new).synchronize { require_relative "config/environment" }

run Rails.application
Rails.application.load_server
