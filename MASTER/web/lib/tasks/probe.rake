desc "Run headless Ferrum probe against the deployed MASTER instance"
task :probe do
  exec "bundle exec ruby #{Rails.root}/script/probe_face"
end
