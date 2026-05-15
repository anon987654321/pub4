#!/usr/bin/env zsh
# nmap.sh — comprehensive network scan against a domain or IP.
# Usage: doas zsh nmap.sh <target>
# Requires: nmap, doas configured for nmap

set -euo pipefail
setopt nullglob

[[ "$EUID" -ne 0 ]] && { print "Run with doas: doas zsh $0 <target>" >&2; exit 1; }
[[ $# -ne 1 ]] && { print "Usage: doas zsh $0 <target>" >&2; exit 1; }

command -v nmap >/dev/null 2>&1 || { print "nmap not found; pkg_add nmap" >&2; exit 1; }

target=$1
stamp=$(date +"%Y-%m-%d_%H-%M-%S")
out="nmap_${target}_${stamp}"
log="${out}.log"
mkdir -p "$out"

# Resolve IPs (pure zsh)
typeset -a ips
local line fields
while IFS= read -r line; do
  [[ "$line" == \;* ]] && continue
  fields=("${(@s: :)line}")
  [[ "${fields[3]}" == "A" ]] && ips+=("${fields[5]}")
done < <(drill "$target" A 2>/dev/null)

[[ ${#ips} -eq 0 ]] && { print "No A records for $target" >&2; exit 1; }
print "Scanning $target (${ips[*]})" | tee "$log"

run() {
  local phase=$1; shift
  print "\n[$phase]" | tee -a "$log"
  nmap "$@" >> "$log" 2>&1
}

run "host-discovery"   -sn -PS22,80,443 -PU53,161 -PE -PP -oN "$out/hosts.txt"          "$target"
run "tcp-syn"          -sS -T4 -p- -oN "$out/tcp_syn.txt"                                ${ips[*]}
run "tcp-connect"      -sT -T4 -p- -oN "$out/tcp_connect.txt"                            ${ips[*]}
run "udp"              -sU -T4 --top-ports 200 -oN "$out/udp.txt"                        ${ips[*]}

# Grab open ports for targeted scans
typeset -a open_ports
local p
while IFS= read -r p; do
  [[ "$p" =~ ^[0-9] ]] && open_ports+=("${p%%/*}")
done < <(nmap -p- "$target" 2>/dev/null)
ports="${(j:,:)open_ports}"

[[ -n "$ports" ]] && {
  run "service-versions" -sV -p "$ports" -oN "$out/services.txt"                         ${ips[*]}
  run "os-detection"     -O  -p "$ports" -oN "$out/os.txt"                               ${ips[*]}
  run "vuln-scripts"     -A --script "default,safe,vuln" -oA "$out/vuln"                 ${ips[*]}

  nmap -p80,443 "$target" 2>/dev/null | grep -q "open" && \
    run "http" --script "http-enum,http-vuln*,http-headers,http-methods" \
               -p80,443 -oN "$out/http.txt"                                               ${ips[*]}
}

print "\nDone. Results: $out/ | log: $log"
