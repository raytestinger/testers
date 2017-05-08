#!/usr/bin/env perl

BEGIN { unshift @INC, "$ENV{HOME}/perl5/lib/perl5"; }

use strict;
use warnings;
use v5.12;
use Parallel::ForkManager;
use LWP::Simple qw (get getstore);
use YAML qw ( Load LoadFile );
use Time::HiRes qw ( gettimeofday);
use App::cpanminus::reporter;
use Data::Dumper;
use Getopt::Long;
use List::MoreUtils qw ( uniq);
use Test::Reporter::Transport::File;
use File::Path::Tiny qw (mk rm);

#
## main begins here
## set variables using command line arguments
#

# CPAN server to fetch modules from,
# this path must be in user's MyConfig.pm urllist.
# MyConfig.pl should be in ~/.local/share/.cpan/CPAN
# use mkmyconfig command described in http://metacpan.org/pod/CPAN
# to create MyConfig.pm
my $cpan_server = 'http://cpan.cpantesters.org/authors';

# variables pointing to paths and files
my $perlbuild = '';        # perl version under which module will be tested
my $function  = 'smoke';
my $function_home               = "$ENV{PWD}/$function";
my $function_cpanm_home         = "$function_home/.cpanm";
my $function_cpanmreporter_home = "$function_home/.cpanmreporter/$perlbuild";
my $cpanmreporter_reports_sent  = "$ENV{PWD}/.cpanreporter/reports-sent.db";

my $recent_file_home  = "$function_home/recent_files";
my $reporter_log_home = "$function_home/reporter_logs";
my $test_log_home     = "$function_home/testlogs";
my $script_PID        = "$function_home/script_PID";

my $recent_file_url = "http://cpan.org/authors/RECENT.recent";
my $modules_url  = "http://cpan.cpantesters.org/modules/01modules.index.html";
my $modules_list = "$function_home/modules";

my $disabled_file_url =
  "http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml";
my $disabled_file   = "$function_home/01.DISABLED.yml";
my $mydisabled_file = "$function_home/01.myDISABLED.yml";

my $rcnt_file             = "$recent_file_home/rcnt";
my $running_disabled_list = "$function_home/disabled_list";
my $running_enabled_list  = "$function_home/enabled_list";
my $enabled_list_sort     = "$function_home/enabled_list_sort";

my $modules_tested_log = "$function_home/modules_tested_log";
my $perlbuilds         = "$function_home/perlbuilds";
my $verbose            = 1;
my $module_index       = 0;

local $ENV{PERL_CPAN_REPORTER_CONFIG} =
  "$function_home/.cpanmreporter/config.ini";

# get all module names from cpan
# save module names and excluded file names to disk, aid troubleshooting
my $Modules = get($modules_url);

open my $modules_fh, '>', "$modules_list"
  or die "can't open $modules_list";
say $modules_fh $Modules;
close $modules_fh;
` grep  '.tar.gz' $modules_list | sed -e 's/\.tar\.gz.*//g' | cut -c27- > tmp`;

# get list of files not to be tested;
# list maintained by ANDK
LWP::Simple::getstore( $disabled_file_url, $disabled_file );
my $Disabled = YAML::LoadFile($disabled_file);

# myDisabled file containing my additions
my $myDisabled = YAML::LoadFile($mydisabled_file);
open my $tmp_fh,           '<', "tmp";
open my $disabled_list_fh, '>', $running_disabled_list
  or die "can't open $running_disabled_list";

open my $enabled_list_fh, '>', $running_enabled_list
  or die "can't open $running_enabled_list";

while (<$tmp_fh>) {
    my $module = $_;
    chomp $module;

    # check if this module is included in either disabled list
    # if it is, don't test this module
    if (   ( $module =~ /$Disabled->{match}{distribution}/ )
        or ( $module =~ /$myDisabled->{match}{distribution}/ ) )
    {
      # module in excluded list
      #           say "$module in excluded list, skip testing it" if ($verbose);
        say $disabled_list_fh "$module " if ($verbose);
        next;
    }
    else {
        # module not in excluded list, test it
        #           say "$module not in excluded list, continue" if ($verbose);
        say $enabled_list_fh "$module ";
    }
}

