#!/usr/bin/env perl

$function = "current";
$function_home = "$ENV{HOME}/testers/$function";
$function_cpanm_home         = "$ENV{HOME}/testers/$function/.cpanm";
$function_cpanmreporter_home = "$ENV{HOME}/testers/$function/.cpanmreporter";

$function_recent_log   = "$ENV{HOME}/testers/$function/recentlogs";
$function_reporter_log = "$ENV{HOME}/testers/$function/reporterlogs";
$function_test_log     = "$ENV{HOME}/testers/$function/testlogs";

$Recent_file_source = "http://www.cpan.org/authors/RECENT.recent";
$Disabled_file_source = "http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml";
$Disabled_file_copy = "$function_home/01.DISABLED.yml";
$rcnt_copy = "$function_home/recentlogs";

