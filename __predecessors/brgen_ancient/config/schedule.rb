
# Whenever configuration file

# https://github.com/javan/whenever

# -------------------------------------------------

# Run `whenever -i` after updating this file

# Emulate cron(8)'s environment with `env -i /usr/local/bin/zsh --no-rcs`

# -------------------------------------------------

# Set shell to zsh

set :job_template, "/usr/local/bin/zsh -l -c ':job'"

# -------------------------------------------------

job_type :ruby, "cd :path && /usr/local/bin/ruby :task"

# Export Bundler's path due to cron(8)'s limited environment

job_type :rake, "export PATH=/usr/local/bin && cd :path && :environment_variable=:environment bundle exec rake :task --silent :output"

# -------------------------------------------------

every :day do
  # rake "ephemerality:expire"
  # rake "ephemerality:archive"
  # rake "ephemerality:delete"

  # -------------------------------------------------

  # Submit new sitemap to Google

  rake "-s sitemap:refresh"
end

# -------------------------------------------------

# Refresh Tor IP list

# http://dan.me.uk/ only lets us download his list once a day

# every :day, at: "1:30 am" do
#   rake "get_tor_ips"
# end

