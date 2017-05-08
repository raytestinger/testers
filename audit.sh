#!/bin/bash

grep '.tar.gz' ./recent/recent_files/rcnt* | awk -F"/" '{print $NF}' | sed -r 's/\.tar\.gz//' > rcntmods.txt
sort -u < rcntmods.txt > rcntmods.sort
grep -f rcntmods.sort ./recent/.cpanmreporter/offline/sync/* > rcntresult.txt

tail --lines=3 ./recent/testlogs/* | awk 'NF > 0' | paste -d " " - -  | \
sed -r 's/==> \.\/recent\/testlogs\///' > testresult.txt

grep 'PERLBREW_PERL = ' ./recent/.cpanmreporter/offline/sync/*rpt  | \
sed -r 's/\.\/recent\/\.cpanmreporter\/offline\/sync\///' | \
sed -r 's/\./ /' | \
sed -r 's/PERLBREW_PERL =//'      > rptresult.txt

sort --key=2 < rptresult.txt > rptresult.sort


