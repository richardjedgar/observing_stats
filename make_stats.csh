#!/usr/bin/env tcsh

# get ASCDS tools (sqsh, param_extract)
source ~/.ascrc
# get rdb tools
source /proj/axaf/simul/etc/mst_envs.tcsh

#edit both these lists to add AO periods
set aolist = "10 11 12 13 14 15 16 17 18 19 20"
set aorev  = "20 19 18 17 16 15 14 13 12 11 10"

# set aolist = "15"
# set aorev  = "15"

# this script computes observing statistics for the indicated AO periods.
# It expects to find the following files in the directory where it runs:
# cases.rdb
# index.html
# hrc_extract.sqsh
# and a bunch of html files it uses to construct web pages:
# 4blank.html
# all_text.html
# ggto_text.html
# nocal_text.html
# wip_text.html
#
# there is a followup script make_drop_stats.csh that looks at
# chip-drop statistics.
# if new cases are desired, add them to the cases.rdb file
# and write a ${case}_text.html file to describe it.

# COPY THIS STUFF to another directory (label with the date) and run it.

# this next section must be redone if the aolist is expanded.

# if you need to re-run but not re-extract from the obscat, uncomment this
# (and the 'endif' below as marked)
# if ( 0 ) then
which param_extract
rm -f obscat_acis_?? obscat_hrc_?? *remarks *winparams *abstracts
foreach ao ( $aolist )

   echo param_extract -a -A $ao -b -o obscat_acis_${ao}
   param_extract -a -A $ao -b -o obscat_acis_${ao} >! obscat_acis_${ao}.log
   echo param_extract -h -A $ao -b -o obscat_hrc_${ao} 
   param_extract -h -A $ao -b -o obscat_hrc_${ao} >! obscat_hrc_${ao}.log

end
rm -f *remarks *winparams *abstracts

date +%D >! date_extracted.txt

# now go use sqsh to get the hrc parameters to file hrc_test
#
/usr/local/bin/sqsh -S ocatsqlsrv -Uedgar -w 400 < hrc_extract.sqsh >! hrc_obscat_test.txt

# endif
# end of obscat extraction; comment out if the 'if (0) then' line is commented out.

echo "************ ckpoint 002 ***************"

# foreach ao ( $aolist )
# cat hrc_test_${ao} \
cat hrc_obscat_test.txt \
| grep -v ' ------' \
| grep -v 'rows affected' \
| grep -v '^$' \
>! hrc_obscat.txt
# >! hrc_obscat_${ao}.txt

repair -blank -w -l -f hrc_obscat.txt
#repair -blank -w -l -f hrc_obscat_${ao}.txt

# end

# rdbcat hrc_obscat_??.rdb >! hrc_obscat.rdb


echo "************ ckpoint 003 ***************"

foreach ao ( $aolist )

# | row obs_ao_str eq $ao \

cat hrc_obscat.rdb \
| sorttbl obsid \
| column -v grating type \
   -c approved_exposure_time app_exp -c rem_exp_time rem_exp \
>! tmp.rdb

# apparently a few obsids don't match.
# different opinions as to which AO some things are in.
# so don't cut hrc_obscat.rdb on ao and it works.
#
cat obscat_hrc_${ao} \
| column -v -a ROW N \
| compute ROW eq _NR \
| sorttbl -uniq obsid \
| jointbl obsid tmp.rdb \
| sorttbl -uniq obsid \
>! hrc_obscat_${ao}.rdb

end #ao

# now we have hrc_obscat_*.rdb and obscat_acis* files.

set num_cases = `headchg -del < cases.rdb | wc -l`
set cases = `column case < cases.rdb | headchg -del`


# GTO, GO

echo "************ ckpoint 005 ***************"

foreach case ( $cases )
   set ctype=`row < cases.rdb case eq $case | column type | headchg -del`
   set cstatus=`row < cases.rdb case eq $case | column status | headchg -del`
   echo $case
   echo $ctype
   echo $cstatus



