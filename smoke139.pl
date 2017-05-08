#!/usr/bin/env perl

use strict;
use warnings;
use lib '/home/ray/perl5/lib/perl5';
use Parallel::ForkManager;
use LWP::Simple qw( get getstore);
use YAML qw( Load LoadFile);
use Time::HiRes qw( gettimeofday );
use App::cpanminus::reporter;
use Data::Dumper;
use Getopt::Long;
use Time::Out qw(timeout);
use List::MoreUtils qw(uniq);

# setup variable number of jobs
my $passes;
my $jobs       = 4;
my $verbose    = '';
my $mydisabled = '';

GetOptions(
    'jobs=i'     => \$jobs,
    'verbose'    => \$verbose,
    'mydisabled' => \$mydisabled,
) or die "wrong Getopt usage \n";

print "starting $jobs jobs\n" if ($verbose);

if ($verbose) {
    if ($mydisabled) {
        print
"module names excluded from testing are taken from local file 01.DISABLED.yml\n";
    }
    else {
        print
"module names excluded from testing are taken from CPAN copy of 01.DISABLED.yml\n";
    }
}

print "deleting old module_list, .cpan/work and .cpanreporter/offline/sync\n"
  if ($verbose);
print "deleting old testlogs and reporterlogs\n"
  if ($verbose);

unlink "module_list.txt" if ( -e "module_list.txt" );
system("rm testlogs/*");
system("rm reporterlogs/*");

system("rm -rf ~/.cpanm/work/*");
system("rm -rf ~/.cpanreporter/offline/sync/*");

unlink "enabled_list.txt";
unlink "enabled_list.sort";
unlink "disabled_list.txt";

open my $perlrevs_fh, '<', 'perlrevs.txt' or die "can't open perlrevs.txt";

# slurp file but don't change $/ in this case
my @revs = <$perlrevs_fh>;
close $perlrevs_fh;

print "Perl revisions to test with:\n @revs\n" if ($verbose);

# get all module names from cpan
# save module names and excluded file names to disk, aid troubleshooting
my $Modules = get("http://cpan.cpantesters.org/modules/01modules.index.html");

open my $modules_fh, '>', '01modules.index.html'
  or die "can't save modules.index";
print $modules_fh $Modules;
close $modules_fh;

my $Disabled = YAML::Load(
    get(
"http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml"
    )
);

# disabled file containing my additions
my $myDisabled = YAML::LoadFile('01.myDISABLED.yml');

open modules_fh, '<', '01modules.index.html';

open my $disabled_list_fh, '>', 'disabled_list.txt'
  or die "can't open disabled_list.txt";

open my $enabled_list_fh, '>', 'enabled_list.txt'
  or die "can't open enabled_list.txt";

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
            print $disabled_list_fh "$module \n";
            next;
        }
        else {
            # module not in excluded list, test it
            print $enabled_list_fh "$module \n";
        }
    }
}
close $disabled_list_fh;
close $enabled_list_fh;
close $modules_fh;

open my $unsorted_modules_fh, '<', 'enabled_list.txt'
  or die "can't open enabled_list.txt";
my @unsorted_modules = <$unsorted_modules_fh>;
close $unsorted_modules_fh;

my @tmp            = sort @unsorted_modules;
my @sorted_modules = uniq(@tmp);

open my $sorted_modules_fh, '>', 'enabled_list.sort'
  or die "can't open enabled_list.sort";
