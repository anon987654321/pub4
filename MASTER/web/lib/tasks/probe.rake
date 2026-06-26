desc "Run headless Ferrum probe against the deployed MASTER instance"
task :probe do
  exec "bundle exec ruby #{Rails.root}/script/probe_face"
end

desc "Run Ferrum E2E probe: primer → ping chat → felt/face state"
task "probe:chat_e2e" do
  exec "bundle exec ruby #{Rails.root}/script/probe_chat_e2e.rb", ENV.fetch("WEB_URL", "http://127.0.0.1:53187/")
end
