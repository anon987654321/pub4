#!/usr/bin/env zsh
# mov.sh — Critically acclaimed / festival / Oscar movies (2023+)
# Zero args or --library: prune junk → auto-download all prestige finds (parallel when flock available).

# Origin: https://gist.github.com/anon987654321/02f78d6a2f32bce0167a5ce3f066d38e
# Works on both Termux (Android) and regular Linux.
# Updated for current Cinemeta + Torrentio APIs (as of 2026).
# Requires: zsh, curl, jq, aria2c, ffprobe (optional)
#
# Fetches REAL proper critically acclaimed + major film festival nominees/winners (Cannes, Oscars etc) new as of 2025 onwards.
# Uses curated prestige IDs (Cannes Palme/Grand Prix/Jury winners, Oscar contenders etc) + live catalogs.
# Skips CAM/TS etc. Prefers proper 1080p/BluRay encodes.
#
# Just run it (zero args): autonomously fetches prestige festival/Oscar titles to disk.
# With extra flags: preview mode, manual pick, or advanced tuning — see --help.
#
# On Termux: defaults to ~/storage/external-1 (after running termux-setup-storage).
# On Linux:   defaults to ~/Downloads/mov-sh.
#
# Usage examples:
#   ./mov.sh                     # just works (smart dir: external-1 on Termux, Downloads on Linux)
#   ./mov.sh -y                  # actually download selected movies
#   ./mov.sh --top=12 -y         # show more options and download
#   ./mov.sh --source=prestige --auto -y   # autonomously fetch real festival/Oscar 2025+ titles that have torrents
#   ./mov.sh --help
#
# WARNING: Downloads copyrighted content. Use at your own risk. Consider a VPN.
#          Torrents can be large; ensure you have bandwidth, disk space, and legal rights.
set -euo pipefail

emulate -L zsh -o extendedglob -o pipefail -o interactivecomments
setopt LOCALOPTIONS NO_POSIXBUILTINS
typeset -F 10

