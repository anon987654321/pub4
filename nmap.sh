#!/usr/bin/env zsh
set -euo pipefail

# Dette skriptet kjører en omfattende nettverksskanning fra en OpenBSD-server.
# Bruk: "doas zsh deep_nmap_scan.sh <domenenavn>" (f.eks. "doas zsh deep_nmap_scan.sh barnevernet.no")

# Krav: "doas" må være konfigurert i /etc/doas.conf (f.eks. "permit nopass bruker as root cmd nmap")
# Formål: Finne alle detaljer om et domene – porter, tjenester, svakheter – for lovlig bruk som politiarbeid.

# Sjekker om skriptet kjøres med doas – vi trenger full tilgang!
[[ "$EUID" -ne 0 ]] && {
    print -P "%BFeil:%b Bruk doas! Slik: doas zsh $0 <domenenavn>" >&2
    exit 1

}
# Sjekker om du har gitt et domene å skanne.
[[ $# -ne 1 ]] && {
    print -P "%BFeil:%b Jeg trenger et domenenavn! Slik: doas zsh $0 <domenenavn>" >&2
    exit 1

}
# Setter opp grunnleggende variabler.
target=$1  # Domenet vi skal undersøke
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")  # Tidsstempel for unike filer
loggfil="deep_scan_${target}_${timestamp}.log"  # Hovedloggfil for alt vi finner

utdatamappe="nmap_output_${target}_${timestamp}"  # Mappe for detaljerte filer
mkdir -p $utdatamappe  # Lager mappen om den ikke finnes
# Finner IP-adressene til domenet (pure zsh).
typeset -a ips drill_output
drill_output=("${(@f)$(drill $target A 2>/dev/null)}")
for line in "${drill_output[@]}"; do

  # Skip comments and non-A records using pure zsh pattern matching
  [[ "$line" == \;* ]] && continue
  local -a fields=("${(@s: :)line}")
  [[ "${fields[3]}" == "A" ]] && ips+=("${fields[5]}")
done
[[ ${#ips} -eq 0 ]] && {
    print -P "%BFeil:%b Ingen IP-adresser funnet for $target!" >&2
    exit 1
}

# Starter skanningen og logger det.
print -P "%BSkanner $target (${ips[*]}) klokken $(date)%b" | tee $loggfil
# 1. Vertsoppdagelse – finner alle maskiner knyttet til domenet.
print "1. Vertsoppdagelse" >> $loggfil

nmap -sn -PS22,80,443 -PU53,161 -PE -PP -oN $utdatamappe/vertsoppdagelse.txt $target >> $loggfil 2>&1
# Tips: Kombinerer flere metoder for å finne maskiner selv bak brannmurer

# 2. TCP SYN-skanning – rask og stille portskanning.
print "2. TCP SYN-skanning" >> $loggfil
nmap -sS -T4 -p- -oN $utdatamappe/tcp_syn.txt $ips >> $loggfil 2>&1
# Triks: Stille skanning unngår ofte brannmuroppdagelse

# 3. TCP CONNECT-skanning – mer nøyaktig, men mindre stille.
print "3. TCP CONNECT-skanning" >> $loggfil
nmap -sT -T4 -p- -oN $utdatamappe/tcp_connect.txt $ips >> $loggfil 2>&1
# Hemmelighet: Bruk denne for å bekrefte porter SYN kan overse

# 4. UDP-skanning – finner UDP-porter.
print "4. UDP-skanning" >> $loggfil
nmap -sU -T4 -p- -oN $utdatamappe/udp_scan.txt $ips >> $loggfil 2>&1
# Tips: Kan ta tid – vurder å begrense porter om nødvendig

# 5. Tjeneste- og versjonsdeteksjon – hva kjører på portene?
print "5. Tjeneste- og versjonsdeteksjon" >> $loggfil
# Pure zsh: Extract open ports from nmap output
typeset -a port_lines open_ports

nmap_scan=$(nmap -p- $target 2>/dev/null)
port_lines=("${(@f)nmap_scan}")
for line in "${port_lines[@]}"; do
  # Match lines starting with digits (port numbers)
  if [[ "$line" =~ ^[0-9] ]]; then
    # Extract port number before the slash (pure parameter expansion)
    local port="${line%%/*}"
    open_ports+=("$port")
  fi
done
# Join array with commas (pure zsh)
åpne_porter="${(j:,:)open_ports}"
[[ -n "$åpne_porter" ]] && nmap -sV -p $åpne_porter -oN $utdatamappe/tjenester.txt $ips >> $loggfil 2>&1
# Triks: Avslører utdaterte tjenester med svakheter
# 6. Styresystemdeteksjon – hvilket system er det?
print "6. Styresystemdeteksjon" >> $loggfil
nmap -O -oN $utdatamappe/styresystem.txt $ips >> $loggfil 2>&1
# Hemmelighet: Nøyaktig OS-info hjelper videre analyser

# 7. Svakhetsskanning – finner kjente problemer.
print "7. Svakhetsskanning" >> $loggfil
nmap -A --script "default,safe,vuln" -oA $utdatamappe/svakheter $ips >> $loggfil 2>&1
# Tips: "vuln"-skript finner kjente feil automatisk

# 8. Nettsideskanning – hvis HTTP/HTTPS er åpent (pure zsh pattern matching).
web_scan=$(nmap -p80,443 $target 2>/dev/null)
if [[ "$web_scan" == *"open"* ]]; then
    print "8. Nettsideskanning" >> $loggfil

    nmap --script "http-enum,http-vuln*,http-headers,http-methods" -p80,443 -oN $utdatamappe/nettside.txt $ips >> $loggfil 2>&1
    # Hemmelighet: Kan avsløre skjulte sider og feilkonfigurasjoner
fi
# Avslutter og gir deg resultatene.
print -P "%BSkanning ferdig klokken $(date).%b Se $loggfil og $utdatamappe!" | tee -a $loggfil
