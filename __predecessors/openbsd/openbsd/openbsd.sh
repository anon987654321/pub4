#!/usr/bin/env zsh

main_ip="46.23.95.45"

# Define function to generate a random port
generate_random_port() {
  echo $((RANDOM % 64511 + 1024))
}

# Function to get the latest package version
get_latest_pkg_version() {
  pkg_name=$1
  latest_pkg=$(pkg_info | grep "^$pkg_name-" | sort -V | tail -1)
  echo $latest_pkg
}

# Define all domains and their subdomains/apps
typeset -A all_domains
all_domains=(
  ["brgen.no"]="markedsplass playlist dating tv takeaway maps"
  ["oshlo.no"]="markedsplass playlist dating tv takeaway maps"
  ["trndheim.no"]="markedsplass playlist dating tv takeaway maps"
  ["stvanger.no"]="markedsplass playlist dating tv takeaway maps"
  ["trmso.no"]="markedsplass playlist dating tv takeaway maps"
  ["longyearbyn.no"]="markedsplass playlist dating tv takeaway maps"
  ["reykjavk.is"]="markadur playlist dating tv takeaway maps"
  ["kobenhvn.dk"]="markedsplads playlist dating tv takeaway maps"
  ["stholm.se"]="marknadsplats playlist dating tv takeaway maps"
  ["gteborg.se"]="marknadsplats playlist dating tv takeaway maps"
  ["mlmoe.se"]="marknadsplats playlist dating tv takeaway maps"
  ["hlsinki.fi"]="markkinapaikka playlist dating tv takeaway maps"
  ["lndon.uk"]="marketplace playlist dating tv takeaway maps"
  ["mnchester.uk"]="marketplace playlist dating tv takeaway maps"
  ["brmingham.uk"]="marketplace playlist dating tv takeaway maps"
  ["edinbrgh.uk"]="marketplace playlist dating tv takeaway maps"
  ["glasgw.uk"]="marketplace playlist dating tv takeaway maps"
  ["lverpool.uk"]="marketplace playlist dating tv takeaway maps"
  ["amstrdam.nl"]="marktplaats playlist dating tv takeaway maps"
  ["rottrdam.nl"]="marktplaats playlist dating tv takeaway maps"
  ["utrcht.nl"]="marktplaats playlist dating tv takeaway maps"
  ["brssels.be"]="marche playlist dating tv takeaway maps"
  ["zrich.ch"]="marktplatz playlist dating tv takeaway maps"
  ["lchtenstein.li"]="marktplatz playlist dating tv takeaway maps"
  ["frankfrt.de"]="marktplatz playlist dating tv takeaway maps"
  ["mrseille.fr"]="marche playlist dating tv takeaway maps"
  ["mlan.it"]="mercato playlist dating tv takeaway maps"
  ["lsbon.pt"]="mercado playlist dating tv takeaway maps"
  ["lsangeles.com"]="marketplace playlist dating tv takeaway maps"
  ["newyrk.us"]="marketplace playlist dating tv takeaway maps"
  ["chcago.us"]="marketplace playlist dating tv takeaway maps"
  ["dtroit.us"]="marketplace playlist dating tv takeaway maps"
  ["houstn.us"]="marketplace playlist dating tv takeaway maps"
  ["dllas.us"]="marketplace playlist dating tv takeaway maps"
  ["austn.us"]="marketplace playlist dating tv takeaway maps"
  ["prtland.com"]="marketplace playlist dating tv takeaway maps"
  ["mnneapolis.com"]="marketplace playlist dating tv takeaway maps"
  ["pub.healthcare"]=""
  ["pub.attorney"]=""
  ["freehelp.legal"]=""
  ["bsdports.org"]=""
  ["discordb.org"]=""
  ["foodielicio.us"]=""
  ["neuroticerotic.com"]=""
)

# Define apps and their domains/ports
typeset -A apps_domains
apps_domains=(
  ["brgen"]="brgen.no $(generate_random_port)"
  ["bsdports"]="bsdports.org $(generate_random_port)"
  ["neuroticerotic"]="neuroticerotic.com $(generate_random_port)"
)

# -- INSTALLATION BEGIN --

echo "Installing necessary packages..."
latest_ruby=$(get_latest_pkg_version "ruby")
latest_postgresql_server=$(get_latest_pkg_version "postgresql-server")
latest_dnscrypt_proxy=$(get_latest_pkg_version "dnscrypt-proxy")