close $disabled_list_fh;
close $enabled_list_fh;
close $tmp_fh;
unlink("tmp");    # no reason to keep it

# sort enabled modules into alpha order
open my $unsorted_modules_fh, '<', $running_enabled_list
  or die "can't open $running_enabled_list";
my @unsorted_modules = <$unsorted_modules_fh>;
close $unsorted_modules_fh;

my @tmp            = sort @unsorted_modules;
my @sorted_modules = uniq(@tmp);
undef @tmp;       # precaution
undef @unsorted_modules;

open my $sorted_modules_fh, '>', $enabled_list_sort
  or die "can't open $enabled_list_sort";
say $sorted_modules_fh @sorted_modules;
close $sorted_modules_fh;

open my $perlbuilds_fh, '<', "$perlbuilds" or die "can't open $perlbuilds";
my @revs = <$perlbuilds_fh>;    # slurp file but don't change $/ in this case
close $perlbuilds_fh;

say "Perl revisions to test with:\n @revs" if ($verbose);

my $TIMEOUT = 120;    # How long a child is running before it should be killed
my $pm   = Parallel::ForkManager->new(5);    # 5 max workers
my @jobs = 1 .. scalar @sorted_modules;      # how many jobs to run

# Hash of PID => time started or last known good
my %watching;

# While there is still work to do, or there are still active workers
while ( @jobs || $pm->running_procs ) {

    # Check to see if any workers are finished
    $pm->reap_finished_children;

    # Check to see if any workers need to be killed because of the
    # timeout. We must do this if we've reached the limit of the number
    # of jobs we want (we wait for a slot to open up), or if we've got
    # no more work to give out.
    if ( $pm->running_procs >= $pm->max_procs || !@jobs ) {
        say sprintf "[%5s] %2s: Checking jobs (%d running, %d left)", '-----',
          '--', scalar $pm->running_procs, scalar @jobs;
        for my $pid ( $pm->running_procs ) {
            if ( $watching{$pid}{time} + $TIMEOUT < time ) {

                # XXX: You can add a concern check here to see if it's
                # still working on something and reset the timeout
                # instead of killing the child. To reset the timeout,
                # just set the current time: $watching{ $pid } = time;
                # Kill the child
                # We're being unforgiving here. You might want to use
                # 'TERM' instead
                kill 'KILL', $pid;
                say sprintf "[%5d] %2d: Killed at %d", $pid,
                  $watching{$pid}{job}, time;
            }
        }

        # Sleep for much less than the timeout. This means we could have
        # a process that runs for up to 25% over the timeout. Our actual
        # timeout is between 10 and 13 seconds.
        sleep $TIMEOUT * 0.25;
        next;
    }

    # Start a new job
    my $job = shift @jobs;
    say "starting job $job" if ($verbose);

DATA_LOOP:
    foreach my $module (@sorted_modules) {
    # has module already been tested?
    chomp($module);
    my $tested = `grep -c $module $modules_tested_log`;
    chomp($tested);
    if ( $tested > 0 ) {
        say "$module already tested, skip it" if ($verbose);
	next;
    }
#    my $pid = $pm->start;
    my $pid = $pm->start and next DATA_LOOP;

    # Parent process: Start tracking the job worker
    if ($pid) {
        # Add to the watchdog timer
        $watching{$pid}{time} = time;
        $watching{$pid}{job}  = $job;
        next;
    }

    # put your application code here
    # Child process: Start the job
    say sprintf "[%5d] %2d: Started Job at %d", $$, $job, time;
        say "$module not yet tested, continue" if ($verbose);
        `echo $module >> $modules_tested_log`;
        test_module($module);
        say sprintf "[%5d] %2d: Finished!", $$, $job;
        system("date");
        say "<=============" if ($verbose);
    say "finishing job $job" if ($verbose);
    $pm->finish;
}
}
$pm->reap_finished_children;

