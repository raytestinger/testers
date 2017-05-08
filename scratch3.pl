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
use File::Path::Tiny qw( mk rm );

#
## beginning of main
#

# set default values for command line variables
my $jobs = 5;    # number of test processes created by Parallel::ForkManager
                 # one for each perl build invoked by perlbrew
                 # should be equal to number of entries in perlbuilds.txt

my $verbose  = '';           # --verbose will print many trace messages
my $function = 'current';    # default to testing RECENT.recent file

# CPAN server to check for updated modules
# if omitted URL below is default
my $cpan_server = 'http://cpan.cpantesters.org/authors';

GetOptions(
    'function=s'    => \$function,
    'jobs=i'        => \$jobs,
    'verbose'       => \$verbose,
    'cpan_server=s' => \$cpan_server,
) or die "wrong Getopt usage \n";

my $perlbuild     = '';                               # to be set later
my $function_home = "$ENV{HOME}/testers/$function";
my $function_cpanm_home = "$ENV{HOME}/testers/$function/.cpanm";
my $function_cpanmreporter_home =
  "$ENV{HOME}/testers//$function/.cpanmreporter/$perlbuild";

my $function_recent_log   = "$ENV{HOME}/testers/$function/recentlogs";
my $function_reporter_log = "$ENV{HOME}/testers/$function/reporterlogs";
my $function_test_log     = "$ENV{HOME}/testers/$function/testlogs";

my $script_PID_home = "$function_home/script_PID";

my $Recent_file_source = "http://www.cpan.org/authors/RECENT.recent";
my $Disabled_file_source =
  "http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml";

my $Disabled_file_copy   = "$function_home/01.DISABLED.yml";
my $myDisabled_file_copy = "$function_home/01.myDISABLED.yml";
my $rcnt_copy            = "$function_home/recentlogs/rcnt";
my $disabled_list        = "$function_home/disabled_list.txt";
my $enabled_list         = "$function_home/enabled_list.txt";

my $modules_tested_log = "$function_home/modules_tested_log";
my $perlbuilds_file    = "$function_home/perlbuilds.txt";

$ENV{PERL_CPAN_REPORTER_CONFIG} = "$function_home/.cpanmreporter/config.ini";

my %functions = (
    current => \&do_current,
    list    => \&do_list,
    smoker  => \&do_smoker,
);

# do this for all '$functions'
verify_directories_files();

say "\n\n==========>  ";    # indicate script start in output
system("date");

unless ( $function eq 'current' | $function eq 'list' | $function eq 'smoker' )
{
    die "variable \$function set to wrong value:  $function \n";
}

my $do_function = $functions{$function};
$do_function->();

#
## end of main
#

# only called when script is started
sub verify_directories_files {
    if ( !File::Path::Tiny::mk("$function_cpanm_home") ) {
        die "Could not make path $function_cpanm_home : $!";
    }
    say "Path $function_cpanm_home found" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_cpanmreporter_home") ) {
        die "Could not make path $function_cpanmreporter_home : $!";
    }
    say "Path $function_cpanmreporter_home found" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_recent_log") ) {
        die "Could not make path $function_recent_log : $!";
    }
    say "Path $function_recent_log found" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_reporter_log") ) {
        die "Could not make path $function_reporter_log : $!";
    }
    say "Path $function_reporter_log found" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_test_log") ) {
        die "Could not make path $function_test_log : $!";
    }
    say "Path $function_test_log found" if ($verbose);

    # first time through this file shouldn't be there

    if ( ( $function eq "current" ) && ( -e "$script_PID_home" ) ) {
        say "unlinking $script_PID_home" if ($verbose);
        unlink $script_PID_home or die "cannot unlink file $script_PID_home\n";
    }

    unless ( -e "$myDisabled_file_copy" ) {
        open( my $myDisabled_file_copy_fh, '>', "$myDisabled_file_copy" )
          or die("cannot open $myDisabled_file_copy\n");
        say $myDisabled_file_copy_fh "0";
        close $myDisabled_file_copy_fh;
    }

    unless ( -e "$modules_tested_log" ) {
        open( my $modules_tested_log_fh, '>', "$modules_tested_log" )
          or die("cannot create $modules_tested_log\n");
        close $modules_tested_log_fh;
    }

    # since this is run only at script start up,
    # get rid of history of tested and nontested files
    unlink $disabled_list;
    unlink $enabled_list;
}

sub do_current {

    # kill any previously running instances of this script
    say "entered sub do_current" if ($verbose);

    kill_previous_run();

    # save this script's  PID
    open my $script_PID_fh, '>', "$script_PID_home"
      or die "can't open $script_PID_home";
    my $script_PID = $$;
    say $script_PID_fh $script_PID;
    say "script PID is $script_PID, saving it" if ($verbose);
    close $script_PID_fh;

    my $Recent = get_recent_file();

    check_for_updated_modules($Recent);

    say "exiting do_current" if ($verbose);
}

