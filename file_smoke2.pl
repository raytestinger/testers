#!/usr/bin/env perl

BEGIN { unshift @INC, "$ENV{HOME}/perl5/lib/perl5"; }

use strict;
use warnings;
use v5.10;
use Parallel::ForkManager;
use LWP::Simple qw( get getstore );
use YAML qw( Load LoadFile );
use Time::HiRes qw( gettimeofday );
use App::cpanminus::reporter;
use Data::Dumper;
use Getopt::Long;
use List::MoreUtils qw( uniq );
use Test::Reporter::Transport::File;
use File::Path::Tiny;

# set default values for command line variables
my $function = 'smoke';    # default to testing files in RECENT.recent
my $jobs = 5;    # number of test processes created by Parallel::ForkManager
                 # one for each perl build invoked by perlbrew
                 # should be equal to number of entries in perlbuilds.txt

my $verbose = '';    # --verbose will print many trace messages

# CPAN server to check for updated modules
# if omitted URL below is default
my $cpan_server = 'http://cpan.cpantesters.org/authors';

GetOptions(
    'function=s'    => \$function,
    'jobs=i'        => \$jobs,
    'verbose'       => \$verbose,
    'cpan_server=s' => \$cpan_server,
) or die "wrong Getopt usage \n";

#
## set paths
#
my $tester_home     = "$ENV{HOME}/testers";
my $tester_function = "$tester_home/$function";

my $tester_recentlogs   = "$tester_function/recentlogs";
my $tester_reporterlogs = "$tester_function/reporterlogs";
my $tester_testlogs     = "$tester_function/testlogs";

my $module_list       = "$tester_function/module_list.txt";
my $enabled_list_sort = "$tester_function/enabled_list_sort";
my $enabled_list_txt  = "$tester_function/enabled_list_txt";

my $disabled_list_txt = "$tester_function/disabled_list_txt";
my $perlbuilds        = "$tester_function/perlbuilds.txt";
my $modules_index     = "$tester_function/01modules.index.html";

my $perlbuild           = '';
my $function_cpanm_home = "$tester_function/.cpanm";
my $function_cpanmreporter_home =
  "$ENV{HOME}/testers//$function/.cpanmreporter/$perlbuild";
my $function_cpanm_latest_build = "$tester_function/.cpanm/latest_build";

my $function_test_log     = "$tester_function/testlogs";
my $function_reporter_log = "$ENV{HOME}/testers/$function/reporterlogs";

my $Disabled_file_source =
  "http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml";

my $Disabled_file_copy   = "$tester_function/01.DISABLED.yml";
my $myDisabled_file_copy = "$tester_function/01.myDISABLED.yml";

open my $perlbuilds_fh, '<', "$perlbuilds" or die "can't open $perlbuilds";

# slurp file but don't change $/ in this case
my @revs = <$perlbuilds_fh>;
close $perlbuilds_fh;

say "Perl revisions to test with:\n @revs" if ($verbose);

# get all module names from cpan
# save module names and excluded file names to disk, aid troubleshooting
my $Modules = get("http://cpan.cpantesters.org/modules/01modules.index.html");

open my $modules_fh, '>', "$modules_index"
  or die "can't save $modules_index";
say $modules_fh $Modules;
close $modules_fh;

LWP::Simple::getstore( $Disabled_file_source, $Disabled_file_copy );
my $Disabled = YAML::LoadFile($Disabled_file_copy);

# myDisabled file containing my additions
my $myDisabled = YAML::LoadFile($myDisabled_file_copy);

open modules_fh, '<', $modules_index;

open my $disabled_list_fh, '>', $disabled_list_txt
  or die "can't open $disabled_list_txt";

open my $enabled_list_fh, '>', $enabled_list_txt
  or die "can't open $enabled_list_txt";

while (<modules_fh>) {
    my $module = $_;
    if ( ( $module =~ /^ href=/ ) && ( $module =~ /\.tar\.gz/ ) ) {
        $module = substr $module, 0, rindex( $module, '.tar' );
        $module = substr $module, 0, rindex( $module, '.tar' );

        my @fields = split '/', $module;
        $fields[6] = substr $fields[6], 0, rindex( $fields[6], '-' );
        $module = $fields[5] . "/" . $fields[6];

        # check if this module is included in disabled list
        # if it is, don't test this module
        if (   ( $module =~ /$Disabled->{match}{distribution}/ )
            or ( $module =~ /$myDisabled->{match}{distribution}/ ) )
        {
            # module in excluded list
            say "$module in excluded list, skip testing it";
            say $disabled_list_fh "$module ";
            next;
        }
        else {
            # module not in excluded list, test it
            say $enabled_list_fh "$module ";
        }
    }
}
close $disabled_list_fh;
close $enabled_list_fh;
close $modules_fh;

open my $unsorted_modules_fh, '<', $enabled_list_txt
  or die "can't open $enabled_list_txt";