foreach ao ( $aolist )

   foreach inst ( HRC-S HRC-I )
     foreach grating ( NONE HETG LETG )
   cat hrc_obscat_${ao}.rdb \
   | column ao obsid seqnbr grating si status app_exp rem_exp type \
   | row $cstatus \
   | row grating eq $grating and si eq $inst \
   | row $ctype \
   | column -v -t app_exp N -t rem_exp N \
   | rdbstats app_exp rem_exp \
   | column -a ao N -a si S -a grating S app_exp_n app_exp_sum rem_exp_sum \
   | compute ao = $ao | compute si = $inst | compute grating = $grating \
   | compute app_exp_n = 0 if \( app_exp_sum eq "" \) \
   | compute app_exp_sum = 0 if \( app_exp_sum eq "" \) \
   | tee ${case}_stats_${inst}_${grating}_${ao}.rdb \
   | tbl2lst

   end # grating
   end # inst

   foreach inst ( ACIS-S ACIS-I )
     foreach grating ( NONE HETG LETG )
   cat obscat_acis_${ao} \
   | column ao obsid seqnbr grating si status app_exp rem_exp type \
   | row $cstatus \
   | row grating eq $grating and si eq $inst \
   | row $ctype \
   | column -v -t app_exp N -t rem_exp N \
   | rdbstats app_exp rem_exp \
   | column -a ao N -a si S -a grating S app_exp_n app_exp_sum rem_exp_sum \
   | compute ao = $ao | compute si = $inst | compute grating = $grating \
   | compute app_exp_n = 0 if \( app_exp_sum eq "" \) \
   | compute app_exp_sum = 0 if \( app_exp_sum eq "" \) \
   | tee ${case}_stats_${inst}_${grating}_${ao}.rdb \
   | tbl2lst

   end
   end


   rdbcat ${case}_stats_*${ao}.rdb \
   | rdbstats app_exp_sum app_exp_n \
   | column -a ao N -a si S -a grating S \
     -c app_exp_n_sum app_exp_n -c app_exp_sum_sum app_exp_sum \
     -a rem_exp_sum N \
   | compute ao = $ao | compute si = total \
   >! ${case}_total_stats_${ao}.rdb

   # never created...
   set tot_time=`column app_exp_sum < ${case}_total_stats_${ao}.rdb | headchg -del`
   set tot_obs=`column app_exp_n < ${case}_total_stats_${ao}.rdb | headchg -del`
   echo "${case}" $tot_time $tot_obs

   rdbcat ${case}_stats_*${ao}.rdb ${case}_total_stats_${ao}.rdb \
   | column -v -a pct_obs N -a pct_time N \
   | compute pct_obs = 100.0 \* app_exp_n / $tot_obs \
   | compute pct_time = 100.0 \* app_exp_sum / $tot_time \
   | rdbfmt pct_obs %.2f pct_time %.2f rem_exp_sum %.1f \
   >! ${case}_totals_${ao}.rdb

end

# rdbcat ggto_totals_1[567].rdb \
# | tee ggto_totals_151617.rdb

end #case

echo "************ ckpoint 006 ***************"
# set case = all
# foreach case ( $cases )
   # foreach ao ( $aolist )
   # cat ${case}_totals_${ao}.rdb \
   # | column si grating -c app_exp_n obsids_${ao} -c pct_obs pct_obs_${ao} \
      # -c app_exp_sum time_${ao} -c pct_time pct_time_${ao} \
   # >! tmp_${ao}.rdb
   # end

   # # jointbl si grating tmp_17.rdb < tmp_16.rdb \
   # # | jointbl si grating tmp_15.rdb \
   # # | rdb2html >! $case.html

# end

# new stuff June 20, 2017
#

# possibly make a plot of stuff vs. AO here, to include as an image.
# sorta like this:
# rdbcat all_totals_??.rdb \
# | sorttbl si grating ao \
# | rdbplt xcol=ao ycol=pct_obs break=grating dev=/xs legend+ 