# ── Zsh-native helpers (no awk/sed/tr) ────────────────────────────────────
mov_lower() { print -r -- ${${1//\\n/ }:l} }

mov_strip_field() { print -r -- ${1//[[:space:]]/} }

mov_trim() { local s=$1; s=${s##[[:space:]]}; s=${s%%[[:space:]]}; print -r -- $s }

float_gt() { (( $1 > $2 )) }

float_le() { (( $1 <= $2 )) }

math() {
  local expr=${(j: :)@}
  print $(( ${expr} ))
}

get_available_gb() {
  local target=$1 avail_kb df_out
  local -a lines fields
  df_out=$(df -k "$target" 2>/dev/null) || { print 0; return }
  lines=("${(@f)df_out}")
  if [[ ${#lines} -lt 2 ]]; then
    print 0
    return
  fi
  fields=(${=lines[2]})
  avail_kb=${fields[4]:-0}
  [[ $avail_kb == <-> ]] || avail_kb=0
  print $(( avail_kb / 1024.0 / 1024.0 ))
}

size_to_gb() {
  local size_str=$1
  if [[ $size_str =~ '([0-9.]+)[[:space:]]*GB' ]]; then
    print -r -- $match[1]
  elif [[ $size_str =~ '([0-9.]+)[[:space:]]*MB' ]]; then
    print $(( match[1] / 1024.0 ))
  else
    print 9999.0
  fi
}

uri_encode() {
  local input=$1 output= char enc
  for (( i = 1; i <= ${#input}; i++ )); do
    char=${input[i]}
    if [[ $char =~ '[-_.~a-zA-Z0-9]' ]]; then
      output+=$char
    else
      enc=$(command printf '%%%02X' $((#char)))
      output+=${enc:l}
    fi
  done
  print -r -- $output
}

merge_torrent_candidates() {
  local -A seeds sizes
  local line hash h seeders sz
  local -a lines
  [[ -n $1 ]] && lines+=(${(f)1})
  [[ -n $2 ]] && lines+=(${(f)2})
  for line in $lines; do
    [[ $line == *'|'* ]] || continue
    IFS='|' read -r hash sz seeders <<< "$line"
    h=${hash:l}
    [[ $h =~ '^[0-9a-f]{40}$' ]] || continue
    seeders=${seeders//[!0-9]/}
    [[ -n $seeders ]] || seeders=0
    if (( ${seeds[$h]:-0} < seeders )); then
      seeds[$h]=$seeders
      sizes[$h]=$sz
    fi
  done
  local h
  for h in ${(ko)seeds}; do
    print -r -- "$h|${sizes[$h]}|${seeds[$h]}"
  done | sort -t'|' -k3,3nr -k2,2n
}

csv_has_id() {
  local csv=$1 id=$2
  [[ ",${csv}," == *",${id},"* ]]
}

dedup_candidates() {
  local input=$1 skip_csv=$2 prestige_csv=$3 priority_csv=$4 top=$5 mode=$6
  local -A seen
  local -a rows
  local line p rating year imdb title
  while IFS=$'	' read -r rating year imdb title; do
    [[ -n $imdb && -n $seen[$imdb] ]] && continue
    csv_has_id "$skip_csv" "$imdb" && continue
    seen[$imdb]=1
    if [[ $mode == all ]]; then
      if csv_has_id "$prestige_csv" "$imdb"; then p=1; else p=0; fi
      rows+=("${p}	${rating}	${year}	${imdb}	${title}")
    else
      if csv_has_id "$priority_csv" "$imdb"; then p=1; else p=0; fi
      rows+=("${p}	${rating}	${year}	${imdb}	${title}")
    fi
  done <<< "$input"
  if [[ $mode == all ]]; then
    print -l ${(on)rows} | sort -t$'	' -k1,1nr -k2,2nr | cut -f2- | head -n "$top"
  else
    print -l ${(on)rows} | sort -t$'	' -k1,1nr -k3,3nr | cut -f2- | head -n "$top"
  fi
}

get_prestige_imdb_csv() {
  local -a ids
  local year imdb _title
  while IFS=$'	' read -r year imdb _title; do
    imdb=${imdb//[[:space:]]/}
    [[ $imdb =~ '^tt[0-9]+$' ]] && ids+=($imdb)
  done <<< "$PRESTIGE_LIST"
  if [[ -n $EXTRA_PRESTIGE_ROWS ]]; then
    while IFS=$'	' read -r year imdb _title; do
      imdb=${imdb//[[:space:]]/}
      [[ $imdb =~ '^tt[0-9]+$' ]] && ids+=($imdb)
    done <<< "$EXTRA_PRESTIGE_ROWS"
  fi
  if [[ -f $PRESTIGE_USER_FILE ]]; then
    while IFS=$'	' read -r year imdb _title; do
      [[ -n $imdb ]] && ids+=($imdb)
    done < "$PRESTIGE_USER_FILE"
  fi
  print -l ${(u)ids} | paste -sd, -
}

get_priority_imdb_csv() {
  local s=${${PRIORITY_IMDBS//$'
'/}//[[:space:]]/}
  s=${s//,,/,}
  s=${s#,}
  s=${s%,}
  print -r -- $s
}

# ── Curated download queues (replaces queue-remaining.sh and ad-hoc batches) ─
QUEUE_MODE=""

mov_script_path() { print -r -- ${(%):-%x} }

run_mov_batch() {
  local label=$1 logfile=$2; shift 2
  print "" | tee -a "$logfile"
  print "========== $label $(date) ==========" | tee -a "$logfile"
  "$(mov_script_path)" --no-sync-owned --no-prune --source=imdb "$@" --auto -y 2>&1 | tee -a "$logfile"
}

dispatch_queue() {
  local q=$1
  local logdir=${DOWNLOAD_DIR:h}
  case $q in
    indonesia)
      run_mov_batch INDONESIA "$logdir/mov-sh-remaining.log" \
        --year-min=1930 \
        --imdb=tt7076834 --imdb=tt5923026 --imdb=tt9000302 --imdb=tt0288127 --imdb=tt0022689 \
        --parallel=3 --max-size=6.0
      ;;
    refetch-broken)
      run_mov_batch REFETCH-BROKEN "$logdir/mov-sh-refetch-broken.log" \
        --year-min=2020 \
        --imdb=tt27445004 --imdb=tt32843349 --imdb=tt31015216 --imdb=tt32083311 \
        --parallel=2 --max-size=6.0
      ;;
    benelux-nz)
      run_mov_batch BENELUX-NZ "$logdir/mov-sh-benelux-nz.log" \
        --year-min=1980 \
        --imdb=tt0107822 --imdb=tt0110729 --imdb=tt0389557 --imdb=tt0112379 \
        --imdb=tt0092610 --imdb=tt0110005 --imdb=tt0200071 \
        --parallel=4 --max-size=6.0
      ;;
    abang)
      run_mov_batch ABANG "$logdir/mov-sh-verify-restart.log" \
        --year-min=2020 --imdb=tt27445004 --max-size=6.0
      ;;
    impetigore)
      run_mov_batch IMPETIGORE "$logdir/mov-sh-verify-restart.log" \
        --year-min=2019 --imdb=tt9000302 --max-size=6.0
      ;;
    remaining)
      dispatch_queue indonesia
      print "========== ALL DONE $(date) ==========" | tee -a "$logdir/mov-sh-remaining.log"
      ;;
    *)
      print -u2 "Unknown --queue=$q (indonesia | refetch-broken | benelux-nz | abang | impetigore | remaining)"
      return 1
      ;;
  esac
}


# ── Platform Detection ─────────────────────────────────────────────────────
is_termux() {
    # Most reliable checks for real Termux (including proot-distro)
    [[ -n "${TERMUX_VERSION:-}" ]] ||
    [[ -n "${TERMUX__PREFIX:-}" ]] ||
    [[ -n "${PREFIX:-}" && "$PREFIX" == *"com.termux"* ]] ||
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# macOS: parallel Stremio search needs flock (brew install flock); add common prefixes to PATH.
if ! is_termux && [[ "$(uname -s 2>/dev/null)" == Darwin ]]; then
    for _brew_prefix in /opt/homebrew /usr/local; do
        if [ -x "${_brew_prefix}/bin/flock" ]; then
            export PATH="${_brew_prefix}/bin:${PATH}"
            break
        fi
    done
fi

# ── Configuration ──────────────────────────────────────────────────────────
if is_termux; then
    # Termux on Android — default to external storage (SD card / USB OTG)
    DEFAULT_DOWNLOAD_DIR="${HOME}/storage/external-1"
else
    # Regular Linux
    DEFAULT_DOWNLOAD_DIR="${HOME}/Downloads/mov-sh"
fi

DOWNLOAD_DIR="${DOWNLOAD_DIR:-$DEFAULT_DOWNLOAD_DIR}"
STATE_DIR="${STATE_DIR:-${HOME}/mov-sh-state}"
STAGING_DIR="${STAGING_DIR:-${DOWNLOAD_DIR}/staging}"   # incomplete pulls; promoted after verify
MIN_RATING=6.5
MIN_YEAR=2025
MAX_YEAR="$(date +%Y)"
TARGET_QUALITY="1080p"
MAX_DOWNLOADS=100
TOP_COUNT=50
MAX_SIZE_GB=4.0             # prefer compact WEBRips over 15+ GB encodes
ENGLISH_ONLY=false          # if true: English audio only (no international)
REQUIRE_ENG_SUBS=true       # international OK — but torrent must have English subs or English audio
HISTORY_FILE="${STATE_DIR}/history"
DRY_RUN=false
DO_DOWNLOAD=false
LIST_ONLY=false
DOWNLOAD_TIMEOUT_SEC=2700   # 45 min per torrent — prevents overnight stalls on dead magnets
MIN_SEEDERS=1               # prefer torrents with at least this many seeders
MIN_SIZE_GB=0.7             # skip tiny/wrong-movie releases (samples, mislabeled torrents)
PARALLEL_DOWNLOADS=1        # simultaneous aria2 jobs (use --parallel=N)
PARALLEL_EXPLICIT=false
SELECT_ARG=""
SOURCE_ARG="prestige"   # prestige (real fest/awards 2025+) | top | imdb | yts | all
PAGES=3
YEAR_EXPLICIT=false
AUTO_MODE=false
SKIP_FILE="${STATE_DIR}/skip"
PRESTIGE_USER_FILE="${STATE_DIR}/prestige"
SKIP_LIST_MERGED=""
SYNC_OWNED=false          # scan download dir and treat matches as owned/skipped
NO_SYNC_OWNED=false
FILTER_CATALOG_JUNK=true  # drop concerts/TV/anime noise from Cinemeta top/all catalogs
PURGE=false
LOOKUP_MODE=false
LOOKUP_QUERY=""
SEARCH_QUERIES=()
IMDB_TARGETS=()
EXTRA_SKIP_IDS=()
EXTRA_PRESTIGE_ROWS=""
LIBRARY_MODE=false
CLEANUP_SEEN=false
PRUNE_INVALID=true       # remove sparse partials / orphan .aria2 on startup
KEEP_HOURS=48            # cleanup-seen: keep media newer than this (hours); 0 = delete all matches
MIN_FREE_GB=3.0          # stop downloading when less than this many GB free
ALLOW_CAM=false          # if true: accept CAM/HDTS/TS (theatrical recordings — low quality)
STREMIO_LOCK="${STATE_DIR}/stremio.lock"
RUN_LOCK="${STATE_DIR}/mov.sh.lock"
FILE_ALLOCATION=trunc       # trunc avoids sparse holes that look complete but won't play
FORCE_RUN=false
REFETCH_IDS=()

# Bad release tags we explicitly reject (see is_good_release() for the actual matching logic)
# Kept here for documentation / easy future extension.

# Multi-Addon Array (Falls through in order until a torrent is found)
# Request proper 480p/720p/1080p encodes; exclude CAM/TS junk via client-side filter.
STREMIO_ADDONS=(
    "torrentio.strem.fun/qualityfilter=480p,720p,1080p"
    "knightcrawler.strem.fun/qualityfilter=480p,720p,1080p"
    "torrentio.strem.fun"
    "mediafusion.strem.fun"
    "comet.strem.fun"
)
YTS_DOMAINS=("yts.mx" "yts.am" "yts.lt")

# ── Real prestige 2025+ (Cannes/Sundance/Berlin/Venice winners, indie gems, Oscar darlings)
# Curated from festival awards + critics' streaming picks (updated June 2026).
# Format per line: YEAR<TAB>IMDB_ID<TAB>TITLE
PRESTIGE_LIST="
# Cannes 2026 (79th) — Palme, Grand Prix, acting/directing prizes, Caméra d'Or
2026	tt35410859	Fjord (Cannes 2026 Palme d'Or)
2026	tt37118301	Minotaur (Cannes 2026 Grand Prix)
2026	tt21188986	The Dreamed Adventure (Cannes 2026 Jury Prize)
2026	tt37304295	Fatherland (Cannes 2026 Best Director)
2026	tt35511966	La Bola Negra (Cannes 2026 Best Director)
2026	tt36834996	All Of A Sudden (Cannes 2026 Best Actress)
2026	tt39328391	Coward (Cannes 2026 Best Actor)
2026	tt38820979	Ben'imana (Cannes 2026 Caméra d'Or)
# Cannes 2025 (78th) — competition + Un Certain Regard darlings
2025	tt36491653	It Was Just an Accident (Cannes 2025 Palme d'Or)
2025	tt28690468	Sound of Falling (Cannes 2025 Jury Prize)
2025	tt27847051	The Secret Agent (Cannes 2025 Best Director/Actor)
2025	tt32909489	Young Mothers (Cannes 2025 Best Screenplay)
2025	tt29002950	Resurrection (Cannes 2025 Bi Gan Special Award)
2025	tt32275943	Alpha (Cannes 2025)
2025	tt31176520	Eddington (Cannes 2025)
2025	tt35715953	Urchin (Cannes 2025 Un Certain Regard)
2025	tt32321317	Pillion (Cannes 2025 Un Certain Regard)
2025	tt35695538	My Father's Shadow (Cannes 2025 Caméra d'Or mention)
# Sundance 2026 — Grand Jury, Audience, NEXT innovators
2026	tt32321285	Josephine (Sundance 2026 Grand Jury + Audience)
2026	tt39150922	Nuisance Bear (Sundance 2026 Grand Jury Documentary)
2026	tt39140264	Shame and Money (Sundance 2026 World Cinema Grand Jury)
2026	tt39150043	To Hold a Mountain (Sundance 2026 World Doc Grand Jury)
2026	tt36980182	The Incomer (Sundance 2026 NEXT Innovator)
2026	tt36840995	Hold Onto Me (Sundance 2026 Audience World Dramatic)
2026	tt37263549	Take Me Home (Sundance 2026 Waldo Salt Screenwriting)
2026	tt35504660	Bedford Park (Sundance 2026 Debut Feature)
2026	tt39150095	TheyDream (Sundance 2026 NEXT Special Jury)
# Sundance 2025 — indie breakout hits
2025	tt31122579	Atropia (Sundance 2025 Grand Jury Dramatic)
2025	tt31322753	Twinless (Sundance 2025 Audience Dramatic)
2025	tt32843349	Sorry Baby (Sundance 2025 Waldo Salt Screenwriting)
2025	tt34966013	Come See Me in the Good Light (Sundance 2025 Festival Favorite)
2025	tt27674982	The Ballad of Wallis Island (Sundance 2025 darling)
2025	tt34964187	DJ Ahmet (Sundance 2025 Audience World)
2025	tt27550504	Plainclothes (Sundance 2025 Special Jury Ensemble)
2025	tt27827635	Ricky (Sundance 2025 Directing Award)
# Critics' darlings + streaming platform hits (June 2026)
2025	tt32928666	Familiar Touch (indie gem — critics' pick)
2025	tt14905854	Hamnet (2025 Oscar darling)
2026	tt32273171	The Death of Robin Hood (A24 critics' pick June 2026)
# Current theatrical / RT Certified Fresh 2026 (live discovery supplements this)
2026	tt15047880	Disclosure Day (Spielberg — RT 80% Certified Fresh)
2026	tt37287335	Obsession (2026 thriller — Cinemeta trending)
2026	tt32565993	The Sheep Detectives (2026 — Cinemeta top)
# Rotten Tomatoes Certified Fresh 2024–2025 (97%+ Tomatometer)
2025	tt32792934	The Plague (RT 97% — Joel Edgerton chiller)
2026	tt1527793	No Other Choice (Park Chan-wook — RT 97%)
2024	tt28332337	Eephus (RT 100% — baseball indie)
2024	tt32086046	Souleymane's Story (RT 100% — Cannes darling)
2025	tt27722618	Left-Handed Girl (RT 98% — Taipei family drama)
2024	tt32060445	Sister Midnight (RT 98% — Mumbai genre-bender)
2024	tt32083311	On Becoming a Guinea Fowl (RT 100% — Zambian family drama)
2024	tt4772188	Flow (Oscar Best Animated — wordless cat adventure)
2024	tt27958252	Caught by the Tides (RT 99% — Jia Zhangke epic)
# Oscar 2025/2026 cycle — festival-to-streaming prestige
2025	tt28607951	Anora (Palme d'Or — Oscar Best Picture)
2025	tt8999762	The Brutalist (Venice — Oscar darling)
2025	tt28082769	September 5 (Oscar contender)
2024	tt14961016	I'm Still Here (Oscar Best Picture nominee)
2024	tt11563598	A Complete Unknown (Oscar Best Picture nominee)
2024	tt23055660	Nickel Boys (Oscar Best Picture nominee)
2024	tt20221436	Emilia Pérez (Oscar 13-nom darling)
2023	tt28479262	Sing Sing (Oscar acting nominee)
2025	tt32178949	The Seed of the Sacred Fig (Berlin Golden Bear)
2025	tt21823606	A Real Pain (Sundance 2024 breakout)
2025	tt11687002	The Outrun (Saoirse Ronan indie gem)
2025	tt32086077	All We Imagine as Light (Cannes indie gem)
# Oscar 2026 Best Picture — full nominee slate (March 2026)
2025	tt31193180	Sinners (Golden Tomato Best Movie 2025)
2025	tt30144839	One Battle After Another (Oscar BP nominee — PTA)
2025	tt32916440	Marty Supreme (Oscar BP nominee — Safdie)
2025	tt12300742	Bugonia (Oscar BP nominee — Lanthimos)
2025	tt1312221	Frankenstein (Oscar BP nominee — del Toro)
2025	tt27714581	Sentimental Value (Oscar BP nominee — Joachim Trier)
2025	tt29768334	Train Dreams (Oscar BP nominee)
2025	tt16311594	F1 The Movie (Oscar BP nominee)
2025	tt32536315	Blue Moon (Oscar contender)
2025	tt26581740	Weapons (Golden Tomato nominee 93%)
# Golden Tomato Awards 2025 — critics' champions
2025	tt14364480	Wake Up Dead Man (Golden Tomato Best Limited Release)
2025	tt30988739	Black Bag (RT 96% spy thriller)
2025	tt10548174	28 Years Later (RT 88% — Danny Boyle return)
# Venice / Cannes 2025 — Lido & Croisette darlings
2025	tt31194612	Highest 2 Lowest (Venice — Spike Lee)
2025	tt31189315	Father Mother Sister Brother (Venice — Yorgos)
2025	tt32159989	After the Hunt (Venice — Luca Guadagnino)
2025	tt32249940	Riefenstahl (Cannes documentary)
2025	tt32298285	Sirat (Cannes competition)
2025	tt28354053	The Shrouds (Venice — Cronenberg)
# Sundance 2025 — additional buzz titles
2025	tt13651462	Lurker (Sundance 2025 thriller)
2025	tt33292655	Oh, Hi! (Sundance 2025 rom-com)
# Oscar 2025 cycle — 2024 releases (streaming darlings)
2024	tt20215234	Conclave (Oscar BP winner 2025)
2024	tt17526714	The Substance (Oscar darling — Demi Moore)
2024	tt5040012	Nosferatu (Oscar contender — Eggers)
2024	tt16426418	Challengers (Oscar tech nom — Guadagnino)
2024	tt30057084	Babygirl (Oscar acting buzz)
2024	tt21097228	A Different Man (indie acclaimed)
2024	tt27367464	Kneecap (Oscar International nom)
2025	tt26625693	The Order (Oscar contender — Jude Law)
2024	tt1262426	Wicked (Oscar spectacle nominee)
2024	tt28491891	His Three Daughters (critics' ensemble pick)
2024	tt28366692	Janet Planet (critics' indie gem)
2024	tt19637052	Love Lies Bleeding (indie queer epic)
# Oscar 2024 cycle — 2023 releases still essential viewing
2023	tt13238346	Past Lives (Oscar BP nominee)
2023	tt14849194	The Holdovers (Oscar BP nominee)
2023	tt5537002	Killers of the Flower Moon (Oscar BP nominee)
2023	tt13651794	May December (indie darling)
2023	tt22041854	Priscilla (Sofia Coppola biopic)
2023	tt7160372	The Zone of Interest (Oscar BP nominee)
2023	tt14230458	Poor Things (Oscar BP nominee)
# RT Certified Fresh + acclaimed docs (June 2026 expansion)
2025	tt37660887	Cover-Up (RT 98% — Hersh/Poitras journalism doc)
2025	tt34965967	Deaf President Now! (RT 100% activism doc)
2025	tt34962891	The Perfect Neighbor (RT 99% — stand your ground doc)
2025	tt33322301	Marlee Matlin: Not Alone Anymore (RT 98% doc)
2024	tt21221386	Secret Mall Apartment (RT 98% doc)
2024	tt32606918	From Ground Zero (RT 98% — Gaza short films)
2025	tt34621966	MegaDoc (RT Certified Fresh documentary)
2026	tt31514146	I Swear (RT 97% — disability coming-of-age)
2025	tt30343021	Song Sung Blue (RT Certified Fresh musical drama)
2025	tt30505698	Friendship (Tim Robinson indie comedy darling)
# Oscar International + festival expansions 2024–2026
2024	tt10236164	The Girl with the Needle (Oscar Int'l Feature nom)
2024	tt28618488	Vermiglio (Oscar Int'l nom — Italian period epic)
2024	tt11891850	Hard Truths (Mike Leigh — Cannes competition)
2025	tt32376165	A House of Dynamite (Netflix prestige thriller)
2024	tt15042300	On Swift Horses (indie queer romance)
2025	tt12908150	The Life of Chuck (Mike Flanagan literary drama)
2024	tt28015403	Heretic (Hugh Grant horror — critics' hit)
2024	tt8368368	The Apprentice (Trump origin biopic)
2025	tt34886821	La Grazia (Cannes 2025 — Nanni Moretti)
2025	tt32063098	Ballad of a Small Player (noir thriller)
2024	tt23853982	Parthenope (Sorrentino Venice darling)
2024	tt22893404	Maria (Pablo Larraín — Jolie opera biopic)
2024	tt27490099	Beating Hearts (Justine Triet romance)
2025	tt33455099	The Mastermind (Kelly Reichardt crime)
2025	tt14142060	Rental Family (Tokyo indie gem)
2024	tt30253514	Pavements (Silver Jews rock doc)
2024	tt23770030	Memoir of a Snail (Oscar animated nom)
2024	tt31015216	Dahomey (Berlin Golden Bear documentary)
2024	tt29344894	All That's Left of You (Palestinian family drama)
2024	tt26745321	Armand (Berlin — child abuse allegory)
2025	tt20969586	Thunderbolts* (Marvel ensemble — user keep)
# Malay world (Malay-language Malaysian — not Chinese diaspora / not Nordic)
2023	tt27445004	Abang Adik (Malaysia — Berlin Silver Bear, Malay drama)
2022	tt11347146	Mat Kilau (Malaysia — historical epic, Malay) [seen]
2023	tt22479650	Pendatang (Malaysia dystopia — crowdfunded darling)
2023	tt10803634	Tiger Stripes (Malaysia — Cannes Critics' Week) [seen]
2024	tt27180099	Grand Tour (Miguel Gomes — Asia wander epic)
2024	tt27476906	When the Light Breaks (Iceland — Cannes Un Certain Regard)
2026	tt13848364	We Are All Strangers (Anthony Chen — Chinese diaspora, deprioritized)
# Global South neighbours — Indian Ocean rim / Central America / Caribbean / Suriname
# (Zambia/Benin/Senegal trio already in RT Certified section above)
2024	tt32046117	The Village Next to Paradise (Somalia — first Somali Cannes selection)
2024	tt33077007	Beloved Tropic (Panama — Oscar Int'l submission)
2025	tt22237964	The Mysterious Gaze of the Flamingo (Chile — Cannes Un Certain Regard)
1976	tt0075411	Wan Pipel (Suriname cult — first post-independence Surinamese film)
# Neighbour cult classics — title-validated seeds (Jun 2026 regional dig)
1973	tt0070820	Touki Bouki (Senegal — Mambéty road-movie cult, Criterion)
2019	tt10199586	Atlantics (Senegal — Mati Diop supernatural Cannes)
2014	tt3409392	Timbuktu (Mali — Sissako Oscar nom)
2005	tt0468565	Tsotsi (South Africa — Oscar winner)
1972	tt0070155	The Harder They Come (Jamaica — reggae outlaw cult)
2004	tt0378284	Machuca (Chile — Pinochet-era ensemble)
2017	tt5639354	A Fantastic Woman (Chile — Oscar winner)
2015	tt3742378	The Second Mother (Brazil — class-divide cult)
1994	tt0110729	Once Were Warriors (New Zealand — Māori family cult)
1994	tt0110005	Heavenly Creatures (New Zealand — Peter Jackson cult)
1993	tt0107822	The Piano (New Zealand — Campion Palme d'Or)
1987	tt0092610	Bad Taste (New Zealand — Jackson splatter debut)
2006	tt0389557	Black Book (Netherlands — Verhoeven WWII thriller)
1995	tt0112379	Antonia's Line (Netherlands — Oscar winner)
1999	tt0200071	Rosetta (Belgium — Dardenne Palme d'Or)
1996	tt0115832	Carla's Song (Nicaragua/Scotland — Ken Loach civil-war romance)
# Malay older + Indonesia + Melanesia/Pacific cult (Jun 2026 Ruby screen)
2011	tt1899353	The Raid (Indonesia — action cult classic) [seen]
2017	tt5923026	Marlina the Murderer (Indonesia — feminist western)
2017	tt7076834	Pengabdi Setan 2017 (Indonesia — horror remake)
2019	tt9000302	Impetigore (Indonesia — folk horror cult)
1987	tt0288127	Naga Bonar (Indonesia — satire cult)
1980	tt0281048	Pengabdi Setan (Indonesia — original Satan's Slave)
1932	tt0022689	Bird of Paradise (Melanesia — pre-code classic)
# P. Ramlee / classic Malay — wishlist (0 seeds Jun 2026): Hang Tuah, Bujang Lapok, Labu dan Labi,
# Seniman Bujang Lapok, Madu Tiga, Antara Dua Darjat, Sumpahan Orang Muda, Yasmin Ahmad pack
1961	tt0278028	Seniman Bujang Lapok (P. Ramlee meta-comedy)
1964	tt0277810	Madu Tiga (P. Ramlee polygamy farce)
1960	tt0277581	Antara Dua Darjat (P. Ramlee class satire)
# Pacific / Fiji / Solomon / PNG — wishlist (0 seeds): Tanna, Orator, Land Has Eyes, Ten Canoes, Reel Paradise
"

# Regional + comedy/island queue — screen and download before the general queue
PRIORITY_IMDBS="
tt15047880,tt32083311,tt31015216,tt32086046,tt27445004,tt7076834,tt5923026,tt9000302,tt0288127,tt0070820,tt10199586,tt3409392,tt22237964,tt22479650,tt33077007,tt32046117,tt0075411,tt31322753,tt32843349,tt33292655,tt30505698,tt27674982,tt32321317,tt27367464,tt34964187,tt10236164,tt32086077,tt27722618,tt31122579,tt28690468,tt35715953
"

# Library-mode live discovery (Cinemeta catalogs + search — catches new theatrical like Disclosure Day)
LIBRARY_DISCOVER_SEARCHES=(
  "critically acclaimed 2026"
  "new release 2026"
  "certified fresh 2026"
  "Spielberg 2026"
)

# Already owned — never re-download (edit when you've seen them / freed space)
SKIP_LIST="
tt31193180
tt32916440
tt30144839
tt32298285
tt26581740
tt27714581
tt14205554
tt32649961
tt37969426
tt28607951
tt8999762
tt20221436
tt10803634
tt1899353
tt11347146
"

# ───────────────────────────────────────────────────────────────────────────

# ── Parse Arguments ────────────────────────────────────────────────────────
ORIGINAL_ARGC=$#
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run|--preview) DRY_RUN=true; shift ;;
    -y|--yes|--download) DO_DOWNLOAD=true; shift ;;  # documented for "actually perform downloads" (default behavior in non-dry runs)
    -l|--list) LIST_ONLY=true; shift ;;
    --max=*) MAX_DOWNLOADS="${1#*=}"; shift ;;
    --top=*) TOP_COUNT="${1#*=}"; shift ;;
    --quality=*) TARGET_QUALITY="${1#*=}"; shift ;;
    --dir=*) DOWNLOAD_DIR="${1#*=}"; shift ;;
    --year=*) MIN_YEAR="${1#*=}"; MAX_YEAR="${1#*=}"; YEAR_EXPLICIT=true; shift ;;
    --year-min=*) MIN_YEAR="${1#*=}"; YEAR_EXPLICIT=true; shift ;;
    --year-max=*) MAX_YEAR="${1#*=}"; shift ;;
    --rating=*) MIN_RATING="${1#*=}"; shift ;;
    --select=*) SELECT_ARG="${1#*=}"; shift ;;
    --source=*) SOURCE_ARG="${1#*=}"; shift ;;
    --pages=*) PAGES="${1#*=}"; shift ;;
    --max-size=*) MAX_SIZE_GB="${1#*=}"; shift ;;
    --allow-dubbed) REQUIRE_ENG_SUBS=false; ENGLISH_ONLY=false; shift ;;
    --allow-cam) ALLOW_CAM=true; shift ;;
    --english-only) ENGLISH_ONLY=true; REQUIRE_ENG_SUBS=false; shift ;;
    --no-sub-requirement) REQUIRE_ENG_SUBS=false; shift ;;
    --parallel=*) PARALLEL_DOWNLOADS="${1#*=}"; PARALLEL_EXPLICIT=true; shift ;;
    --auto) AUTO_MODE=true; [ -z "$SELECT_ARG" ] && SELECT_ARG="all"; shift ;;
    --library|--netflix) LIBRARY_MODE=true; shift ;;
    --cleanup-seen) CLEANUP_SEEN=true; shift ;;
    --no-cleanup-seen) CLEANUP_SEEN=false; shift ;;
    --no-prune) PRUNE_INVALID=false; shift ;;
    --keep-hours=*) KEEP_HOURS="${1#*=}"; shift ;;
    --min-free-gb=*) MIN_FREE_GB="${1#*=}"; shift ;;
    --imdb=*) IMDB_TARGETS+=("${1#*=}"); shift ;;
    --skip=*) EXTRA_SKIP_IDS+=("${1#*=}"); shift ;;
    --seen=*) EXTRA_SKIP_IDS+=("${1#*=}"); shift ;;
    --refetch=*) REFETCH_IDS+=("${1#*=}"); shift ;;
    --force) FORCE_RUN=true; shift ;;
    --sparse) FILE_ALLOCATION=none; shift ;;
    --search=*) SEARCH_QUERIES+=("${1#*=}"); shift ;;
    --lookup=*) LOOKUP_QUERY="${1#*=}"; LOOKUP_MODE=true; shift ;;
    --sync-owned) SYNC_OWNED=true; shift ;;
    --no-sync-owned) SYNC_OWNED=false; NO_SYNC_OWNED=true; shift ;;
    --no-junk-filter) FILTER_CATALOG_JUNK=false; shift ;;
    --queue=*) QUEUE_MODE="${1#*=}"; shift ;;
    --queue) QUEUE_MODE="$2"; shift 2 ;;
    --purge) PURGE=true; shift ;;
    --add-prestige=*) EXTRA_PRESTIGE_ROWS+=$'\n'"${1#*=}"; shift ;;
    --help)
      cat <<EOF
