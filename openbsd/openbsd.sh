#!/usr/bin/env zsh
# OpenBSD Rails Stack - Clean Style
# Version: 49.0.0
# Date: 2025-12-30

set -e

VERSION="49.0.0"
MAIN_IP="185.52.176.18"
PRIMARY_DOMAIN="brgen.no"

# Apps: name port domains
declare -A apps
apps[brgen]="11006 brgen.no www.brgen.no"
apps[amber]="10001 amber.no www.amber.no"
apps[blognet]="10002 blognet.no www.blognet.no"

print "OpenBSD Rails Stack v$VERSION"
print "=============================="

# Install packages
print "\nInstalling packages..."
pkg_add ruby-3.3 postgresql-server redis nsd relayd acme-client

# Ruby/Rails setup
print "\nSetting up Ruby..."
gem install bundler rails --no-document

# PostgreSQL
print "\nConfiguring PostgreSQL..."
rcctl enable postgresql
rcctl start postgresql

# Redis
print "\nConfiguring Redis..."
rcctl enable redis
rcctl start redis

# Deploy each app
for app_name port_domains in ${(kv)apps}; do
  port=${port_domains% *}
  domains=${port_domains#* }
  
  print "\nDeploying $app_name on port $port..."
  
  # Create user
  useradd -m -G www -s /bin/ksh $app_name || true
  
  # Create directories
  doas -u $app_name mkdir -p /home/$app_name/app/{app,config,db,log,public,tmp}
  
  # Write Gemfile
  cat > /home/$app_name/app/Gemfile << GEMFILE
source "https://rubygems.org"
gem "rails", "~> 8.0"
gem "pg"
gem "falcon"
gem "propshaft"
gem "turbo-rails"
gem "stimulus-rails"
GEMFILE
  
  # Install gems
  cd /home/$app_name/app
  doas -u $app_name bundle install
  
  # Database config
  db_password=$(openssl rand -hex 16)
  cat > /home/$app_name/app/config/database.yml << DB
production:
  adapter: postgresql
  database: ${app_name}_production
  username: $app_name
  password: $db_password
  host: localhost
DB
  
  # Create database
  doas -u _postgresql createuser $app_name || true
  doas -u _postgresql createdb -O $app_name ${app_name}_production || true
  
  # RC script
  cat > /etc/rc.d/$app_name << RC
#!/bin/ksh
daemon_user="$app_name"
daemon="/usr/local/bin/bundle"
daemon_flags="exec falcon serve -b 0.0.0.0 -p $port"
. /etc/rc.d/rc.subr
rc_bg=YES
rc_cmd \$1
RC
  chmod +x /etc/rc.d/$app_name
  
  # Start service
  rcctl enable $app_name
  rcctl start $app_name
  
  print "$app_name deployed"
done

# Firewall
print "\nConfiguring firewall..."
cat > /etc/pf.conf << PF
ext_if="vio0"
set skip on lo
block all
pass in on \$ext_if proto tcp to port {22 53 80 443}
pass out
PF
pfctl -f /etc/pf.conf

# DNS
print "\nConfiguring DNS..."
cat > /var/nsd/zones/brgen.no.zone << DNS
\$ORIGIN brgen.no.
\$TTL 3600
@ IN SOA ns.brgen.no. admin.brgen.no. (
  2025123001
  3600
  900
  604800
  86400
)
@ IN NS ns.brgen.no.
@ IN A $MAIN_IP
www IN A $MAIN_IP
ns IN A $MAIN_IP
DNS

rcctl enable nsd
rcctl start nsd

print "\nDeployment complete!"
print "Apps running: ${#apps} services"
print "Next: Point domains to $MAIN_IP"