if [ -z "$latest_ruby" ] || [ -z "$latest_postgresql_server" ] || [ -z "$latest_dnscrypt_proxy" ]; then
  echo "Failed to find package versions. Please check the package names." >&2
  exit 1
fi

doas pkg_add -U $latest_ruby $latest_postgresql_server $latest_dnscrypt_proxy > /dev/null 2>&1
echo "Packages installed."

# -- PF --

echo "Configuring pf..."
doas tee /etc/pf.conf > /dev/null << "EOF"
ext_if = "vio0"

# Allow all loopback traffic
set skip on lo

# Block stateless traffic and return RSTs
block return

# Default pass rule to keep state
pass

# Block all incoming traffic by default and log
block in log

# Allow all outgoing traffic by default
pass out quick

# Block brute-force attackers
# Manage with: pfctl -t bruteforce -T [show|flush|delete <IP>]
table <bruteforce> persist
block quick from <bruteforce>

# Allow incoming SSH with rate limits and protection
pass in on $ext_if inet proto tcp from any to $ext_if port 22 keep state (max-src-conn 15, max-src-conn-rate 5/3, overload <bruteforce> flush global)

# Allow DNS requests and zone transfers
pass in on $ext_if inet proto { tcp, udp } from any to $ext_if port 53 keep state

# Allow HTTP and HTTPS traffic
pass in on $ext_if inet proto tcp from any to $ext_if port { 80, 443 } keep state

# Include relayd rules if installed
anchor "relayd/*"
EOF

doas pfctl -f /etc/pf.conf
doas pfctl -e
echo "pf configured and enabled."

# -- RELAYD --

echo "Configuring relayd..."
doas tee /etc/relayd.conf > /dev/null << EOF
log connection

# Specify egress interface
interface $main_ip
EOF