mov.sh — critically acclaimed / film festival nominees torrent downloader (2025+ focus)

Main flow:
  1. Fetches from "prestige" source (real Cannes winners, Oscar nominees, festival darlings 2025+) + catalogs
  2. Shows a numbered list
  3. Lets you select which ones to process (e.g. "1 3 5-7" or "all")  OR use --auto for non-interactive
  4. For each: finds best proper torrent (Stremio addons/YTS), skips all CAM/TS/screener junk
  5. Downloads with aria2c (or --dry-run preview)

Options:
  (default)             Show 2025+ prestige + top movies and preview (safe)
  -n, --dry-run         Explicit preview mode (same as default)
  -y, --yes, --download Actually download the torrents you select (use with care)
  -l, --list            Just list the movies (no torrent search)
  --auto                Fully autonomous: skip prompt, auto pick & process ones with available torrents (best with -y)
  --library             Same as zero-arg: autonomous prestige auto-download
  --cleanup-seen        Delete on-disk media matching ~/mov-sh-state/skip (frees space for new pulls)
  --no-cleanup-seen     Skip seen-library cleanup (default for zero-arg / --library)
  --keep-hours=N        During cleanup-seen, keep media modified within N hours (default: 48 in --library)
  --min-free-gb=N       Stop downloading when free disk drops below N GB (default: 3)
  --no-prune            Skip startup prune of sparse partials and stale .aria2 files
  --seen=IMDB_ID        Mark title as seen — same as --skip (persisted to ~/mov-sh-state/skip)
  --refetch=IMDB_ID     Re-fetch a title (removes from history/skip for this run; repeatable)
  --force               Skip singleton lock (use when a stale lock blocks a new run)
  --sparse              Use aria2 sparse allocation (saves disk; partials may look complete but fail playback)
  --top=N               How many to show (default: 30)
  --max=N               Maximum number of movies to download (default: 100)
  --quality=720p        Preferred quality (480p/720p/1080p proper encodes only)
  --dir=PATH            Target directory (smart default: ~/storage/external-1 on Termux, ~/Downloads/mov-sh on Linux)
                          Downloads land in PATH/staging first; promoted to PATH only after playable+audio verify
  --year=YYYY           Exact year (default min 2025, max current year)
  --year-min=YYYY       Minimum release year (default 2025)
  --year-max=YYYY       Maximum release year
  --rating=F            Minimum IMDb rating (default: 6.5; prestige source relaxes this)
  --source=SOURCE       Movie catalog: prestige (default: real fest/award 2025+), top, imdb, yts, all
                          prestige — Curated 2025+ Cannes Palme/prizes, Oscar nominees, critical darlings (guaranteed "proper acclaimed")
                          top    — Cinemeta trending/recent
                          imdb   — Cinemeta IMDb Top 250 (ignores year unless explicit)
                          yts    — YTS by rating
                          all    — every source above, combined
  --pages=N             Fetch N pages per catalog source (default: 2)
  --max-size=N          Max torrent size in GB (default: 4 — compact WEBRips)
  --english-only        English audio only — skip international releases (old behavior)
  --allow-dubbed        Allow any language/dub — no English subtitle requirement
  --no-sub-requirement  Same as --allow-dubbed (skip subtitle requirement)
  --parallel=N          Download N torrents at once (zero-arg: 6 on macOS/Linux with flock, else 1)
  --skip=IMDB_ID        Skip a title (repeatable); also persisted in ~/mov-sh-state/skip
  --sync-owned          Scan download dir + match prestige list → auto-skip owned titles
  --no-sync-owned       Disable owned-title scan
  --imdb=ID             Target one IMDb ID directly (repeatable; stable vs --search)
  --search=QUERY        Cinemeta search — add matches to candidate pool (repeatable)
  --lookup=QUERY        Resolve IMDB ID via Cinemeta and exit (for updating PRESTIGE_LIST)
  --add-prestige=ROW    Add one prestige row: YEAR<TAB>IMDB<TAB>TITLE
  --queue=NAME          Run curated batch: indonesia | refetch-broken | benelux-nz | abang | impetigore | remaining
  --purge               Delete all files in download dir before running
  --no-junk-filter      Allow concerts/TV/anime from Cinemeta top/all catalogs
  --allow-cam           Accept CAM/HDTS/TS theatrical recordings (low quality; use --max-size=8 for 1080p CAM)
  --help                This help

Skip / owned / seen:
  ~/mov-sh-state/history — download log; also blocks re-fetch after you delete files from disk
  ~/mov-sh-state/skip + --seen= — explicitly watched titles (never re-fetched; --cleanup-seen deletes these from disk)
  Inline SKIP_LIST — hardcoded never-fetch titles, listed in the script
  Zero-arg / --library: prestige list + live Cinemeta discovery → parallel auto-fetch (2023+)

Selection examples at the prompt:
  1 3 5          → pick movies #1, #3 and #5
  2-6,9          → pick 2 through 6 plus #9
  all            → select everything shown
  q or empty     → quit with nothing

With --auto + -y : autonomously downloads the first available proper torrents for real acclaimed 2025+ titles.

By default skips CAM, CAMRip, TS, HDTS, screeners and workprints. Use --allow-cam to accept theatrical recordings.

Examples:
  zsh mov.sh                            # just works: prestige auto-download, parallel, no flags
  ./mov.sh                              # same as above
  ./mov.sh --library                    # same as zero-arg
  ./mov.sh --cleanup-seen               # also delete seen titles from disk (free space)
  ./mov.sh --seen=tt28607951            # mark Anora seen; next run won't re-fetch it
  ./mov.sh --cleanup-seen --keep-hours=0   # wipe all skip-listed media from disk (max space)
  ./mov.sh -y                           # download what you pick (preview first without -y)
  ./mov.sh --auto -y                    # auto-fetch prestige finds (no cleanup unless --cleanup-seen)
  ./mov.sh --source=prestige --list     # just list the proper ones
  ./mov.sh --source=all --top=50 -y
  ./mov.sh --year-min=2025 --auto -y
  ./mov.sh --lookup="Fjord 2026"              # resolve IMDB ID for prestige list edits
  ./mov.sh --search="Cannes 2026 winners" --list
  ./mov.sh --skip=tt31193180 --auto -y        # skip Sinners et al.
  ./mov.sh --refetch=tt20215234 --auto -y     # re-download Conclave after a bad pull
  ./mov.sh --purge --auto -y                  # wipe dir, fetch only new titles
  Stale downloads: pkill -9 -x aria2c  (never pkill -f mov.sh — kills your shell)
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1"; shift ;;
  esac
done

# Curated batch queues (replaces queue-remaining.sh)
if [[ -n ${QUEUE_MODE:-} ]]; then
  STAGING_DIR="${STAGING_DIR:-${DOWNLOAD_DIR}/staging}"
  dispatch_queue "$QUEUE_MODE"
  exit $?
fi

# Lone --parallel=N → library mode (tune concurrency without extra flags).
if [ "$ORIGINAL_ARGC" -eq 1 ] && [ "$PARALLEL_EXPLICIT" = true ]; then
  LIBRARY_MODE=true
fi