# called only if $function = 'current'
sub kill_previous_run {

    # if the script's previous run is still alive, kill it,
    # PID for previous script run is in this file
    if ( -e "$script_PID_home" ) {
        say "fetching previous PID" if ($verbose);
        open my $tester_PID_fh, '<', "$script_PID_home"
          or die "can't $script_PID_home";
        my $previous_PID = <$tester_PID_fh>;
        chomp $previous_PID;
        close $tester_PID_fh;
        $previous_PID = " " . $previous_PID . " ";
        say "previous PID is $previous_PID" if ($verbose);

        # command returns 1 if still alive, 0 if not
        my $previous_tester_alive = `ps $previous_PID | grep -c $previous_PID`;
        say
"previous_tester_alive is (1=alive; 0=not alive): $previous_tester_alive"
          if ($verbose);

        if ( $previous_tester_alive != 0 ) {
            say "Previous script instance still alive, killing it";

            # using -15 is supposed to kill all PID descendants,
            # but it kills this currently running script also,
            # a -1 SIGUP works
            system("kill -1 $previous_PID");
            sleep 10;    # allow some time to die

            # if that didn't kill the still running script quit this script
            $previous_tester_alive = `ps $previous_PID | grep -c $previous_PID`;
            if ( $previous_tester_alive != 0 ) {
                die "previous script instance didn't die, quitting script\n";
            }
        }
        else {
            say "Previous script instance not running now, continue"
              if ($verbose);

        }
    }
}

sub get_recent_file {

    # get the latest list of new or updated modules
    my $Recent = YAML::Load( get($Recent_file_source) );

########### begin for testing only ###########
    {
        # comment this code if not needed,
        # save copy of recent file to aid troubleshooting
        ( my $s, my $usec ) = gettimeofday;
        chomp $s;
        chomp $usec;
        my $rcnt = $rcnt_copy . "$s";
        LWP::Simple::getstore( $Recent_file_source, $rcnt );
    }
########### end for testing only ###########

    # get and save a copy of list of modules which are not to be tested
    # file is maintained by CPAN tester ANDK
    LWP::Simple::getstore( $Disabled_file_source, $Disabled_file_copy );
    return ($Recent);
}

sub check_for_updated_modules {
    my $Recent = $_[0];

    # when was RECENT file updated?
    my $Recent_updated = $Recent->{meta}{minmax}{max};

    my $previous_Recent_update_file = "$function_home/previous_Recent_update";

    unless ( -e $previous_Recent_update_file ) {
        open my $previous_Recent_update_fh, '>', $previous_Recent_update_file;
        say $previous_Recent_update_fh "0";
        close $previous_Recent_update_fh;
    }

    # when was RECENT file previously updated?
    open my $previous_Recent_update_fh, '<', $previous_Recent_update_file;
    my $previous_Recent_update = <$previous_Recent_update_fh>;
    close $previous_Recent_update_fh;
    chomp $previous_Recent_update;

    # if newest Recent file was updated after previous Recent file,
    # there may be modules to test
    if ( $Recent_updated > $previous_Recent_update ) {

        say "RECENT file updated since last checked" if ($verbose);
        open my $previous_Recent_update_fh, '>', "$previous_Recent_update_file";

        # save time of latest Recent file update
        say $previous_Recent_update_fh $Recent_updated;
        close $previous_Recent_update_fh;
        chomp $previous_Recent_update;

        # we know the RECENT.recent file has been updated,
        # are there any new or updated modules to test?
        for my $recent_entry ( reverse @{ $Recent->{recent} } ) {

            # check only files ending in .tar.gz
            next unless ( $recent_entry->{path} =~ /\.tar\.gz$/ );
            say "found module $recent_entry->{path}" if ($verbose);

            say "Reading cpan disabled file" if ($verbose);
            my $Disabled = YAML::LoadFile($Disabled_file_copy);
            say "Read cpan disabled file" if ($verbose);

            say "Reading user copy of disabled file" if ($verbose);
            my $myDisabled = YAML::LoadFile($myDisabled_file_copy);
            say "Read user's disabled file" if ($verbose);

            # isolate author/module name
            my $module = $recent_entry->{path};
            $module =~ s/\.tar\.gz//;
            my @name = split '/', $module;
            say "$module " if ($verbose);
            chomp $name[4];
            $module = $name[3] . '/' . $name[4];
            say "$name[3] $name[4]" if ($verbose);

            open my $disabled_list_fh, '>>', $disabled_list
              or die "can't open $disabled_list";

            open my $enabled_list_fh, '>>', $enabled_list
              or die "can't open $enabled_list";

            # check if this module is included in either disabled list
            # if it is, don't test this module
            # keep separate lists of enabled and disabled module names
            if (   ( $module =~ /$Disabled->{match}{distribution}/ )
                or ( $module =~ /$myDisabled->{match}{distribution}/ ) )
            {
                say $disabled_list_fh "$module ";
                say "$module found in disabled list, do not test"
                  if ($verbose);
                close $disabled_list_fh;
                close $enabled_list_fh;
                next;
            }
            else {
                say $enabled_list_fh "$module ";
                say "$module not found in disabled list, continue"
                  if ($verbose);
                close $disabled_list_fh;
                close $enabled_list_fh;
            }

            # module already been tested?
            # keep a list of tested modules in modules_tested_log
            # if a current module has already been tested
            # skip testing it
            my $already_tested = 0;
            open my $modules_tested_log_fh, '<', $modules_tested_log
              or die "cannot read $modules_tested_log\n";
            while (<$modules_tested_log_fh>) {
                if (/$recent_entry->{path}/) {
                    close $modules_tested_log_fh;
                    say "$recent_entry->{path} has been tested, skip it"
                      if ($verbose);
                    $already_tested = 1;
                    last;
                }
            }

            # module hasn't been tested
            if ( $already_tested == 0 ) {
                close $modules_tested_log_fh;
                say "$recent_entry->{path} has not been tested, test it"
                  if ($verbose);

                # update list of modules attempted to be tested
                # add this module to list
                open my $modules_tested_log_fh, '>>', $modules_tested_log
                  or die "can't open $modules_tested_log";

                my $timestamp = `date`;
                ( my $s, my $usec ) = gettimeofday;
                chomp $s;
                chomp $usec;
                my $this_check = "$s" . "." . "$usec ";

                # add current epoch time and formatted date and time
                # to module name entry, save in modules_tested file,
                # use print instead of say, $timestamp already ends
                # with a return
                print $modules_tested_log_fh
                  "$recent_entry->{path} $this_check $timestamp";
                close $modules_tested_log_fh;
                print
"added to modules tested log:  $recent_entry->{path} $this_check $timestamp"
                  if ($verbose);
                test_module( $recent_entry->{path} );
            }
        }
        say "Finished checking RECENT file for updated *.tar.gz module files"
          if ($verbose);
    }
    say "Finished checking RECENT file for any updates"
      if ($verbose);

}