foreach case ( $cases )
    rdbcat ${case}_totals_??.rdb \
    | sorttbl si grating ao \
    | row si ne "total" \
    | tee tmp.rdb \
    | rdbplt xcol=ao ycol=pct_obs break=grating dev=/xs legend+ \
       legend_opts="x=0.1 y=0.9 ul box" title="red=ACIS-I, green=ACIS-S gray=HRC-I magenta=HRC-S" \
       color=red,red,red,green,green,green,lightgray,lightgray,lightgray,magenta,magenta,magenta,white \
       marker=1,2,3,1,2,3,1,2,3,1,2,3,4 line_width=3 \
       connect=dash,full,dot,dash,full,dot,dash,full,dot,dash,full,dot
    cat tmp.rdb \
    | rdbplt xcol=ao ycol=pct_obs break=grating dev=${case}_num.ps/cps legend+ \
       legend_opts="x=0.1 y=0.9 ul box" title="red=ACIS-I, green=ACIS-S gray=HRC-I magenta=HRC-S" \
       color=red,red,red,green,green,green,lightgray,lightgray,lightgray,magenta,magenta,magenta,white \
       marker=1,2,3,1,2,3,1,2,3,1,2,3,4 line_width=3 \
       connect=dash,full,dot,dash,full,dot,dash,full,dot,dash,full,dot
    rm tmp.rdb

    rdbcat ${case}_totals_??.rdb \
    | sorttbl si grating ao \
    | row si ne "total" \
    | tee tmp.rdb \
    | rdbplt xcol=ao ycol=pct_time break=grating dev=/xs legend+ \
       legend_opts="x=0.1 y=0.9 ul box" title="red=ACIS-I, green=ACIS-S gray=HRC-I magenta=HRC-S" \
       color=red,red,red,green,green,green,lightgray,lightgray,lightgray,magenta,magenta,magenta,white \
       marker=1,2,3,1,2,3,1,2,3,1,2,3,4 line_width=3 \
       connect=dash,full,dot,dash,full,dot,dash,full,dot,dash,full,dot
    cat tmp.rdb \
    | rdbplt xcol=ao ycol=pct_time break=grating dev=${case}_time.ps/cps legend+ \
       legend_opts="x=0.1 y=0.9 ul box" title="red=ACIS-I, green=ACIS-S gray=HRC-I magenta=HRC-S" \
       color=red,red,red,green,green,green,lightgray,lightgray,lightgray,magenta,magenta,magenta,white \
       marker=1,2,3,1,2,3,1,2,3,1,2,3,4 line_width=3 \
       connect=dash,full,dot,dash,full,dot,dash,full,dot,dash,full,dot
    rm tmp.rdb

    ps2any --trim --rotate=90 ${case}_num.ps ${case}_num.png
    ps2any --trim --rotate=90 ${case}_time.ps ${case}_time.png

    # should use date extracted, not date of script run
    echo "OBSCAT data extracted `cat date_extracted.txt`</p><p>" >! tmp.html
    # echo "OBSCAT data extracted `date +%D`</p><p>" >! tmp.html
    cat ${case}_text.html >> tmp.html
    foreach ao ( $aorev )
	cat 4blank.html >> tmp.html
	cat ${case}_totals_${ao}.rdb \
	| column ao si grating -c app_exp_n obsids pct_obs -c app_exp_sum time pct_time \
	| rdb2html >> tmp.html
    end
    mv tmp.html ${case}_allyears.html
end 
# end #case


rm -rf observing_stats/*
mkdir observing_stats
cp {all,nocal,ggto,wip}_allyears.html observing_stats
cp {all,nocal,ggto,wip}_{num,time}.png observing_stats
cp index.html observing_stats
tar cfv obscat_stats.tar observing_stats


# this line copies the tarball to the web DMZ.
cp obscat_stats.tar /proj/web-cxc-dmz/htdocs/acis/tmp