sub test_module {

# $id contains (example)
# http://cpan.cpantesters.org/authors/id/D/DA/DAGOLDEN/Acme-Devel-Hide-Tiny-0.001.tar.gz
    my ($module) = @_;
    say "arg to test_module input:  $module " if ($verbose);

    # get list of perl builds to test modules against,
    # this list could change while script is running,
    # so read it here
    # make sure there's some time between output file timestamps
    $perlbuild = "perl-5.24.0";
    sleep 2;
    say "starting test process for perl build $perlbuild" if ($verbose);
    system("date");
    eval {
        # setup to handle signals
        local $SIG{'HUP'}  = sub { say "Got hang up" };
        local $SIG{'INT'}  = sub { say "Got interrupt" };
        local $SIG{'STOP'} = sub { say "Stopped" };
        local $SIG{'TERM'} = sub { say "Got term" };
        local $SIG{'KILL'} = sub { say "Got kill" };

        # this one won't work with apostrophes like above
        local $SIG{__DIE__} = sub { say "Got die" };

        # next two variable settings are explained in this link
### http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus
        local $ENV{NONINTERACTIVE_TESTING} = 1;
        local $ENV{AUTOMATED_TESTING}      = 1;

        # cpanm will put its test reports in this directory,
        # cpanm-reporter will get its input from this directory
        local $ENV{PERL_CPANM_HOME} = "$function_cpanm_home/$perlbuild";
        say "PERL_CPANM_HOME is:  $ENV{PERL_CPANM_HOME}" if ($verbose);
        my $BUILD_DIR     = $ENV{PERL_CPANM_HOME};
        my $BUILD_LOGFILE = "$BUILD_DIR/build.log";

        # my $CPANM_REPORTER_HOME = "$function_cpanmreporter_home";
        unless ( -d $BUILD_DIR ) {
            mkdir $BUILD_DIR;
            system("chmod 777 $BUILD_DIR");
        }
        say "BUILD_DIR is: $BUILD_DIR for $perlbuild"         if ($verbose);
        say "BUILD_LOGFILE is: $BUILD_LOGFILE for $perlbuild" if ($verbose);

        # isolate module name
        $module = substr( $module, 0, rindex( $module, '-' ) )
          if ( $module =~ /-/ );
        say "module name cleared of final dash:  $module" if ($verbose);
        $module = substr( $module, rindex( $module, '/' ) + 1 );
        $module =~ s/-/::/g;

        # test the module, don't install it
        my $command = "perlbrew exec --with $perlbuild ";
        $command .= "cpanm --test-only $module ";
        $command .= "| tee $test_log_home/$module.$perlbuild ";
        say "about to test $module for $perlbuild" if ($verbose);
        system("which perl") if ($verbose);
        check_test_exit( system("$command") );
        say "Should have completed testing $module for $perlbuild"
          if ($verbose);
        local $ENV{CPANM_REPORTER_HOME} = $function_cpanmreporter_home;
        say "CPANM_REPORTER_HOME is $ENV{CPANM_REPORTER_HOME}"
          if ($verbose);

  # reports already sent are listed in "user_home"/.cpanreporter/reports-sent.db
        unlink("$cpanmreporter_reports_sent");
        $command = "perlbrew exec --with $perlbuild ";
        $command .= "cpanm-reporter --verbose ";
        $command .= "--skip-history --ignore-versions --force ";
        $command .= "--build_dir=$BUILD_DIR ";
        $command .= "--build_logfile=$BUILD_LOGFILE ";
        $command .= "| tee $reporter_log_home/$module.$function.$perlbuild ";
        say "About to send cpanm report for $perlbuild: \n  $command"
          if ($verbose);
        check_reporter_exit( system($command) );
        say
"Should have completed sending cpanm report for $perlbuild :\n  $command"
          if ($verbose);
    };
    warn("bad exit from test_module subr") if $@;
}

sub check_test_exit {
    my ($exit) = @_;
    if ( $exit == -1 ) {
        say "test failed to execute: $!";
    }
    elsif ( $exit & 127 ) {
        printf "test child died with signal %d, %s coredump\n",
          ( $exit & 127 ), ( $exit & 128 ) ? 'with' : 'without';
    }
    else {
        printf "test child exited with value %d\n", $exit >> 8;
    }
}

sub check_reporter_exit {
    my ($exit) = @_;
    if ( $exit == -1 ) {
        say "reporter failed to execute: $!";
    }
    elsif ( $exit & 127 ) {
        printf "reporter child died with signal %d, %s coredump\n",
          ( $exit & 127 ), ( $exit & 128 ) ? 'with' : 'without';
    }
    else {
        printf "reporter child exited with value %d\n", $exit >> 8;
    }
}
