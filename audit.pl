#!/usr/bin/env perl

use v5.10;
use Data::Dumper;

open my $modules_tested_log_fh, '<', "./current/modules_tested_log";
my @modules = <$modules_tested_log_fh>;
close $modules_tested_log_fh;

foreach my $module (@modules) {
chomp $module;

my @rcnt_files = `ls ./current/recentlogs/*`;
foreach my $rcnt (@rcnt_files) {
chomp $rcnt;
say "rcnt $rcnt";

open my $rcnt_fh, '<', $rcnt;
my @rcntfile = <$rcnt_fh>;
close $rcnt_fh;

my @modules = `grep -A 1 -B 1 '.tar.gz' ./current/recentlogs/rcnt*`;
open my $modules_fh, '>', "./current/rcnt_modules.txt";
say $modules_fh @modules;
close $modules_fh;


#say Dumper @rcntfile;


}
}