for app in "${(@k)apps_domains}"; do
  domain=${apps_domains[$app]% *}
  port=${apps_domains[$app]#* }

  doas tee -a /etc/relayd.conf > /dev/null << EOF

table <${app}> { 127.0.0.1 }

protocol "http_protocol_${app}" {
  match request header set "X-Forwarded-By" value "\$SERVER_ADDR:\$SERVER_PORT"
  match request header set "X-Forwarded-For" value "\$REMOTE_ADDR"
  match response header set "Content-Security-Policy" value "upgrade-insecure-requests; default-src https:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; script-src 'self' 'unsafe-inline' 'unsafe-eval'"
  match response header set "Strict-Transport-Security" value "max-age=31536000; includeSubDomains; preload"
  match response header set "Referrer-Policy" value "strict-origin"
  match response header set "Feature-Policy" value "accelerometer 'none'; ..."
  match response header set "X-Content-Type-Options" value "nosniff"
  match response header set "X-Download-Options" value "noopen"
  match response header set "X-Frame-Options" value "DENY"
  match response header set "X-XSS-Protection" value "1; mode=block"

  tcp { no delay }

  request timeout 20
  session timeout 60

  forward to <${app}> port $port
}

relay "http_${app}" {
  listen on 0.0.0.0 port 80
  protocol "http_protocol_${app}"
}

relay "https_${app}" {
  listen on 0.0.0.0 port 443 tls
  protocol "http_protocol_${app}"
}
EOF
done

doas rcctl enable relayd
doas rcctl start relayd
echo "relayd configured and started."

# -- HTTPD --

echo "Configuring httpd..."
doas tee /etc/httpd.conf > /dev/null << EOF
server "default" {
  listen on * port 80
  location "/.well-known/acme-challenge/*" {
    root "/acme"
    request strip 2
  }
}
EOF

doas mkdir -p /var/www/acme

doas tee /etc/acme-client.conf > /dev/null << EOF
authority letsencrypt {
  api url "https://acme-v02.api.letsencrypt.org/directory"
  account key "/etc/acme/letsencrypt-privkey.pem"
}

authority letsencrypt-staging {
  api url "https://acme-staging-v02.api.letsencrypt.org/directory"
  account key "/etc/acme/letsencrypt-staging-privkey.pem"
}
EOF

for domain in "${(@k)all_domains}"; do
  doas tee -a /etc/acme-client.conf > /dev/null << EOF
domain "$domain" {
  alternative name { $(echo ${all_domains[$domain]} | tr ' ' '", "') }
  domain key "/etc/ssl/private/$domain.key"
  domain fullchain "/etc/ssl/acme/$domain.fullchain"
  domain chain "/etc/ssl/acme/$domain.chain"
  domain cert "/etc/ssl/acme/$domain.crt"

  sign with letsencrypt
}
EOF
done

doas rcctl enable httpd
doas rcctl start httpd
echo "httpd configured and started."

# -- NSD --

echo "Configuring nsd..."
doas mkdir -p /var/nsd/zones/master /var/nsd/etc

for domain in "${(@k)all_domains}"; do
  serial=$(date +"%Y%m%d%H")

  doas tee "/var/nsd/zones/master/$domain.zone" > /dev/null << EOF
\$ORIGIN $domain.
\$TTL 24h

@ IN SOA ns.brgen.no. admin.brgen.no. ($serial 1h 15m 1w 3m)
@ IN NS ns.brgen.no.
@ IN NS ns.hyp.net.

www IN CNAME @

@ IN A $main_ip
EOF

  if [[ -n "${all_domains[$domain]}" ]]; then
    for subdomain in ${(s/ /)all_domains[$domain]}; do
      echo "$subdomain IN CNAME @" | doas tee -a "/var/nsd/zones/master/$domain.zone" > /dev/null
    done
  fi
done

doas tee /var/nsd/etc/nsd.conf > /dev/null << EOF
server:
  ip-address: "$main_ip"
  hide-version: yes
  verbosity: 2

remote-control:
  control-enable: yes
  control-interface: 127.0.0.1
  control-port: 8952
  server-key-file: "/var/nsd/etc/nsd_server.key"
  server-cert-file: "/var/nsd/etc/nsd_server.pem"
  control-key-file: "/var/nsd/etc/nsd_control.key"
  control-cert-file: "/var/nsd/etc/nsd_control.pem"

pattern:
  name: "default"
  zonefile: "master/%s.zone"
  notify: yes
  allow-notify: 194.63.248.53 NOKEY
  provide-xfr: 194.63.248.53 NOKEY
EOF

for domain in "${(@k)all_domains}"; do
  doas tee -a /var/nsd/etc/nsd.conf > /dev/null << EOF
zone:
  name: "$domain"
  include-pattern: "default"
EOF
done

doas nsd-checkconf /etc/nsd/nsd.conf
if [ $? -ne 0 ]; then
  echo "NSD configuration error. Exiting." >&2
  exit 1
fi

doas rcctl enable nsd
doas rcctl start nsd
echo "nsd configured and started."

# -- APP USER ACCOUNTS --

echo "Setting up app user accounts..."
for app in "${(@k)apps_domains}"; do
  doas useradd -m -G www -s /sbin/nologin $app > /dev/null 2>&1
  doas mkdir -p /home/$app/{public,config,log} > /dev/null 2>&1
  doas chown -R $app:www /home/$app > /dev/null 2>&1
done
echo "App user accounts setup complete."

# -- STARTUP SCRIPTS --

echo "Creating startup scripts for apps..."
for app in "${(@k)apps_domains}"; do
  port=${apps_domains[$app]#* }

  doas tee /etc/rc.d/$app > /dev/null << EOF
#!/bin/ksh

# Set environment variables
export BUNDLE_GEMFILE="/home/$app/$app/Gemfile"
export BUNDLE_PATH="/home/$app/$app/vendor/bundle"

# Run the daemon
daemon="/bin/ksh -c 'cd /home/$app/$app && export RAILS_ENV=production && /usr/local/bin/bundle32 exec /home/$app/$app/vendor/bundle/ruby/3.2/bin/falcon-host /home/$app/$app/config/falcon.rb >> /var/log/$app.log 2>&1'"

# Specify daemon user
daemon_user="$app"

# Include rc.subr for standard rc.d functionality
. /etc/rc.d/rc.subr

# Execute the command
rc_cmd \$1
EOF

  doas chmod +x /etc/rc.d/$app > /dev/null 2>&1
  doas rcctl enable $app > /dev/null 2>&1
  doas rcctl start $app > /dev/null 2>&1
done
echo "Startup scripts for apps created."

echo "Setup complete."

