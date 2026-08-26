#!/bin/zsh
# Re-render the nine, with a lead each and no two drum beats alike.
#
# Why this exists rather than `demo-each`: the six demo slugs
# (ubrukte_samples_NN) are chopped-sample directories, not progressions, so
# TRACK= does not accept them and the manifest header saying it does is wrong.
# Each row below pairs a real record (SAMPLE_LOOP) with its own progression
# profile, so the chords and the drum grid differ per track and not just the
# kit's name.
#
# Drums: every row takes a different DRUM_PRESET x POCKET_SET pair -- all six of
# each are used and no pair repeats -- and the nine profiles carry nine
# different DRUM_PATTERN_SETS feels (timeless, organic, techno_house,
# chromatic_planing, loose_pocket, syncopated_slash_ninth and the three named
# profiles' own). Six kit names drawn from two families was what "sound same"
# actually was on the drum side.
#
# Leads: cd8e6850f turned LEAD_ARP/MELODIC_LEAD/EXPERIMENTAL_LEADS off because
# "the arpeggiated lead is the erratic one". The arp stays off here. What comes
# back is the melodic lead, one voice per track from a different instrument
# family, which is the only element that told these tracks apart.

set -u # scan: intentional — no -e: one track failing must not abort the other eight
# The engine, the samples and ../../.ruby-version are all anchored to the dilla
# root, so run from there rather than from scripts/.
cd "${0:A:h}/.."

export HARMONY_LEAD=1 MELODIC_LEAD=1 LEAD_ARP=0 LEAD_FORCE_ARP=0
export BARS=${BARS:-16}
export DILLA_SH_TIMEOUT=${DILLA_SH_TIMEOUT:-900}
export RBENV_VERSION=$(cat ../../.ruby-version)

# out : track : sample loop : drum preset : pocket : lead voice
rows=(
  # r1 rendered 2026-08-03; keep it.
  # "r1_mercury_lantern:neo_soul:samples/chopped/ubrukte_samples_01/loop.wav:dilla_slight:neo_soul:rhodes_lead_comp"
  "r2_velvet_channel:jazz:samples/chopped/ubrukte_samples_02/loop.wav:madlib_dusty:dusty:clean_jazz_guitar"
  "r3_nickel_mile:generated_techno:samples/chopped/ubrukte_samples_03/loop.wav:sp303:analog:moog_dilla_pocket"
  "r4_cedar_table:chromatic_planing:samples/chopped/ubrukte_samples_04/loop.wav:flylo_abstract:flylo:flylo_fm_shimmer"
  "r5_rust_field:chromatic_mediant:samples/chopped/ubrukte_samples_05/loop.wav:mpc3000:kit:dangelo_clav_lead"
  "r6_glass_pier:syncopated_slash_ninth:samples/chopped/ubrukte_samples_06/loop.wav:dilla_drunk:fm:glasper_ep_lead"
  "r7_lo_borges:lo_borges:samples/lo_borges/loop.wav:mpc3000:analog:erykah_dust_lead"
  "r8_kembara_rindu:kembara_rindu:samples/kembara_rindu/loop.wav:madlib_dusty:flylo:koto_pluck"
  "r9_semua_untuk_mu:semua_untuk_mu:samples/semua_untuk_mu/loop.wav:sp303:neo_soul:stevie_organ_lead"
)

ok=0
fail=0
for row in $rows; do
  out=${row%%:*}; rest=${row#*:}
  track=${rest%%:*}; rest=${rest#*:}
  loop=${rest%%:*}; rest=${rest#*:}
  preset=${rest%%:*}; rest=${rest#*:}
  pocket=${rest%%:*}
  lead=${rest#*:}

  if [[ ! -f $loop ]]; then
    print -r -- "skip $out: no record at $loop"
    fail=$((fail + 1))
    continue
  fi

  print -r -- "=== $out  track=$track drums=$preset/$pocket lead=$lead"
  TRACK=$track SAMPLE_LOOP=$loop DRUM_PRESET=$preset POCKET_SET=$pocket LEAD_VOICE=$lead \
    rbenv exec ruby dilla.rb dilla "$out.mp3" 2>&1 | tail -4
  if [[ -f $out.mp3 ]]; then
    print -r -- "    ok $(du -h $out.mp3 | cut -f1)"
    ok=$((ok + 1))
  else
    print -r -- "    FAILED $out"
    fail=$((fail + 1))
  fi
done

print -r -- "rendered $ok, failed $fail"