my @unsorted_modules = <$unsorted_modules_fh>;
close $unsorted_modules_fh;

my @tmp            = sort @unsorted_modules;
my @sorted_modules = uniq(@tmp);

open my $sorted_modules_fh, '>', $enabled_list_sort
  or die "can't open $enabled_list_sort";
say $sorted_modules_fh @sorted_modules;
close $sorted_modules_fh;

foreach my $module (@sorted_modules) {
    system("date");

    #    $module =~ s/\s+//g;
    #    $module =~ s/-/::/g;
    #    $module =~ s/^[^\/]*\///;
    test_module($module);
}

sub test_module {

# $id contains (example)
# http://cpan.cpantesters.org/authors/id/D/DA/DAGOLDEN/Acme-Devel-Hide-Tiny-0.001.tar.gz
    my ($id) = @_;

    # get list of perl builds to test modules against
    open my $perlbuilds_fh, '<', $perlbuilds
      or die "can't open perlbuilds";

    # slurp file but don't change $/ in this case
    my @perlbuilds = <$perlbuilds_fh>;
    close $perlbuilds_fh;
    say "Perl revisions to test under:\n @perlbuilds" if ($verbose);

    # start a test process for each perl build,
    # maybe $jobs should be read from # of lines in perlbuilds.txt
    my $pm = Parallel::ForkManager->new($jobs);
    foreach my $perlbuild (@perlbuilds) {
        chomp $perlbuild;

        # make sure there's some time between log file timestamps
        sleep 1;

        say "starting test process for perl build $perlbuild" if ($verbose);

        $pm->start and next;
        eval {
            # setup to handle signals
            local $SIG{'HUP'}  = sub { say "Got hang up" };
            local $SIG{'INT'}  = sub { say "Got interrupt" };
            local $SIG{'STOP'} = sub { say "Stopped" };
            local $SIG{'TERM'} = sub { say "Got term" };
            local $SIG{'KILL'} = sub { say "Got kill" };

            # last one won't work with apostrophes like above
            local $SIG{__DIE__} = sub { say "Got die" };

            # variable settings are explained in this link
### http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus
            local $ENV{NONINTERACTIVE_TESTING} = 1;
            local $ENV{AUTOMATED_TESTING}      = 1;

            # cpanm will put its test reports in this directory,
            # cpanm-reporter will get its input from this directory
            local $ENV{PERL_CPANM_HOME} = "$function_cpanm_home/$perlbuild";
            say "PERL_CPANM_HOME is:  $ENV{PERL_CPANM_HOME}" if ($verbose);

            my $BUILD_DIR     = $ENV{PERL_CPANM_HOME};
            my $BUILD_LOGFILE = "$BUILD_DIR/latest_build/build.log";

            unless ( -d $BUILD_DIR ) {
                mkdir $BUILD_DIR;
                system("chmod 777 $BUILD_DIR");
            }

            say "BUILD_DIR is: $BUILD_DIR for $perlbuild"         if ($verbose);
            say "BUILD_LOGFILE is: $BUILD_LOGFILE for $perlbuild" if ($verbose);

            # isolate module name
            my $module = substr( $id, 0, rindex( $id, '-' ) );
            $module = substr( $module, rindex( $module, '/' ) + 1 );
            $module =~ s/-/::/g;

            my $cpanm_timeouts = " --configure-timeout 600 ";
            $cpanm_timeouts .= " --build-timeout 600 ";
            $cpanm_timeouts .= " --test-timeout 600 ";

            # test the module, don't install it
            my $command = "perlbrew exec --with $perlbuild ";
            $command .= "cpanm $cpanm_timeouts --test-only $module ";
            $command .= "| tee $function_test_log/$module.$perlbuild ";
            say "about to test $module with $perlbuild" if ($verbose);
            check_test_exit( system("$command") );

         # force cpanm-reporter to send all reports no matter when test was done
         # by unlinking reports-sent.db
         # --force arg to cpanm-reporter shouldn't be needed
         #            unlink("/home/ray/.cpanreporter/reports-sent.db");
            local $ENV{CPANM_REPORTER_HOME} = $function_cpanmreporter_home;
            say "CPANM_REPORTER_HOME is $ENV{CPANM_REPORTER_HOME}"
              if ($verbose);

            $command = "perlbrew exec --with $perlbuild ";
            $command .= "cpanm-reporter --verbose ";
            $command .= "--ignore-versions --force ";
            $command .= "--build_dir=$BUILD_DIR ";
            $command .= "--build_logfile=$BUILD_LOGFILE ";
            $command .=
              "| tee $function_reporter_log/$module.$function.$perlbuild ";

            say "About to send cpanm report:\n  $command" if ($verbose);
            check_reporter_exit( system($command) );
        };
        $pm->finish;
    }
    $pm->wait_all_children();
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

