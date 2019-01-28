#!/usr/bin/env tcsh

# get rdb tools
source /proj/axaf/simul/etc/mst_envs.tcsh
#

# the idea here is to compute for each AO the percentage of executed ACIS observations with dropcount > 0.
#
#

# inputs are the ACIS obscat exctraction from make_stats.csh, in files acis_obscat_${ao} for ao=10..19

# filter on status as in that script, and then do stats for dropcount = 0 and dropcount > 0.

rm -rf drop_stats
mkdir drop_stats

foreach ocatfile ( obscat_acis_?? )

   cat $ocatfile \
   | row status eq 'archived' or status eq 'scheduled' or status eq 'observed' \
   | column -t ao N -t dropped_chip_count N \
   | tee tmp_obsv.rdb \
   | row dropped_chip_count gt 0 \
   | rdbstats ao \
   | column -c ao_n num_drops -c ao_ave ao \
   >! tmp_drop_stat.rdb

   set fn = `column ao < tmp_drop_stat.rdb | headchg -del`

   cat tmp_obsv.rdb \
   | rdbstats ao \
   | column -c ao_n num_props -c ao_ave ao \
   | jointbl ao tmp_drop_stat.rdb \
   | column -v -a pct N \
   | compute pct = 100.0 \* num_drops / num_props \
   | rdbfmt pct "%.1f" \
   >! drop_stats/${fn}_drop_pct.rdb



# cat $ocatfile | row status eq 'archived' or status eq 'scheduled' or status eq 'observed' | column -t ao N | rdbstats ao
# cat $ocatfile | row status eq 'archived' or status eq 'scheduled' or status eq 'observed' | row dropped_chip_count gt 0 | column -t ao N | rdbstats ao

end

cd drop_stats

rdbcat ??_drop_pct.rdb > drop_stats.xxx

repair -e drop_stats.xxx

ptbl < drop_stats.rdb