print $sorted_modules_fh @sorted_modules;
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
    open my $perlbuilds_fh, '<', 'perlbuilds.txt'
      or die "can't open perlbuilds.txt";

    # slurp file but don't change $/ in this case
    my @perlbuilds = <$perlbuilds_fh>;
    close $perlbuilds_fh;
    print "Perl revisions to test under:\n @perlbuilds\n" if ($verbose);

    # start a test process for each perl build,
    # maybe $jobs should be read from # of lines in perlbuilds.txt
    my $pm = Parallel::ForkManager->new($jobs);
    foreach my $perlbuild (@perlbuilds) {
        chomp $perlbuild;
        print "starting test process for perl build $perlbuild\n" if ($verbose);

        $pm->start and next;
        eval {
            # setup to handle signals
            local $SIG{'HUP'}  = sub { print "Got hang up\n" };
            local $SIG{'INT'}  = sub { print "Got interrupt\n" };
            local $SIG{'STOP'} = sub { print "Stopped\n" };
            local $SIG{'TERM'} = sub { print "Got term\n" };
            local $SIG{'KILL'} = sub { print "Got kill\n" };

            # last one won't work with apostrophes like above
            local $SIG{__DIE__} = sub { print "Got die\n" };

            # variable settings are explained in this link
### http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus
            local $ENV{NONINTERACTIVE_TESTING} = 1;
            local $ENV{AUTOMATED_TESTING}      = 1;

            # cpanm will put its test reports in this directory,
            # cpanm-reporter will get its input from this directory
            unless ( -d "/homme/ray/.cpanm/$perlbuild" ) {
                mkdir "/home/ray/.cpanm/$perlbuild";
            }

            local $ENV{PERL_CPANM_HOME} = "/home/ray/.cpanm/$perlbuild";
            system("chmod 777 ~/.cpanm/$perlbuild");

            # isolate module name
            my $module = substr( $id, 0, rindex( $id, '-' ) );
            $module = substr( $module, rindex( $module, '/' ) + 1 );
            $module =~ s/-/::/g;
            print "testing $module with $perlbuild\n" if ($verbose);

            my $cpanm_timeouts = " --configure-timeout 600 ";
            $cpanm_timeouts .= " --build-timeout 600 ";
            $cpanm_timeouts .= " --test-timeout 600 ";

            # test the module, don't install it
            my $command = "perlbrew exec --with $perlbuild ";
            $command .= "cpanm $cpanm_timeouts --test-only $module ";
            $command .= "| tee ./testlogs/$module.$perlbuild\n";
            system("$command");

            my $BUILD_DIR     = "$ENV{HOME}/.cpanm/$perlbuild";
            my $BUILD_LOGFILE = "$BUILD_DIR/build.log";
            my $CPANM_REPORTER_HOME =
              "$ENV{HOME}/perl5/perlbrew/perls/$perlbuild/bin";

            # each $perlbuild must have a copy of cpanm_reporter
            unless ( -e "$CPANM_REPORTER_HOME/cpanm_reporter" ) {
                die "cpanm_reporter not found in $CPANM_REPORTER_HOME\n
		    see the Installation Notes for cpanm_reporter\n
		    by entering \'perldoc tester.pl\'  \n";
            }

            print "BUILD_DIR is: $BUILD_DIR\n"         if ($verbose);
            print "BUILD_LOGFILE is: $BUILD_LOGFILE\n" if ($verbose);
            print "CPANM_REPORTER_HOME is: $CPANM_REPORTER_HOME\n"
              if ($verbose);
            print "Building command for cpanm-reporter\n" if ($verbose);

         # force cpanm-reporter to send all reports no matter when test was done
         # by unlinking reports-sent.db
         # --force arg to cpanm-reporter shouldn't be needed
            unlink("/home/ray/.cpanreporter/reports-sent.db");

            my $command = "perlbrew exec --with $perlbuild ";
            $command .= "$CPANM_REPORTER_HOME/cpanm-reporter ";
            $command .= "--ignore-versions --force ";
            $command .= "--build_dir=$BUILD_DIR ";
            $command .= "--build_logfile=$BUILD_LOGFILE ";
            $command .= "| tee ./reporterlogs/$module.$perlbuild ";
            print "Executing command:  $command\n" if ($verbose);
            system($command);
        };
        $pm->finish;
    }
    $pm->wait_all_children();
}

sub check_test_exit {
    my ($exit) = @_;
    if ( $exit == -1 ) {
        print "test failed to execute: $!\n";
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
        print "reporter failed to execute: $!\n";
    }
    elsif ( $exit & 127 ) {
        printf "reporter child died with signal %d, %s coredump\n",
          ( $exit & 127 ), ( $exit & 128 ) ? 'with' : 'without';
    }
    else {
        printf "reporter child exited with value %d\n", $exit >> 8;
    }
}