sub test_module {

# $id contains (example)
# http://cpan.cpantesters.org/authors/id/D/DA/DAGOLDEN/Acme-Devel-Hide-Tiny-0.001.tar.gz
    my ($id) = @_;

    # get list of perl builds to test modules against,
    # this list could change while script is running,
    # so read it here
    open my $perlbuilds_fh, '<', $perlbuilds_file
      or die "can't open $perlbuilds_file";

    # slurp file but don't change $/ in this case
    my @perlbuilds = <$perlbuilds_fh>;
    close $perlbuilds_fh;
    say "Perl revisions to test under:\n @perlbuilds" if ($verbose);

    # start a test process for each perl build,
    # maybe $jobs should be read from # of lines in perlbuilds.txt
    my $pm = Parallel::ForkManager->new($jobs);
    foreach my $perlbuild (@perlbuilds) {

        # make sure there's some time between log file timestamps
        sleep 1;

        say "starting test process for perl build $perlbuild" if ($verbose);
        chomp $perlbuild;
        system("date");

        $pm->start and next;

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

            my $BUILD_DIR           = $ENV{PERL_CPANM_HOME};
            my $BUILD_LOGFILE       = "$BUILD_DIR/build.log";
            my $CPANM_REPORTER_HOME = "$function_cpanmreporter_home";

            unless ( -d $BUILD_DIR ) {
                mkdir $BUILD_DIR;
                system("chmod 777 $BUILD_DIR");
            }

            say "BUILD_DIR is: $BUILD_DIR for $perlbuild"         if ($verbose);
            say "BUILD_LOGFILE is: $BUILD_LOGFILE for $perlbuild" if ($verbose);
            say "CPANM_REPORTER_HOME is: $CPANM_REPORTER_HOME for $perlbuild"
              if ($verbose);

            # isolate module name
            my $module = substr( $id, 0, rindex( $id, '-' ) );
            $module = substr( $module, rindex( $module, '/' ) + 1 );
            $module =~ s/-/::/g;

            # test the module, don't install it
            say "testing $module with $perlbuild" if ($verbose);
            system(
"perlbrew exec --with $perlbuild cpanm --test-only $module | tee $function_test_log/$module.$perlbuild"
            );

         # force cpanm-reporter to send all reports no matter when test was done
         # by unlinking reports-sent.db
         # --force arg to cpanm-reporter shouldn't be needed
         #            unlink("/home/ray/.cpanreporter/reports-sent.db");
            say "Building command for cpanm-reporter" if ($verbose);

            local $ENV{CPANM_REPORTER_HOME} = $function_cpanmreporter_home;
            say "CPANM_REPORTER_HOME is $CPANM_REPORTER_HOME" if ($verbose);

            my $command = "perlbrew exec --with $perlbuild ";
            $command .= "cpanm-reporter ";
            $command .= "--ignore-versions --force ";
            $command .= "--build_dir=$BUILD_DIR ";
            $command .= "--build_logfile=$BUILD_LOGFILE ";
            $command .=
              "| tee $function_reporter_log/$module.$function.$perlbuild ";
            say "Executing command:  $command" if ($verbose);
            system($command);
        };
        $pm->finish;
    }
    $pm->wait_all_children();
}

sub do_list {
    say "doing list";
}

sub do_smoker {
    say "doing smoker";
}