# Zero-arg or --library: frictionless prestige auto-fetch (no prompts, no flags required).
# Never override when user passed explicit --imdb targets (queue batches, single-title fetches).
if { [ "$ORIGINAL_ARGC" -eq 0 ] || [ "$LIBRARY_MODE" = true ]; } && [ ${#IMDB_TARGETS} -eq 0 ]; then
  LIBRARY_MODE=true
  AUTO_MODE=true
  SOURCE_ARG="prestige"
  SELECT_ARG="all"
  DO_DOWNLOAD=true
  TOP_COUNT=200
  PAGES=2
  SYNC_OWNED=false
  NO_SYNC_OWNED=true
  CLEANUP_SEEN=false
  PRUNE_INVALID=true
  YEAR_EXPLICIT=true
  MIN_YEAR=2023           # Oscar 2024 cycle + fest darlings through 2026
  if [ "$PARALLEL_EXPLICIT" != true ]; then
    if is_termux || ! command -v flock >/dev/null 2>&1; then
      PARALLEL_DOWNLOADS=1
    else
      PARALLEL_DOWNLOADS=6
    fi
    PARALLEL_EXPLICIT=true
  fi
fi
if [ "$AUTO_MODE" = true ] && [ "$NO_SYNC_OWNED" != true ]; then
  SYNC_OWNED=true
fi

# Default: preview only. -y / zero-arg mode actually downloads.
if [ "$DRY_RUN" = true ]; then
  :
elif [ "$DO_DOWNLOAD" = true ]; then
  DRY_RUN=false
else
  DRY_RUN=true
fi

# Auto mode: default serial downloads (parallel torrent search/API calls hang).
if [ "$AUTO_MODE" = true ] && [ "$PARALLEL_EXPLICIT" = false ] && [ "$DRY_RUN" = false ]; then
  PARALLEL_DOWNLOADS=1
fi

# imdb source spans all time; only apply year filter if user set one explicitly.
# prestige always respects 2025+ (or explicit --year)
if [ "$YEAR_EXPLICIT" = false ] && [[ "$SOURCE_ARG" == "imdb" ]]; then
  MIN_YEAR=0
  MAX_YEAR=9999
fi
# For prestige source ensure sane recent window even if user didn't --year
if [[ "$SOURCE_ARG" == "prestige" ]] && [ "$YEAR_EXPLICIT" = false ]; then
  MIN_YEAR=2025
  # MAX_YEAR already current from config
fi


# ── Setup & Dependencies ───────────────────────────────────────────────────
migrate_legacy_mov_paths() {
  local legacy new item
  mkdir -p "$STATE_DIR"
  for legacy new in \
    "${HOME}/.mov_sh_history" "$HISTORY_FILE" \
    "${HOME}/.mov_sh_skip" "$SKIP_FILE" \
    "${HOME}/.mov_sh_prestige" "$PRESTIGE_USER_FILE"; do
    [[ -f $legacy && ! -s $new ]] && cp "$legacy" "$new"
  done
  legacy="${DOWNLOAD_DIR}/.staging"
  if [[ -d $legacy ]]; then
    mkdir -p "$STAGING_DIR"
    for item in "$legacy"/*(N); do
      [[ -e $item ]] || continue
      mv "$item" "$STAGING_DIR"/ 2>/dev/null || true
    done
    rmdir "$legacy" 2>/dev/null || true
  fi
}

mkdir -p "$DOWNLOAD_DIR" "$STATE_DIR" "$STAGING_DIR" || { echo "❌ Cannot create $DOWNLOAD_DIR"; exit 1; }
migrate_legacy_mov_paths

acquire_run_lock() {
  if [ "$FORCE_RUN" = true ]; then
    echo "⚠️  --force: skipping singleton lock"
    return 0
  fi
  if ! command -v flock >/dev/null 2>&1; then
    return 0
  fi
  exec 8>>"$RUN_LOCK"
  if ! flock -n 8; then
    echo "❌ Another mov.sh is already running (lock: $RUN_LOCK)"
    echo "   Kill stale workers: pkill -9 -x aria2c"
    echo "   Or re-run with --force"
    exit 1
  fi
}

cleanup_stale_aria2() {
  local pid cmd killed=0
  while IFS= read -r pid cmd; do
    [ -z "$pid" ] && continue
    [[ "$cmd" == *"$STAGING_DIR"* ]] || continue
    kill -9 "$pid" 2>/dev/null && killed=$((killed + 1))
  done < <(ps aux 2>/dev/null | grep '[a]ria2c' | awk -v staging="$STAGING_DIR" '$0 ~ staging {print $2, substr($0, index($0,$11))}')
  if [ "$killed" -gt 0 ]; then
    echo "  🧹 Killed $killed stale aria2 worker(s) for $STAGING_DIR"
  fi
}

acquire_run_lock
[ "$DRY_RUN" = false ] && [ "$DO_DOWNLOAD" = true ] && cleanup_stale_aria2

# Termux-specific storage warning (matches original Gist behavior)
if is_termux && [[ ! -d "${HOME}/storage" ]]; then
    echo "❌ Termux storage not set up."
    echo "   Please run 'termux-setup-storage' first, then re-run this script."
    echo "   This gives access to ~/storage/external-1 (SD card / USB)."
    exit 1
fi

install_if_missing() {
  local cmd="$1" pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  echo "⚙️  Installing $pkg (provides $cmd)..."

  if is_termux; then
    # Prefer Termux's pkg manager
    pkg install -y "$pkg" 2>/dev/null || apt install -y "$pkg"
  elif command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update -qq
      apt-get install -y -qq "$pkg"
    else
      sudo apt-get update -qq
      sudo apt-get install -y -qq "$pkg"
    fi
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "$pkg"
  else
    echo "❌ No supported package manager found. Please install $pkg manually."
    return 1
  fi
}

install_if_missing curl curl
install_if_missing jq jq
install_if_missing aria2c aria2

touch "$HISTORY_FILE"
JOB_STATE_DIR="${TMPDIR:-/tmp}/mov-sh-$$"
mkdir -p "$JOB_STATE_DIR"
cleanup_job_state() { rm -rf "$JOB_STATE_DIR"; }
trap cleanup_job_state EXIT

append_history_imdb() {
  local imdb="$1"
  [[ "$imdb" =~ ^tt[0-9]+$ ]] || return 0
  grep -qF "$imdb" "$HISTORY_FILE" 2>/dev/null || echo "$imdb" >> "$HISTORY_FILE"
}

SESSION_SUCCESS_COUNT=0

record_job_success() {
  local imdb="$1"
  touch "$JOB_STATE_DIR/success-${imdb}"
  append_history_imdb "$imdb"
  append_skip_imdb "$imdb"
  (( SESSION_SUCCESS_COUNT++ ))
}

count_job_successes() {
  print $SESSION_SUCCESS_COUNT
}

wait_for_download_slot() {
  local max="$1" running
  while true; do
    running=$(jobs -r 2>/dev/null | wc -l | tr -d ' ')
    [[ "$running" =~ ^[0-9]+$ ]] || running=0
    (( running < max )) && break
    sleep 1
  done
}

# ── Skip list management (inline + file + history + CLI + owned scan) ─────
is_skipped_imdb() {
  local imdb="$1"
  grep -qF "$imdb" <<< "$SKIP_LIST_MERGED" 2>/dev/null
}

load_skip_lists() {
  SKIP_LIST_MERGED="$SKIP_LIST"
  touch "$SKIP_FILE"
  [ -s "$SKIP_FILE" ] && SKIP_LIST_MERGED+=$'\n'"$(grep -E '^tt[0-9]+$' "$SKIP_FILE" 2>/dev/null || true)"
  # History = successfully downloaded before; treat as seen so manual deletes don't re-fetch.
  [ -s "$HISTORY_FILE" ] && SKIP_LIST_MERGED+=$'\n'"$(grep -E '^tt[0-9]+$' "$HISTORY_FILE" 2>/dev/null || true)"
  local id
  if [ ${#EXTRA_SKIP_IDS} -gt 0 ]; then
    for id in "${EXTRA_SKIP_IDS[@]}"; do
      [[ "$id" =~ ^tt[0-9]+$ ]] || continue
      SKIP_LIST_MERGED+=$'\n'"$id"
      grep -qF "$id" "$SKIP_FILE" 2>/dev/null || echo "$id" >> "$SKIP_FILE"
    done
  fi
  SKIP_LIST_MERGED=$(echo "$SKIP_LIST_MERGED" | grep -E '^tt[0-9]+$' | sort -u)
  apply_refetch_ids
}

apply_refetch_ids() {
  local id tmp
  [ ${#REFETCH_IDS[@]} -eq 0 ] && return 0
  for id in "${REFETCH_IDS[@]}"; do
    [[ "$id" =~ ^tt[0-9]+$ ]] || continue
    SKIP_LIST_MERGED=$(print -l ${(f)SKIP_LIST_MERGED} | grep -vF "$id" 2>/dev/null || true)
    if [ -s "$HISTORY_FILE" ]; then
      tmp=$(grep -vF "$id" "$HISTORY_FILE" 2>/dev/null || true)
      print -r -- "$tmp" >"$HISTORY_FILE"
    fi
    if [ -s "$SKIP_FILE" ]; then
      tmp=$(grep -vF "$id" "$SKIP_FILE" 2>/dev/null || true)
      print -r -- "$tmp" >"$SKIP_FILE"
    fi
    echo "  🔄 Refetch enabled: $id (removed from history/skip)"
  done
}

skip_list_count() {
  local n
  n=$(echo "$SKIP_LIST_MERGED" | grep -cE '^tt[0-9]+$' 2>/dev/null || true)
  echo "${n:-0}"
}

append_skip_imdb() {
  local imdb="$1"
  [[ "$imdb" =~ ^tt[0-9]+$ ]] || return 0
  if is_skipped_imdb "$imdb"; then return 0; fi
  echo "$imdb" >> "$SKIP_FILE"
  SKIP_LIST_MERGED+=$'\n'"$imdb"
}

# Serialize Stremio/YTS API calls — parallel workers otherwise hang on torrent search.
with_stremio_lock() {
  if command -v flock >/dev/null 2>&1; then
    flock -w 180 9 || return 1
  fi
  "$@"
}

# Remove sparse aria2 partials, zero-filled shells, and stale .aria2 sidecars.
prune_invalid_downloads() {
  local root path aria2 mmin_arg removed=0
  echo "🧹 Pruning invalid partial downloads..."
  for root in "$STAGING_DIR" "$DOWNLOAD_DIR"; do
    [ -d "$root" ] || continue
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      [ -f "${path}.aria2" ] && continue   # active download — never prune
      is_valid_media_file "$path" && continue
      rm -f "$path" "${path}.aria2" 2>/dev/null && removed=$((removed + 1)) && echo "  🗑️  partial: $(basename "$path")"
    done < <(find "$root" -maxdepth 3 \
        \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) 2>/dev/null)
    mmin_arg="+60"
    while IFS= read -r aria2; do
      [ -z "$aria2" ] && continue
      path="${aria2%.aria2}"
      [ -f "$path" ] || { rm -f "$aria2" 2>/dev/null; continue; }
      is_valid_media_file "$path" || rm -f "$path" "$aria2" 2>/dev/null
    done < <(find "$root" -maxdepth 3 -name '*.aria2' -mmin "$mmin_arg" 2>/dev/null)
  done
  if [ "$removed" -gt 0 ]; then
    echo "  ✅ Removed $removed invalid file(s)"
  fi
}

media_is_protected_by_keep_hours() {
  local fpath="$1" keep_h="$2" age_sec now mtime
  [ "$keep_h" -le 0 ] && return 1
  now=$(date +%s)
  mtime=$(stat -f%m "$fpath" 2>/dev/null || stat -c%Y "$fpath" 2>/dev/null || echo 0)
  age_sec=$(( now - mtime ))
  [ "$age_sec" -lt $(( keep_h * 3600 )) ]
}

# Delete on-disk media for titles in ~/mov-sh-state/skip (seen / already watched).
cleanup_seen_from_disk() {
  local keep_h="$KEEP_HOURS" imdb title year rating paths path parent freed_kb=0 total_kb=0
  echo "🧹 Cleaning seen/skipped titles from $DOWNLOAD_DIR (keep-hours=${keep_h})..."
  while IFS= read -r imdb; do
    [[ "$imdb" =~ ^tt[0-9]+$ ]] || continue
    IFS=$'\t' read -r rating year title <<< "$(fetch_imdb_meta "$imdb" | head -1)"
    [ -z "$title" ] && title="$imdb"
    paths=$(find_disk_paths_for_title "$title" "$year")
    [ -z "$paths" ] && continue
    while IFS= read -r path; do
      [ -z "$path" ] || [ ! -e "$path" ] && continue
      media_is_protected_by_keep_hours "$path" "$keep_h" && \
        echo "  ⏳ keep (recent): $(basename "$path")" && continue
      if [ -d "$path" ]; then
        total_kb=$(du -sk "$path" 2>/dev/null | cut -f1)
        rm -rf "$path" && freed_kb=$((freed_kb + total_kb)) && echo "  🗑️  $title → $(basename "$path")"
      else
        total_kb=$(du -sk "$path" 2>/dev/null | cut -f1)
        parent=$(dirname "$path")
        rm -f "$path" "${path}.aria2" 2>/dev/null
        rmdir "$parent" 2>/dev/null || true
        freed_kb=$((freed_kb + total_kb)) && echo "  🗑️  $title → $(basename "$path")"
      fi
    done <<< "$paths"
  done < <(grep -E '^tt[0-9]+$' "$SKIP_FILE" 2>/dev/null | sort -u)
  if [ "$freed_kb" -gt 0 ]; then
    echo "  ✅ Freed ~$(awk -v k="$freed_kb" 'BEGIN{printf "%.1f", k/1024/1024}') GB"
  else
    echo "  ✅ No seen titles to remove (or all protected by --keep-hours)"
  fi
}

find_disk_paths_for_title() {
  local title="$1" year="$2"
  local word lowered match base hits path parent
  local -a words=() paths=() seen_paths=()

  for word in $(echo "$title" | tr '()[]:,' '      '); do
    lowered=$(echo "$word" | tr '[:upper:]' '[:lower:]')
    [[ ${#lowered} -ge 4 ]] || continue
    case "$lowered" in
      cannes|grand|prix|jury|awards|contender|accident|falling|palme|movie|show|live|from|with|oscar|sundance|venice|berlin|breakout|darling|gem|pick|nominee|mention|regard|ensemble|screenwriting|dramatic|documentary|innovator|feature|prize|acting|director|actress|actor|palme|grand|special|award|world|cinema|next|debut|favorite|touch|light|shadow|mothers|baby|plainclothes|twinless|pillion|resurrection|falling|unknown|still|here|boys|sing|fig|sacred|seed|outrun|pain|real|substance|things|poor|emilia|brutalist|anora) continue ;;
    esac
    words+=("$lowered")
  done
  [ ${#words[@]} -eq 0 ] && return 0

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    base=$(basename "$match" | tr '[:upper:]' '[:lower:]')
    hits=0
    for word in "${words[@]}"; do
      echo "$base" | grep -q "$word" && hits=$((hits + 1))
    done
    [ "$hits" -lt 1 ] && continue
    [ ${#words[@]} -ge 2 ] && [ "$hits" -lt 2 ] && continue
    if [ -n "$year" ] && [ "$year" != "0" ]; then
      echo "$base" | grep -q "$year" || continue
    fi
    path="$match"
    [ -f "$path" ] && parent=$(dirname "$path") || parent="$path"
    for p in "$path" "$parent"; do
      [ -e "$p" ] || continue
      [[ " ${seen_paths[*]} " == *" $p "* ]] && continue
      seen_paths+=("$p")
      echo "$p"
    done
  done < <(find "$DOWNLOAD_DIR" -maxdepth 3 \
      \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) -size +50M 2>/dev/null)
}

# ── Cinemeta search / lookup (same API used for manual prestige curation) ─
fetch_imdb_meta() {
  local id="$1" json
  [[ "$id" =~ ^tt[0-9]+$ ]] || return 0
  json=$(curl -sL --max-time 12 "https://v3-cinemeta.strem.io/meta/movie/${id}.json" 2>/dev/null) || return 0
  echo "$json" | jq -r --arg min_year "$MIN_YEAR" --arg max_year "$MAX_YEAR" '
    .meta
    | select(.imdb_id != null and .imdb_id != "")
    | ((.releaseInfo // .year // "") | tostring) as $y
    | select(($y | tonumber? // 0) >= ($min_year | tonumber) or ($min_year | tonumber) == 0)
    | select(($max_year | tonumber) == 9999 or ($y | tonumber? // 9999) <= ($max_year | tonumber))
    | [((.imdbRating // "") | if . == "" then "7.0" else . end), $y, .imdb_id, .name]
    | @tsv
  ' 2>/dev/null || true
}

cinemeta_search() {
  local query="$1" limit="${2:-8}" relax="${3:-false}"
  local enc url json
  [ -z "$query" ] && return 0
  enc=$(uri_encode "$query")
  url="https://v3-cinemeta.strem.io/catalog/movie/top/search=${enc}.json"
  json=$(curl -sL --max-time 12 "$url" 2>/dev/null) || return 0
  echo "$json" | jq -r --arg min_year "$MIN_YEAR" --arg max_year "$MAX_YEAR" --arg min_rating "$MIN_RATING" --arg relax "$relax" --argjson lim "$limit" '
    .metas[:$lim][]
    | ((.imdbRating // "") | if . == "" then (if $relax == "true" then 7.0 else 0 end) else tonumber? // 0 end) as $r
    | ((.releaseInfo // .year // "") | tostring) as $y
    | select(($y | tonumber? // 0) >= ($min_year | tonumber) or ($min_year | tonumber) == 0)
    | select(($max_year | tonumber) == 9999 or ($y | tonumber? // 9999) <= ($max_year | tonumber))
    | select(.imdb_id != null and .imdb_id != "")
    | select(($relax == "true" and ((.imdbRating // "") | length) == 0) or $r >= ($min_rating | tonumber))
    | [((.imdbRating // "") | if . == "" then "7.0" else . end), (.releaseInfo // .year // ""), .imdb_id, .name]
    | @tsv
  ' 2>/dev/null || true
}

# ── Catalog noise filter (concerts, TV, anime blockbusters in Cinemeta top) ─
is_catalog_junk() {
  local title="$1"
  local t
  t=$(echo "$title" | tr '[:upper:]' '[:lower:]')
  [[ "$t" =~ '(live from|live in|in concert|unplugged|stand[ -]?up|comedy special|stadium tour|world tour|eras tour)' ]] && return 0
  [[ "$t" =~ '(bring me the horizon|taylor swift|bts:|metallica:|iron maiden:)' ]] && return 0
  [[ "$t" =~ '(demon slayer|chainsaw man|kimetsu no yaiba|anime|dragon ball|one piece film)' ]] && return 0
  [[ "$t" =~ '(season [0-9]|s[0-9]{2}e[0-9]|complete series|miniseries|tv series)' ]] && return 0
  [[ "$t" =~ '(documentary special|making of|behind the scenes)' ]] && return 0
  return 1
}

is_prestige_imdb() {
  local imdb="$1" csv="${2:-}"
  [ -z "$csv" ] && csv=$(get_prestige_imdb_csv)
  [[ ",${csv}," == *",${imdb},"* ]]
}

filter_catalog_noise() {
  local input="$1" prestige_csv="$2"
  local rating year imdb title
  while IFS=$'\t' read -r rating year imdb title || [ -n "${rating:-}" ]; do
    [ -z "$imdb" ] && continue
    if is_prestige_imdb "$imdb" "$prestige_csv"; then
      printf "%s\t%s\t%s\t%s\n" "$rating" "$year" "$imdb" "$title"
      continue
    fi
    if is_catalog_junk "$title"; then continue; fi
    printf "%s\t%s\t%s\t%s\n" "$rating" "$year" "$imdb" "$title"
  done <<< "$input" || true
  return 0
}

# ── Early init (after helper defs): skip lists, purge, lookup-only mode ───
touch "$SKIP_FILE"
load_skip_lists

if [ "$PURGE" = true ]; then
  echo "🗑️  Purging $DOWNLOAD_DIR..."
  find "$DOWNLOAD_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
fi

if [ "$LOOKUP_MODE" = true ]; then
  echo "🔎 Cinemeta lookup: $LOOKUP_QUERY"
  echo "────────────────────────────────────────────────────────────"
  cinemeta_search "$LOOKUP_QUERY" 12 | while IFS=$'\t' read -r rating year imdb title; do
    [ -z "$imdb" ] && continue
    printf "  %s (%s)  ⭐%s  %s\n" "$title" "$year" "$rating" "$imdb"
  done
  echo "────────────────────────────────────────────────────────────"
  echo "Add to PRESTIGE_LIST or ~/mov-sh-state/prestige as: YEAR<TAB>IMDB<TAB>TITLE"
  exit 0
fi

# ── Fetch Live Trackers (Massive Redundancy) ──────────────────────────────
echo "📡 Fetching live tracker list..."
TRACKER_LIST=""
if TRACKER_RAW=$(curl -sL --max-time 10 "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt" 2>/dev/null); then
  while IFS= read -r tracker; do
    [ -z "$tracker" ] && continue
    TRACKER_LIST+="&tr=$(uri_encode "$tracker")"
    if [ "$(echo "$TRACKER_LIST" | grep -o '&tr=' | wc -l)" -ge 10 ]; then break; fi
  done <<< "$TRACKER_RAW"
fi
if [ -z "$TRACKER_LIST" ]; then
  TRACKER_LIST="&tr=udp://tracker.opentrackr.org:1337/announce&tr=udp://tracker.openbittorrent.com:6969/announce&tr=udp://open.stealth.si:80/announce"
  echo "  ⚠️  Using fallback trackers"
else
  echo "  ✅ Loaded $(echo "$TRACKER_LIST" | grep -o '&tr=' | wc -l) live trackers"
fi

# ── Helper: Build magnet link with dynamic trackers ───────────────────────
build_magnet() {
  local info_hash="$1"
  local title="$2"
  echo "magnet:?xt=urn:btih:${info_hash}&dn=$(uri_encode "$title")${TRACKER_LIST}"
}

# ── Helper: Rank torrents (seeders first, then quality, bluray, seeder count) ─
TORRENT_CANDIDATES=()

torrent_score() {
  local quality="$1" type="$2" seeders="${3:-0}" size_gb="${4:-9999}" title="${5:-}"
  local seeder_penalty=1 q_rank=1 web_rank=1 subs_rank=1 eng_rank=1 yts_rank=1 size_rank=99999 seed_gap
  local t
  t=$(mov_lower "$title")

  [ "$seeders" -ge "$MIN_SEEDERS" ] && seeder_penalty=0
  [ "$quality" = "$TARGET_QUALITY" ] && q_rank=0
  [ "$type" = "web" ] && web_rank=0
  [[ "$type" == *"bluray"* || "$type" == *"blu-ray"* || "$type" == *"remux"* ]] && web_rank=2
  has_eng_subs "$title" && subs_rank=0
  has_english_audio "$title" && eng_rank=0
  [[ "$t" =~ '(yts\.|yts\.mx|yts\.bz|yts\.lt|\[yts|yify|(^|[^a-z])yts([^a-z]|$))' ]] && yts_rank=0
  if [ "$size_gb" != "9999.0" ]; then
    size_rank=$(awk -v s="$size_gb" 'BEGIN{printf "%05d", int(s*100+0.5)}')
  fi
  seed_gap=$(( 10000 - seeders ))
  # seeders (count) → YTS → eng subs → english audio → web over bluray → smaller file → target quality
  echo "${seeder_penalty}:${seed_gap}:${yts_rank}:${subs_rank}:${eng_rank}:${web_rank}:${size_rank}:${q_rank}"
}

# Reject torrents that clearly belong to a different release year.
is_matching_movie_year() {
  local title="$1" expected_year="$2"
  title=${title//\n/ }
  local found
  found=$(echo "$title" | grep -oE '\(20[0-9]{2}\)|[^0-9]20[0-9]{2}[^0-9]' | grep -oE '20[0-9]{2}' | head -1)
  [ -z "$found" ] && return 0
  [ "$found" -eq "$expected_year" ] && return 0
  # Cinemeta year can be ±1 from torrent tags (e.g. Souleymane 2025 vs 2024 WEBRip)
  local diff=$(( found - expected_year ))
  [ "${diff#-}" -le 1 ]
}

add_torrent_candidate() {
  local hash="$1" quality="$2" type="$3" seeders="${4:-0}" size_gb="$5" title="${6:-}"
  [ -z "$hash" ] && return
  local score
  score=$(torrent_score "$quality" "$type" "$seeders" "$size_gb" "$title")
  TORRENT_CANDIDATES+=("${score}|${hash}|${size_gb}|${seeders}")
}

sort_torrent_candidates() {
  if [ ${#TORRENT_CANDIDATES[@]} -eq 0 ]; then
    return 1
  fi
  printf '%s\n' "${TORRENT_CANDIDATES[@]}" | sort -t'|' -k1,1 | while IFS='|' read -r _score hash size_gb seeders || [[ -n ${_score:-}${hash:-} ]]; do
    printf '%s|%s|%s\n' "$hash" "$size_gb" "$seeders"
  done
  return 0
}

# ── Extractors for Stremio streams (handles current Torrentio format) ──────
extract_size_gb() {
  local title="$1"
  local s
  # Prefer 💾 annotated sizes, then any number+unit pattern
  s=$(echo "$title" | grep -oE '💾?[ ]*[0-9.,]+[ ]*[GMK]i?B' | head -1)
  [ -z "$s" ] && s=$(echo "$title" | grep -oE '[0-9.,]+[ ]*[GMK]i?B' | head -1)
  # Normalize: lower, remove spaces/emoji/commas, keep number + unit marker
  s=$(echo "$s" | tr -d '💾 ,' | tr '[:upper:]' '[:lower:]')
  if [[ "$s" =~ ([0-9.]+)gb ]]; then
    echo "$match[1]"
  elif [[ "$s" =~ ([0-9.]+)mb ]]; then
    math "$match[1] / 1024"
  else
    echo "9999.0"
  fi
}

extract_seeders() {
  local title="$1" s="${2:-0}"
  # Torrentio titles often embed stats after a literal "\n" in the JSON string.
  title=${title//\n/ }
  local from_title
  from_title=$(echo "$title" | grep -oE '👤[ ]*[0-9]+|👥[ ]*[0-9]+|[Ss]eeders?:?[ ]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ -n "$from_title" ]; then
    echo "$from_title"; return
  fi
  if [ -n "$s" ] && [ "$s" != "0" ]; then
    echo "$s"; return
  fi
  echo "0"
}

extract_quality_and_type() {
  local title="$1"
  local quality="SD" type="web"
  local t
  t=$(mov_lower "$title")

  echo "$t" | grep -qE '2160p|4k|uhd' && quality="2160p"
  echo "$t" | grep -q '1080p' && quality="1080p"
  echo "$t" | grep -q '720p'  && quality="720p"
  echo "$t" | grep -q '480p'  && quality="480p"

  if echo "$t" | grep -qE 'web-?dl|webdl|webrip|web-?rip|amzn|atvp|dsnp|hulu|it\.web'; then
    type="web"
  elif echo "$t" | grep -qE 'bluray|blu-ray|remux|bdrip|brrip'; then
    type="bluray"
  fi
  echo "$quality//$type"
}

# Explicit English subtitle markers (international films with subs).
has_eng_subs() {
  local title="$1"
  local t
  t=$(mov_lower "$title")
  [[ "$t" =~ '(^|[^a-z])(english[._ -]?subs?|eng[._ -]?subs?|subs?[._ -]?eng|sub[._ -]?eng)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(english[._ -]?subtitles?|eng[._ -]?subtitles?)' ]] && return 0
  [[ "$t" =~ '(eng[._ -]?sub|english[._ -]?sub|engsub|subbed[._ -]?eng|eng[._ -]?subbed)' ]] && return 0
  [[ "$t" =~ '(\.eng\.sub|eng\.sub|subs\.eng|sub\.eng|\.srt\.eng|eng\.srt|forced\.eng|vosteng)' ]] && return 0
  [[ "$t" =~ '(\[eng sub\]|\(eng sub\)|\{eng sub\}|eng subs included)' ]] && return 0
  [[ "$t" =~ artsubs ]] && return 0
  [[ "$t" =~ sub[^a-z0-9]{0,6}(ita[^a-z0-9]{0,6})?eng ]] && return 0
  return 1
}

# English audio markers in torrent title (do NOT trust generic web-dl/webrip — RU scene uses those tags too).
has_english_audio() {
  local title="$1"
  local t
  t=$(mov_lower "$title")
  is_russian_scene "$title" && return 1
  [[ "$t" =~ '(^|[^a-z])(english|\.eng\.|\.eng$|-eng-|eng\.ac3|en\.ac3|en\.ddp|ddp.*eng|aac.*eng|dual\.audio.*eng|eng.*dual)' ]] && return 0
  [[ "$t" =~ '(yts\.|yts\.mx|yts\.bz|yts\.lt|\[yts|yify|(^|[^a-z])yts([^a-z]|$))' ]] && return 0
  # Trusted WEB groups — English by default when not foreign-tagged
  [[ "$t" =~ '(^|[-.])(psa|aoc|ntb|megusta|playweb|flux|blutopia|nikt0|ethel|bone|kingdom|asiimov)([-. ]|$)' ]] && \
    [[ "$t" =~ 'web-?dl|web-?rip|webdl|webrip' ]] && return 0
  # Trusted BluRay/x265 groups — English-original when not foreign-tagged (NZ/NL cult encodes)
  [[ "$t" =~ '(^|[^a-z])(tigole|qxr|rmteam|hifi|epsi|decibe)([^a-z]|$)' ]] && \
    [[ "$t" =~ 'blu-?ray|bluray|bdrip|x265|hevc' ]] && return 0
  # AMZN/ATVP only when not a foreign dub release
  [[ "$t" =~ '(amzn|atvp|dsnp|hulu|nf\.|netflix)' ]] && \
    ! [[ "$t" =~ '(^|[^a-z])(dub|dubbed|\.d\.|\.dub\.|multi\.|truefrench|vfq|vff|mvo|\.rus\.|d\.rus)' ]] && return 0
  return 1
}

# Russian/CIS release groups and dub markers — almost never original English audio.
is_russian_scene() {
  local title="$1"
  local t
  t=$(mov_lower "$title")
  echo "$title" | grep -qE '[а-яА-ЯёЁ]' && return 0
  [[ "$t" =~ '(^|[^a-z_-])(exkinoray|shkiper|elektri4ka|elektricka|selezen|selezen\.|il68k|new-team|nitrid|kinorip|wolfmax4k|megapeer|rutor|rutracker|mvo|lostfilm|hdrezka|baibako|newstudio|kuraj-bambej|anilibria)([^a-z_-]|$)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(dub|dubbed|\.dub\.|\.dub$|-dub-|\.d\.web|d\.web-dl|d\.web-dlrip|\.d\.rus|d\.rus|avo\.web)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(\.rus\.|\.rus$|-rus-|rus\.ac3|ukr\.|\.ukr\.|dub\.ukr)' ]] && return 0
  return 1
}

# Reject dubbed, multi-language, and foreign-community releases (English-only mode).
is_english_release() {
  local title="$1"
  local t
  title=${title//\n/ }
  t=$(echo "$title" | tr '[:upper:]' '[:lower:]')

  echo "$title" | grep -qE '[а-яА-ЯёЁ]' && return 1
  echo "$title" | grep -qE '🇷🇺|🇫🇷|🇪🇸|🇵🇱|🇮🇹|🇩🇪|🇧🇷|🇳🇴|🇮🇳|🇰🇷|🇯🇵|🇲🇽' && return 1

  [[ "$t" =~ '(^|[^a-z])(multi|multilang|multilingual|multi-audio|dual-audio|dual\.audio)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(dub|dubbed|\.dub\.|\.dub$|-dub-|\.dub )' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(truefrench|vfq|vff|vfi|vf2|vostfr|french)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(lektor|napisy|polski|sub\.pl|\[pl\]|pl\.ac3)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(hindi|tamil|telugu|hin-|tam-|tel-|hin2)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(castellano|spanish|latino|esp\.|\.esp|\[esp\])([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(italian|\.ita\.|\.ita$|-ita-|ita\.ac3)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(german|deutsch|\.ger\.|ger\.ac3)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(russian|\.rus\.|rutor|rutracker|megapeer|mvo)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z_-])(exkinoray|shkiper|elektri4ka|elektricka|selezen|il68k|new-team|nitrid|wolfmax4k|nicollubin|kinorip)([^a-z_-]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(\.d\.web|d\.web-dl|d\.web-dlrip|\.d\.rus|d\.rus|avo\.web)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(czech|cz\.|\.cz\.|titulky|posedlost|hungarian|norwegian|swedish|danish)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ '(^|[^a-z])(dual\.|\.dual\.|-dual-|dual\.ddp)([^a-z]|$)' ]] && return 1
  [[ "$t" =~ 'multi\.(webrip|web-dl|webdl|truefrench|webrip)' ]] && return 1

  return 0
}

# Foreign-only dubs/hardsubs with no English subs or audio.
is_foreign_only_bad() {
  local title="$1"
  local t
  t=$(mov_lower "$title")

  is_russian_scene "$title" && return 0
  has_eng_subs "$title" && return 1
  has_english_audio "$title" && return 1

  [[ "$t" =~ '(^|[^a-z])(dub|dubbed|\.dub\.|lektor|truefrench|vfq|vff|vfi|vf2|vostfr)([^a-z]|$)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(napisy|polski|sub\.pl|\[pl\]|pl\.ac3|titulky)([^a-z]|$)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(mvo|megapeer|rutor|rutracker)([^a-z]|$)' ]] && return 0
  [[ "$t" =~ '(^|[^a-z])(castellano|latino|hindi|tamil|telugu)([^a-z]|$)' ]] && return 0
  return 1
}

# Language filter: international OK if English subs or English audio present.
passes_language_filter() {
  local title="$1"
  local t
  [ "$ALLOW_CAM" = true ] && is_cam_release "$title" && return 0
  if [ "$ENGLISH_ONLY" = true ]; then
    is_english_release "$title"
    return
  fi
  [ "$REQUIRE_ENG_SUBS" != true ] && return 0
  if is_foreign_only_bad "$title"; then return 1; fi
  has_eng_subs "$title" && return 0
  has_english_audio "$title" && return 0
  return 1
}

# Theatrical recording markers (CAM/HDTS/TS) — blocked unless --allow-cam.
is_cam_release() {
  local t
  t=$(mov_lower "$1")
  t=${t//._ /-}
  [[ "$t" =~ '(^|[-.])(cam|hdcam|hd-cam|hdts|hd-ts)(rip)?([-.\[]|$)' ]] && return 0
  [[ "$t" =~ 'hdcam|hd-cam|camrip|cam-rip' ]] && return 0
  [[ "$t" =~ '(^|[-.])(ts|hdts|te?lesync)([-.\[]|$)' ]] && return 0
  return 1
}

# ── Helper: Reject CAMs, telesyncs, screeners and other garbage early releases ─
# Uses strict token matching to avoid false positives on "DTS", "YTS", "SPARKS" etc.
is_good_release() {
  local t
  t=$(mov_lower "$1")
  t=${t//._ /-}
  if [ "$ALLOW_CAM" != true ]; then
    is_cam_release "$1" && return 1
  fi
  [[ "$t" =~ '(^|[-])(tc|telecine)([-]|$)' ]] && return 1
  [[ "$t" =~ '(^|[-])(screener|dvdscr|r5|workprint)([-]|$)' ]] && return 1
  [[ "$t" =~ '(^|[-])(line-audio|cam-audio)([-]|$)' ]] && return 1
  # Scene re-encodes of WEB-DL — often corrupt/truncated (e.g. Licdom/ViTO "WebDl Rip")
  [[ "$t" =~ 'licdom|vito|webdl-rip|webdlrip|web-dl-rip' ]] && return 1
  return 0
}

# ── Search Stremio Addons (Multi-source loop) ────────────────────────────
search_stremio_magnet() {
  local imdb_id="$1"
  local expected_year="${2:-}"
  TORRENT_CANDIDATES=()

  for addon in "${STREMIO_ADDONS[@]}"; do
    local url="https://${addon}/stream/movie/${imdb_id}.json"
    local json
    if command -v flock >/dev/null 2>&1; then
      { flock -w 180 9; json=$(curl -sL --max-time 8 "$url" 2>/dev/null); } 9>>"$STREMIO_LOCK" || continue
    else
      json=$(curl -sL --max-time 8 "$url" 2>/dev/null) || continue
    fi

    # Parse streams: infoHash, title, seeders (seeders often missing or 0)
    {
      while IFS=$'\t' read -r hash title seeders || [[ -n ${hash:-} ]]; do
        [ -z "$hash" ] && continue
        is_good_release "$title" || continue   # skip CAM, TS, screener, etc.
        ! passes_language_filter "$title" && continue
        [ -n "$expected_year" ] && ! is_matching_movie_year "$title" "$expected_year" && continue

        local size_gb q_and_t quality type
        size_gb=$(extract_size_gb "$title")
        seeders=$(extract_seeders "$title" "$seeders")
        q_and_t=$(extract_quality_and_type "$title")
        quality="${q_and_t%%//*}"
        type="${q_and_t##*//}"

        if [ "$size_gb" != "9999.0" ] && float_gt "$MIN_SIZE_GB" "$size_gb"; then
          continue
        fi
        if float_le "$size_gb" "$MAX_SIZE_GB" || [ "$size_gb" = "9999.0" ]; then
          add_torrent_candidate "$hash" "$quality" "$type" "$seeders" "$size_gb" "$title"
        fi
      done < <(print -r -- "$json" | jq -r '.streams[]? | [.infoHash // "", (.title // "" | gsub("[\t\n\r]"; " ")), ((.seeders // 0) | if type == "number" then . else 0 end)] | @tsv' 2>/dev/null)
    } >/dev/null
  done

  sort_torrent_candidates
}


# ── Search YTS (fallback) ─────────────────────────────────────────────────
search_yts_magnet() {
  local imdb_id="$1"
  local _expected_year="${2:-}"
  TORRENT_CANDIDATES=()

  for domain in "${YTS_DOMAINS[@]}"; do
    local url="https://${domain}/api/v2/list_movies.json?query_term=${imdb_id}"
    local json
    if command -v flock >/dev/null 2>&1; then
      { flock -w 180 9; json=$(curl -sL --max-time 8 "$url" 2>/dev/null); } 9>>"$STREMIO_LOCK" || continue
    else
      json=$(curl -sL --max-time 8 "$url" 2>/dev/null) || continue
    fi
    # Some mirrors return notice but still have .data
    if ! echo "$json" | jq -e '.data.movies' >/dev/null 2>&1; then continue; fi

    while IFS=$'\t' read -r hash quality type seeds size_str || [[ -n ${hash:-} ]]; do
      [ -z "$hash" ] && continue

      # YTS titles are usually clean, but double-check the movie title + torrent info if available
      # (the size_str and quality are separate; we still want to be safe)
      # YTS releases are English-only by default — tag as YTS so language filter accepts them
      local yts_title_check="YTS ${quality} ${type} ${size_str}"
      is_good_release "$yts_title_check" || continue
      ! passes_language_filter "$yts_title_check" && continue

      local size_gb
      size_gb=$(size_to_gb "$size_str")

      if [ "$size_gb" != "9999.0" ] && float_gt "$MIN_SIZE_GB" "$size_gb"; then
        continue
      fi
      if float_le "$size_gb" "$MAX_SIZE_GB" || [ "$size_gb" = "9999.0" ]; then
        add_torrent_candidate "$hash" "$quality" "$type" "$seeds" "$size_gb" "$yts_title_check"
      fi
    done < <(echo "$json" | jq -r '.data.movies[]?.torrents[]? | [.hash, .quality, .type, .seeds, .size] | @tsv' 2>/dev/null)
    break
  done

  sort_torrent_candidates
}

# Title word hits against a lowercase path/filename blob (shared by local + staging match).
_title_word_hits() {
  local base="$1" year="$2"
  local word lowered hits=0
  local -a words=()

  shift 2
  words=("$@")
  [ ${#words[@]} -eq 0 ] && return 1

  local y tol
  for y in "$year" $(( year - 1 )) $(( year + 1 )); do
    [[ "$y" =~ ^[0-9]{4}$ ]] || continue
    echo "$base" | grep -q "$y" || continue
    hits=0
    for word in "${words[@]}"; do
      echo "$base" | grep -q "$word" && hits=$((hits + 1))
    done
    [ "$hits" -ge 2 ] && return 0
    [ ${#words[@]} -eq 1 ] && [ ${#words[0]} -ge 7 ] && [ "$hits" -ge 1 ] && return 0
  done

  hits=0
  for word in "${words[@]}"; do
    echo "$base" | grep -q "$word" && hits=$((hits + 1))
  done
  [ "$hits" -ge 2 ] && return 0
  [ ${#words[@]} -eq 1 ] && [ ${#words[0]} -ge 7 ] && [ "$hits" -ge 1 ] && return 0
  return 1
}

title_match_words() {
  local title="$1"
  local word lowered
  local -a words=()

  for word in $(echo "$title" | tr '()[]:,' '      '); do
    lowered=$(echo "$word" | tr '[:upper:]' '[:lower:]')
    [[ ${#lowered} -ge 4 ]] || continue
    case "$lowered" in
      cannes|grand|prix|jury|awards|contender|accident|falling|ryan|coogler|palme|movie|show|live|from|with|horizon|value|battle|another|sheep|detectives|years|later|bone|temple|guardians|falling|bright|creatures) continue ;;
    esac
    words+=("$lowered")
  done
  print -l -- "${words[@]}"
}

# Torrent folder (or file) directly under staging or library root.
media_container_item() {
  local media_path="$1" item parent
  item=$(dirname "$media_path")
  while true; do
    parent=$(dirname "$item")
    [ "$parent" = "$STAGING_DIR" ] && { echo "$item"; return 0 }
    [ "$parent" = "$DOWNLOAD_DIR" ] && { echo "$item"; return 0 }
    [ "$parent" = "$item" ] || [ "$parent" = "/" ] && { echo "$media_path"; return 0 }
    item="$parent"
  done
}

media_path_matches_title() {
  local fpath="$1" title="$2" year="$3"
  local base item words

  words=("${(@f)$(title_match_words "$title")}")
  [ ${#words[@]} -eq 0 ] && return 1
  item=$(media_container_item "$fpath")
  base="$(basename "$fpath" | tr '[:upper:]' '[:lower:]') $(basename "$item" | tr '[:upper:]' '[:lower:]')"
  _title_word_hits "$base" "$year" "${words[@]}"
}

# ── Helper: detect movies already present in the download dir ─────────────
movie_exists_locally() {
  local title="$1" year="$2"
  local match base

  while IFS= read -r match; do
    [ -z "$match" ] && continue
    [ -f "${match}.aria2" ] && continue
    media_path_matches_title "$match" "$title" "$year" || continue
    base=$(basename "$match" | tr '[:upper:]' '[:lower:]')
    [ "$ENGLISH_ONLY" = true ] && ! passes_language_filter "$base" && continue
    verify_media_playable "$match" && return 0
  done < <(find "$DOWNLOAD_DIR" -maxdepth 4 \
      \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) -size +400M 2>/dev/null)

  return 1
}

# Reject aria2 pre-allocated shells (all-zero header) and tiny junk files.
is_valid_media_file() {
  local fpath="$1"
  [ -f "$fpath" ] || return 1
  local sz
  sz=$(stat -f%z "$fpath" 2>/dev/null || stat -c%s "$fpath" 2>/dev/null || echo 0)
  [ "$sz" -gt 52428800 ] || return 1   # >50 MB
  local head off pct zero=0
  head=$(dd if="$fpath" bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ -n "$head" ] && [ "$head" != "00000000000000000000000000000000" ] || return 1
  # Reject aria2 sparse partials (file-allocation=none leaves zero-filled holes)
  for pct in 25 50 75; do
    off=$(( sz * pct / 100 ))
    head=$(dd if="$fpath" bs=16 count=1 skip=$((off / 16)) 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [ "$head" = "00000000000000000000000000000000" ] && zero=$((zero + 1))
  done
  [ "$zero" -eq 0 ]
}

# ffprobe/ffmpeg decode check — catches moov-missing MP4s and video-only rips.
verify_media_playable() {
  local fpath="$1"
  is_valid_media_file "$fpath" || return 1
  if ! command -v ffprobe >/dev/null 2>&1; then
    return 0
  fi
  local aud_n
  aud_n=$(ffprobe -v error -select_streams a -show_entries stream=codec_type \
    -of csv=p=0 "$fpath" 2>/dev/null | grep -c '^audio$' || true)
  [ "${aud_n:-0}" -gt 0 ] || return 1
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -v error -i "$fpath" -t 1 -f null - 2>/dev/null || return 1
  fi
  return 0
}

# Walk up from a media file to the top-level item aria2 created under $STAGING_DIR.
staging_top_level_item() {
  media_container_item "$1"
}

# Move a verified staging folder/file into the library directory.
promote_staged_item() {
  local item="$1" base dest
  [ -e "$item" ] || return 1
  base=$(basename "$item")
  dest="$DOWNLOAD_DIR/$base"
  if [ -e "$dest" ]; then
    if find "$dest" -maxdepth 3 \( -iname "*.mkv" -o -iname "*.mp4" \) -size +50M 2>/dev/null | head -1 | grep -q .; then
      rm -rf "$item" 2>/dev/null
      return 0
    fi
    rm -rf "$dest" 2>/dev/null
  fi
  mv "$item" "$DOWNLOAD_DIR/" 2>/dev/null || return 1
  echo "  📦 Promoted to library: $base"
  return 0
}

promote_verified_staging() {
  local title="$1" year="$2"
  local match item
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    [ -f "${match}.aria2" ] && continue
    media_path_matches_title "$match" "$title" "$year" || continue
    verify_media_playable "$match" || continue
    item=$(staging_top_level_item "$match")
    promote_staged_item "$item" && return 0
  done < <(find "$STAGING_DIR" -maxdepth 4 \
      \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) -mmin -240 2>/dev/null)
  return 1
}

cleanup_recent_staging_failures() {
  local path item
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ -f "${path}.aria2" ] && continue
    verify_media_playable "$path" && continue
    item=$(staging_top_level_item "$path")
    rm -rf "$item" "${item}.aria2" 2>/dev/null
  done < <(find "$STAGING_DIR" -maxdepth 4 \
      \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) -mmin -240 2>/dev/null)
  find "$STAGING_DIR" -maxdepth 1 -name '*.aria2' -mmin +5 -delete 2>/dev/null || true
}

verify_download_for_title() {
  local title="$1" year="$2"
  promote_verified_staging "$title" "$year" && return 0
  movie_exists_locally "$title" "$year"
}

port_is_free() {
  local port=$1
  ! lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

pick_free_port() {
  local base=$1 attempt port
  for attempt in {0..39}; do
    port=$(( base + attempt * 17 + RANDOM % 13 ))
    (( port >= 1024 && port <= 65500 )) || continue
    port_is_free "$port" && { print -r -- "$port"; return 0 }
  done
  print -r -- $(( 1024 + RANDOM % 64000 ))
}

find_resumable_hash_for_title() {
  local title="$1" year="$2"
  local path aria2 hash
  while IFS= read -r path; do
    [[ -f "${path}.aria2" ]] || continue
    media_path_matches_title "$path" "$title" "$year" || continue
    hash=$(grep -aoE '[0-9a-f]{40}' "${path}.aria2" 2>/dev/null | head -1)
    hash=${hash:l}
    [[ $hash =~ ^[0-9a-f]{40}$ ]] && { print -r -- "$hash"; return 0 }
  done < <(find "$STAGING_DIR" -maxdepth 4 \
      \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" \) 2>/dev/null)
  while IFS= read -r aria2; do
    path="${aria2%.aria2}"
    [[ -f "$path" ]] || continue
    media_path_matches_title "$path" "$title" "$year" || continue
    hash=$(grep -aoE '[0-9a-f]{40}' "$aria2" 2>/dev/null | head -1)
    hash=${hash:l}
    [[ $hash =~ ^[0-9a-f]{40}$ ]] && { print -r -- "$hash"; return 0 }
  done < <(find "$STAGING_DIR" -maxdepth 1 -name '*.aria2' 2>/dev/null)
  return 1
}

prioritize_resume_hash() {
  local candidates="$1" resume_hash="$2"
  local line hash rest
  resume_hash=${resume_hash:l}
  [[ $resume_hash =~ ^[0-9a-f]{40}$ ]] || { print -r -- "$candidates"; return }
  local -a preferred=() other=()
  while IFS='|' read -r hash rest; do
    [[ -z "$hash" ]] && continue
    hash=${hash:l}
    if [[ "$hash" == "$resume_hash" ]]; then
      preferred+=("${hash}|${rest}")
    else
      other+=("${hash}|${rest}")
    fi
  done <<< "$candidates"
  if [ ${#preferred[@]} -gt 0 ]; then
    print -l -- "${preferred[@]}" "${other[@]}"
  else
    print -r -- "${resume_hash}|9999.0|1"
    print -r -- "$candidates"
  fi
}

# ── Helper: aria2c with hard timeout so dead magnets cannot stall overnight ─
download_torrent() {
  local magnet="$1"
  local slot="${2:-0}"
  local imdb="${3:-}"
  local attempt_timeout="${4:-$DOWNLOAD_TIMEOUT_SEC}"
  local timeout_bin="" err_file bt_port dht_port try rc port_base
  err_file="${TMPDIR:-/tmp}/mov-sh-aria2-$$-${slot}.err"

  port_base=$(( 6881 + slot * 137 + RANDOM % 200 ))
  if [[ "$imdb" =~ tt([0-9]+)$ ]]; then
    port_base=$(( 6881 + (10#$match[1] % 2000) + slot * 53 ))
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin="gtimeout"
  fi

  for try in 1 2 3 4; do
    bt_port=$(pick_free_port "$port_base")
    dht_port=$(pick_free_port $(( bt_port + 43000 )))

    local -a aria_cmd=(aria2c
      --seed-time=0
      --file-allocation="$FILE_ALLOCATION"
      --allow-overwrite=true
      --console-log-level=notice
      --summary-interval=30
      --max-tries=3
      --continue=true
      --bt-stop-timeout=0
      --bt-tracker-timeout=20
      --connect-timeout=10
      --timeout=30
      --enable-dht=true
      --bt-enable-lpd=true
      --listen-port="$bt_port"
      --dht-listen-port="$dht_port"
      --dir="$STAGING_DIR"
      "$magnet"
    )

    : >"$err_file"
    if [ -n "$timeout_bin" ]; then
      "$timeout_bin" "$attempt_timeout" "${aria_cmd[@]}" 2>"$err_file"
    else
      "${aria_cmd[@]}" 2>"$err_file"
    fi
    rc=$?

    if grep -qiE 'address already in use|failed to bind|bind.*error' "$err_file" 2>/dev/null; then
      continue
    fi
    rm -f "$err_file"
    return $rc
  done
  rm -f "$err_file"
  return 1
}

seeders_ge_min() {
  local raw=$1 n
  n=${raw//[!0-9]/}
  [[ -n $n && $n -ge $MIN_SEEDERS ]]
}

has_viable_torrent() {
  local imdb_id=$1 movie_year=$2
  local hash seeders stremio_candidates yts_candidates candidates
  stremio_candidates=$(search_stremio_magnet "$imdb_id" "$movie_year" 2>/dev/null) || true
  yts_candidates=$(search_yts_magnet "$imdb_id" "$movie_year" 2>/dev/null) || true
  candidates=$(merge_torrent_candidates "$stremio_candidates" "$yts_candidates")
  [[ -n $candidates ]] || return 1
  while IFS='|' read -r hash _size seeders || [[ -n ${hash:-} ]]; do
    [[ $hash =~ '^[0-9a-f]{40}$' ]] || continue
    seeders_ge_min "$seeders" && return 0
  done <<< "$candidates"
  return 1
}

# ── Per-movie processor (used by interactive selection) ───────────────────
process_one_movie() {
  local imdb="$1"
  local title="$2"
  local year="$3"
  local rating="${4:-?}"
  local slot="${5:-0}"

  log_line() { echo "$*"; }

  log_line "----------------------------------------"
  log_line "🎬 $title ($year) ⭐$rating"

  local avail_now
  avail_now=$(get_available_gb "$DOWNLOAD_DIR")
  if float_gt "$MIN_FREE_GB" "$avail_now"; then
    log_line "  ⚠️  Only ${avail_now} GB free (min ${MIN_FREE_GB}) — stopping downloads"
    return 2
  fi

  if is_skipped_imdb "$imdb"; then
    log_line "  👁️  Marked seen ($imdb) — won't re-fetch"
    return 0
  fi

  if movie_exists_locally "$title" "$year"; then
    log_line "  ✅ Already on disk — skipping download"
    record_job_success "$imdb"
    return 0
  fi

  local candidates="" stremio_candidates="" yts_candidates=""
  stremio_candidates=$(search_stremio_magnet "$imdb" "$year")
  yts_candidates=$(search_yts_magnet "$imdb" "$year")
  candidates=$(merge_torrent_candidates "$stremio_candidates" "$yts_candidates")
  if [ -z "$candidates" ]; then
    log_line "  ❌ No suitable torrent found, skipping."
    return 1
  fi

  local resume_hash=""
  if [ "$DRY_RUN" = false ]; then
    resume_hash=$(find_resumable_hash_for_title "$title" "$year" 2>/dev/null || true)
    if [ -n "$resume_hash" ]; then
      log_line "  ♻️  Resuming partial (${resume_hash:0:8}…) — same torrent before alternates"
      candidates=$(prioritize_resume_hash "$candidates" "$resume_hash")
    fi
  fi

  local avail tried=0
  avail=$(get_available_gb "$DOWNLOAD_DIR")

  while IFS='|' read -r best_hash torrent_size_gb seeders; do
    [ -z "$best_hash" ] && continue
    tried=$((tried + 1))
    torrent_size_gb=${torrent_size_gb:-0}
    seeders=${seeders:-0}

    if [ "$seeders" -lt "$MIN_SEEDERS" ]; then
      [ "$tried" -eq 1 ] && log_line "  ⚠️  Best match has 0 seeders — trying alternates..."
      continue
    fi

    local display_size="${torrent_size_gb} GB"
    [ "$torrent_size_gb" = "9999.0" ] && display_size="size unknown"

    if [ "$torrent_size_gb" != "9999.0" ] && float_gt "$torrent_size_gb" "$avail"; then
      log_line "  ⚠️  Only ${avail} GB free — skipping ${display_size} release"
      continue
    fi

    local magnet source_hint=""
    [[ "$best_hash" =~ ^[0-9a-fA-F]{40}$ ]] && best_hash=$(echo "$best_hash" | tr '[:upper:]' '[:lower:]')
    magnet=$(build_magnet "$best_hash" "$title ($year)")
    { [ -n "$stremio_candidates" ] && echo "$stremio_candidates" | grep -qi "$best_hash"; } && source_hint="Stremio"
    [ -z "$source_hint" ] && { [ -n "$yts_candidates" ] && echo "$yts_candidates" | grep -qi "$best_hash"; } && source_hint="YTS"
    [ -z "$source_hint" ] && source_hint="Stremio/YTS"
    log_line "  🔗 Found on $source_hint (${display_size}, 👤${seeders})"
    if [ "$DRY_RUN" = true ]; then
      log_line "  [dry-run] Would download: $magnet"
      log_line "  ✅ [dry-run] Would have downloaded: $title"
      return 0
    fi

    local attempt_timeout="$DOWNLOAD_TIMEOUT_SEC"
    log_line "  ⬇️  Downloading (timeout: ${attempt_timeout}s, slot ${slot}, attempt ${tried})..."
    if download_torrent "$magnet" "$slot" "$imdb" "$attempt_timeout"; then
      if verify_download_for_title "$title" "$year"; then
        record_job_success "$imdb"
        log_line "  ✅ Done: $title"
        return 0
      fi
      log_line "  ⚠️  Download finished but unplayable or missing audio — trying next torrent..."
      cleanup_recent_staging_failures
    else
      log_line "  ⚠️  Attempt ${tried} stalled or failed — trying next torrent..."
    fi
    cleanup_recent_staging_failures
  done <<< "$candidates"

  log_line "  ❌ Failed: $title (no seeded torrent completed in time)"
  return 1
}

run_movie_worker() {
  local imdb="$1" title="$2" year="$3" rating="$4" slot="$5"
  local log_file="$JOB_STATE_DIR/worker-${slot}-${imdb}.log"
  local rc_file="$JOB_STATE_DIR/worker-${slot}-${imdb}.rc"
  local wrc=0
  {
    process_one_movie "$imdb" "$title" "$year" "$rating" "$slot"
  } >"$log_file" 2>&1 || wrc=$?
  echo "$wrc" >"$rc_file"
  echo "----- ${title} (${year}) -----"
  cat "$log_file"
}

# ── Movie catalog fetchers ─────────────────────────────────────────────────
fetch_cinemeta() {
  local catalog="$1" page="${2:-0}" relax="${3:-false}"
  local url="https://v3-cinemeta.strem.io/catalog/movie/${catalog}"
  [ "$page" -gt 0 ] && url+="/skip=$((page * 100))"
  url+=".json"
  local json
  json=$(curl -sL --max-time 20 "$url" 2>/dev/null) || return 0
  echo "$json" | jq -r --arg min_rating "$MIN_RATING" --arg min_year "$MIN_YEAR" --arg max_year "$MAX_YEAR" --arg relax "$relax" '
    .metas[]
    | ((.imdbRating // "") | if . == "" then (if $relax == "true" then 7.0 else 0 end) else tonumber? // 0 end) as $r
    | ((.releaseInfo // .year // "0") | tonumber? // 0) as $y
    | select(($relax == "true" and ((.imdbRating // "") | length) == 0) or $r >= ($min_rating | tonumber))
    | select($y >= ($min_year | tonumber))
    | select($y <= ($max_year | tonumber))
    | [((.imdbRating // "") | if . == "" then "7.0" else . end), (.releaseInfo // .year // ""), .imdb_id, .name]
    | @tsv
  ' 2>/dev/null || true
}

# Live Cinemeta discovery — imdbTop/trending/year catalogs + search (new theatrical w/ no IMDb score yet)
fetch_discover() {
  local catalog page max_pages q
  local -a catalogs=(imdbTop top "year=2026" "year=2025")
  for catalog in $catalogs; do
    max_pages=2
    [[ $catalog == year=* ]] && max_pages=1
    for (( page=0; page<max_pages; page++ )); do
      fetch_cinemeta "$catalog" "$page" true
    done
  done
  for q in "${LIBRARY_DISCOVER_SEARCHES[@]}"; do
    cinemeta_search "$q" 10 true
  done
}

fetch_yts() {
  local page="${1:-1}"
  local year_param=""
  [ "$MIN_YEAR" = "$MAX_YEAR" ] && [ "$MIN_YEAR" != "0" ] && year_param="&year=${MIN_YEAR}"
  local json
  for domain in "${YTS_DOMAINS[@]}"; do
    local url="https://${domain}/api/v2/list_movies.json?sort_by=rating&minimum_rating=${MIN_RATING}&limit=50&page=${page}${year_param}"
    json=$(curl -sL --max-time 15 "$url" 2>/dev/null) || continue
    echo "$json" | jq -e '.data.movies' >/dev/null 2>&1 || continue
    echo "$json" | jq -r --arg min_year "$MIN_YEAR" --arg max_year "$MAX_YEAR" '
      .data.movies[]?
      | select((.year // 0) >= ($min_year | tonumber))
      | select(($max_year | tonumber) == 9999 or (.year // 0) <= ($max_year | tonumber))
      | select(.imdb_code != null and .imdb_code != "")
      | [(.rating | tostring), (.year | tostring), .imdb_code, .title]
      | @tsv
    ' 2>/dev/null || true
    return 0
  done
}

# Match on-disk files against prestige rows → skip IDs (owned library scan)
scan_owned_into_skip() {
  local year imdb title found=0
  while IFS=$'\t' read -r year imdb title || [ -n "$year" ]; do
    year=$(echo "$year" | tr -d ' \t\r')
    imdb=$(echo "$imdb" | tr -d ' \t\r')
    title=$(echo "$title" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ "$year" =~ ^[0-9]{4}$ ]] || continue
    [[ "$imdb" =~ ^tt[0-9]+$ ]] || continue
    if movie_exists_locally "$title" "$year"; then
      append_history_imdb "$imdb"
      append_skip_imdb "$imdb"
      echo "  📁 owned: $title ($year) → seen $imdb"
      found=$((found + 1))
    fi
  done <<< "$(printf '%s\n%s' "$PRESTIGE_LIST" "$EXTRA_PRESTIGE_ROWS")" || true
  [ -f "$PRESTIGE_USER_FILE" ] && while IFS=$'\t' read -r year imdb title || [ -n "$year" ]; do
    year=$(echo "$year" | tr -d ' \t\r')
    imdb=$(echo "$imdb" | tr -d ' \t\r')
    title=$(echo "$title" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ "$year" =~ ^[0-9]{4}$ ]] || continue
    [[ "$imdb" =~ ^tt[0-9]+$ ]] || continue
    if movie_exists_locally "$title" "$year"; then
      append_history_imdb "$imdb"
      append_skip_imdb "$imdb"
      echo "  📁 owned: $title ($year) → seen $imdb"
      found=$((found + 1))
    fi
  done < "$PRESTIGE_USER_FILE" || true
  return 0
}

# ── Prestige (real 2025+ film festival / awards) fetcher ───────────────────
# Uses the curated list of actual Cannes winners, Oscar nominees etc.
# This is the key fix for "automatically and autonomously fetches real proper critically acclaimed or film festival nominees etc."
fetch_prestige() {
  local miny="${1:-$MIN_YEAR}" maxy="${2:-$MAX_YEAR}"
  # Parse the PRESTIGE_LIST (tab separated). Output rating year imdb title
  # prestige bypasses MIN_RATING filter — festival nomination = acclaim
  while IFS=$'\t' read -r year imdb title || [ -n "$year" ]; do
    year=$(echo "$year" | tr -d ' \t\r')
    imdb=$(echo "$imdb" | tr -d ' \t\r')
    title=$(echo "$title" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [ -z "$year" ] && continue
    [[ "$year" =~ ^[0-9]{4}$ ]] || continue
    [ -z "$imdb" ] && continue
    if is_skipped_imdb "$imdb"; then continue; fi
    [ "$year" -lt "$miny" ] && continue
    [ "$maxy" != "9999" ] && [ "$year" -gt "$maxy" ] && continue
    local rating="8.0"
    printf "%s\t%s\t%s\t%s\n" "$rating" "$year" "$imdb" "$title"
  done <<< "$(printf '%s\n%s' "$PRESTIGE_LIST" "$EXTRA_PRESTIGE_ROWS")" || true
  [ -f "$PRESTIGE_USER_FILE" ] && while IFS=$'\t' read -r year imdb title || [ -n "$year" ]; do
    year=$(echo "$year" | tr -d ' \t\r')
    imdb=$(echo "$imdb" | tr -d ' \t\r')
    title=$(echo "$title" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [ -z "$year" ] && continue
    [[ "$year" =~ ^[0-9]{4}$ ]] || continue
    [ -z "$imdb" ] && continue
    if is_skipped_imdb "$imdb"; then continue; fi
    [ "$year" -lt "$miny" ] && continue
    [ "$maxy" != "9999" ] && [ "$year" -gt "$maxy" ] && continue
    printf "%s\t%s\t%s\t%s\n" "8.0" "$year" "$imdb" "$title"
  done < "$PRESTIGE_USER_FILE" || true
}

# ── Main Execution ────────────────────────────────────────────────────────
echo "🎬 mov.sh – $(date '+%Y-%m-%d %H:%M')"
AVAILABLE_GB=$(awk -v g="$(get_available_gb "$DOWNLOAD_DIR")" 'BEGIN{printf "%.1f", g}')
echo "💾 ${AVAILABLE_GB} GB free in $DOWNLOAD_DIR"
echo "📥 Staging incomplete pulls in $STAGING_DIR (promoted after playable+audio verify)"
if [ "$ENGLISH_ONLY" = true ]; then
  echo "🗣️  English audio only (no international)"
elif [ "$REQUIRE_ENG_SUBS" = true ]; then
  echo "🌍 International OK — requires English audio/subs; blocks RU/CIS dub tags (ExKinoRay, seleZen, DUB)"
else
  echo "🗣️  Any language accepted (no subtitle requirement)"
fi
echo "📦 Max torrent size: ${MAX_SIZE_GB} GB (prefers compact WEBRips)"
[ "$ALLOW_CAM" = true ] && echo "📹 CAM/HDTS/TS allowed (--allow-cam) — theatrical recordings, not proper encodes"
[ "$LIBRARY_MODE" = true ] && echo "📚 Library mode — prestige list + live Cinemeta discovery (imdbTop/trending/2026)"
[ "$PRUNE_INVALID" = true ] && [ "$DRY_RUN" = false ] && prune_invalid_downloads
if [ "$CLEANUP_SEEN" = true ] && [ "$DRY_RUN" = false ]; then
  cleanup_seen_from_disk
  load_skip_lists
fi
if [ "$SYNC_OWNED" = true ]; then
  echo "📁 Scanning $DOWNLOAD_DIR for owned prestige titles..."
  scan_owned_into_skip || true
  load_skip_lists
fi
skip_n=$(skip_list_count)
skip_n=${skip_n:-0}
[ "${skip_n:-0}" -gt 0 ] && echo "⏭️  Skipping $skip_n titles ($SKIP_FILE + SKIP_LIST)"
[ ${#SEARCH_QUERIES} -gt 0 ] && echo "🔎 Extra Cinemeta searches: ${#SEARCH_QUERIES}"
[ "$FILTER_CATALOG_JUNK" = true ] && [[ "$SOURCE_ARG" == "all" || "$SOURCE_ARG" == "top" ]] && \
  echo "🧹 Catalog junk filter on (concerts/TV/anime) — use --no-junk-filter to disable"
IMDB_ONLY_MODE=false
if [ ${#IMDB_TARGETS} -gt 0 ] && [ ${#SEARCH_QUERIES} -eq 0 ]; then
  IMDB_ONLY_MODE=true
fi
if [ "$IMDB_ONLY_MODE" = true ]; then
  echo "📡 Fetching movies (imdb-only: ${#IMDB_TARGETS[@]} title(s))..."
else
  echo "📡 Fetching movies (source: $SOURCE_ARG, pages: $PAGES)..."
fi

raw_candidates=""
if [ "$IMDB_ONLY_MODE" = false ]; then
  if [[ "$SOURCE_ARG" == "prestige" || "$SOURCE_ARG" == "all" ]]; then
    raw_candidates+=$'\n'"$(fetch_prestige "$MIN_YEAR" "$MAX_YEAR")"
  fi
  for (( _p=0; _p<PAGES; _p++ )); do
    case "$SOURCE_ARG" in
      prestige) ;;  # already handled
      top)  raw_candidates+=$'\n'"$(fetch_cinemeta "top" "$_p")" ;;
      imdb) raw_candidates+=$'\n'"$(fetch_cinemeta "imdbTop" "$_p")" ;;
      yts)  raw_candidates+=$'\n'"$(fetch_yts "$((_p+1))")" ;;
      all)
        raw_candidates+=$'\n'"$(fetch_cinemeta "top" "$_p")"
        raw_candidates+=$'\n'"$(fetch_cinemeta "imdbTop" "$_p")"
        raw_candidates+=$'\n'"$(fetch_yts "$((_p+1))")"
        ;;
      *)    raw_candidates+=$'\n'"$(fetch_cinemeta "$SOURCE_ARG" "$_p")" ;;
    esac
  done
  if [ "$LIBRARY_MODE" = true ]; then
    raw_candidates+=$'\n'"$(fetch_discover)"
  fi
fi

if (( ${#SEARCH_QUERIES} > 0 )); then
  for q in $SEARCH_QUERIES; do
    raw_candidates+=$'\n'"$(cinemeta_search "$q")"
  done
fi
if (( ${#IMDB_TARGETS} > 0 )); then
  for _imdb in $IMDB_TARGETS; do
    raw_candidates+=$'\n'"$(fetch_imdb_meta "$_imdb")"
  done
fi

if [ "$FILTER_CATALOG_JUNK" = true ] && [[ "$SOURCE_ARG" == "all" || "$SOURCE_ARG" == "top" || "$LIBRARY_MODE" == true ]]; then
  prestige_ids_csv=$(get_prestige_imdb_csv || true)
  raw_candidates=$(filter_catalog_noise "$raw_candidates" "$prestige_ids_csv" || printf '%s' "$raw_candidates")
fi

# Deduplicate by IMDb ID (field 3). When mixing sources, prestige curated rows win ties.
if [[ "$SOURCE_ARG" == "all" ]]; then
  prestige_ids_csv=$(get_prestige_imdb_csv || true)
  skip_csv=$(print -l ${(f)SKIP_LIST_MERGED} | paste -sd, - || true)
  candidates=$(dedup_candidates "$raw_candidates" "$skip_csv" "$prestige_ids_csv" "" "$TOP_COUNT" all || true)
else
  skip_csv=$(print -l ${(f)SKIP_LIST_MERGED} | paste -sd, - || true)
  priority_csv=$(get_priority_imdb_csv || true)
  candidates=$(dedup_candidates "$raw_candidates" "$skip_csv" "" "$priority_csv" "$TOP_COUNT" priority || true)
fi

if [ -z "$candidates" ]; then
  echo "No movies matched your --rating / --year filters or prestige list."
  exit 0
fi

if [ "$LIST_ONLY" = true ]; then
  echo ""
  echo "Top critically acclaimed movies (by IMDb rating):"
  echo "────────────────────────────────────────────────────────────"
  idx=1
  while IFS=$'\t' read -r rating year imdb title; do
    [ -z "$imdb" ] && continue
    printf "%2d. %s (%s)  ⭐%s   imdb:%s\n" "$idx" "$title" "$year" "$rating" "$imdb"
    ((idx++))
  done <<< "$candidates"
  echo "────────────────────────────────────────────────────────────"
  exit 0
fi

# Pretty numbered list for selection
echo ""
echo "Top critically acclaimed movies (by IMDb rating):"
echo "────────────────────────────────────────────────────────────"
typeset -a MOVIE_LIST
idx=1
while IFS=$'\t' read -r rating year imdb title; do
  [ -z "$imdb" ] && continue
  printf "%2d. %s (%s)  ⭐%s\n" "$idx" "$title" "$year" "$rating"
  MOVIE_LIST[idx]="$imdb|$title|$year|$rating"
  ((idx++))
done <<< "$candidates"
total=$((idx - 1))
echo "────────────────────────────────────────────────────────────"
echo ""

# Interactive selection
DOWNLOADED_COUNT=0
if [ -n "$SELECT_ARG" ]; then
  sel_raw="$SELECT_ARG"
elif [ ! -t 0 ]; then
  echo "Non-interactive terminal — cannot prompt for selection."
  exit 0
else
  read -r -p "Select movies (e.g. 1 3 5-7, 'all', or 'q' to quit): " sel_raw
fi
sel=$(echo "$sel_raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [[ -z "$sel" || "$sel" == "q" || "$sel" == "quit" ]]; then
  echo "Aborted."
  exit 0
fi

# Parse selection (supports 1,3  2-5,8  all)
selected=()
if [[ "$sel" == "all" ]]; then
  for ((j=1; j<=total; j++)); do selected+=("$j"); done
else
  parts=(${(s:,:)sel})
  for p in $parts; do
    if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      s=$match[1]; e=$match[2]
      for ((j=s; j<=e; j++)); do
        [[ $j -ge 1 && $j -le $total ]] && selected+=("$j")
      done
    elif [[ "$p" =~ ^[0-9]+$ ]]; then
      j=$p
      [[ $j -ge 1 && $j -le $total ]] && selected+=("$j")
    fi
  done
fi

if [ ${#selected[@]} -eq 0 ]; then
  echo "No valid movies selected."
  exit 0
fi

# ── Optional autonomous screening (for --auto) ─────────────────────────────
if [ "$AUTO_MODE" = true ]; then
  echo ""
  echo "🤖 --auto: screening prestige/catalog titles for ones with real available proper torrents (Stremio/YTS)..."
  auto_selected=()
  screened=0
  for num in "${selected[@]}"; do
    [ "$DOWNLOADED_COUNT" -ge "$MAX_DOWNLOADS" ] && break
    entry="${MOVIE_LIST[num]}"
    IFS='|' read -r imdb title year rating <<< "$entry"
    if movie_exists_locally "$title" "$year"; then
      echo "  📁 ${title} (${year}) — already on disk"
      append_skip_imdb "$imdb"
      append_history_imdb "$imdb"
    elif is_skipped_imdb "$imdb"; then
      echo "  👁️  ${title} (${year}) — seen (won't fetch)"
    elif has_viable_torrent "$imdb" "$year"; then
      auto_selected+=("$num")
      echo "  ✅ ${title} (${year}) — seeded torrent found"
    else
      echo "  ⏭️  ${title} (${year}) — no seeded proper torrent yet (common for brand new fests)"
    fi
    screened=$((screened+1))
    [ ${#auto_selected[@]} -ge "$MAX_DOWNLOADS" ] && break
  done
  selected=()
  if [ ${#auto_selected[@]} -gt 0 ]; then
    selected=("${auto_selected[@]}")
  fi
  if [ ${#selected[@]} -eq 0 ]; then
    echo "No prestige titles with current proper torrents found in this run (try again later or use --source=all)."
    echo "✨ Done – 0 downloaded"
    exit 0
  fi
  echo "→ Auto-selected ${#selected[@]} with available torrents. Proceeding..."
fi

# Process the chosen ones
echo ""
if [ "$PARALLEL_DOWNLOADS" -gt 1 ]; then
  echo "⚡ Parallel mode: up to ${PARALLEL_DOWNLOADS} simultaneous downloads"
fi

processed=0
slot=0
proc_rc=0
for num in "${selected[@]}"; do
  entry="${MOVIE_LIST[num]}"
  IFS='|' read -r imdb title year rating <<< "$entry"

  if movie_exists_locally "$title" "$year"; then
    echo "⏭️  $title — already on disk, skipping"
    append_skip_imdb "$imdb"
    append_history_imdb "$imdb"
    continue
  fi
  if is_skipped_imdb "$imdb"; then
    echo "👁️  $title — seen, not fetching"
    continue
  fi

  if [ "$PARALLEL_DOWNLOADS" -le 1 ]; then
    proc_rc=0
    process_one_movie "$imdb" "$title" "$year" "$rating" 0 || proc_rc=$?
    [ "$proc_rc" -eq 2 ] && echo "💾 Low disk — stopping batch." && break
  else
    wait_for_download_slot "$PARALLEL_DOWNLOADS"
    run_movie_worker "$imdb" "$title" "$year" "$rating" "$slot" &
    slot=$(( (slot + 1) % PARALLEL_DOWNLOADS ))
  fi

  processed=$((processed + 1))
  [ "$AUTO_MODE" = true ] && [ "$processed" -ge "$MAX_DOWNLOADS" ] && break
done

if [ "$PARALLEL_DOWNLOADS" -gt 1 ]; then
  wait || true
  for rc_file in "$JOB_STATE_DIR"/worker-*.rc; do
    [ -f "$rc_file" ] || continue
    read -r wrc <"$rc_file" || wrc=0
    if [ "$wrc" -eq 2 ]; then
      proc_rc=2
      echo "💾 Low disk — stopping batch."
      break
    fi
  done
fi

DOWNLOADED_COUNT=$(count_job_successes)
echo ""
echo "✨ Done – $DOWNLOADED_COUNT downloaded to $DOWNLOAD_DIR"
exit 0
