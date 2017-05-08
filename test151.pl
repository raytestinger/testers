#!/usr/bin/env perl

use strict;
use warnings;
use Parallel::ForkManager;
use LWP::Simple qw( get getstore );
use YAML qw( Load LoadFile );
use Time::HiRes qw( gettimeofday );
use App::cpanminus::reporter;
use Data::Dumper;
use Getopt::Long;
use List::MoreUtils qw( uniq );
use Test::Reporter::Transport::File;

# set default values for command line variables
my $jobs = 5;    # number of test processes created by Parallel::ForkManager
                 # one for each perl build invoked by perlbrew
                 # should be equal to number of entries in perlbuilds.txt

my $verbose = '';    # --verbose will print many trace messages

# CPAN server to check for updated modules
# if omitted URL below is default
my $cpan_server = 'http://cpan.cpantesters.org/authors';

GetOptions(
    'jobs=i'        => \$jobs,
    'verbose'       => \$verbose,
    'cpan_server=s' => \$cpan_server,
) or die "wrong Getopt usage \n";

print "\n\n==========>  ";    # indicate script start in output
system("date");

# kill any previously running instances of this script
kill_previous_run();

# save current PID
open my $tester_PID_fh, '>', 'tester_PID' or die "can't write tester_PID";
my $current_PID = $$;
print $tester_PID_fh $current_PID;
print "current PID is $current_PID, saving it\n" if ($verbose);
close $tester_PID_fh;

# what process name accompanies current PID?
# my $temp=`ps -e | grep $current_PID | grep -v grep`;
# print "my process name is:  $temp\n";

# if log directories or log files are absent, create them
create_log_files();

# load copies of RECENT.recent and disabled files from CPAN
# RECENT.recent contains names of new/changed modules
# disabled file contains names of modules not to be tested
my $Recent = get_recent_file();

# when was RECENT file updated?
my $Recent_updated = $Recent->{meta}{minmax}{max};

# when was RECENT file previously updated?
open my $previous_Recent_update_fh, '<', 'previous_Recent_update';
my $previous_Recent_update = <$previous_Recent_update_fh>;
close $previous_Recent_update_fh;
chomp $previous_Recent_update;

# if newest Recent file was updated after previous Recent file,
# there may be modules to test
if ( $Recent_updated > $previous_Recent_update ) {
    open my $previous_Recent_update_fh, '>', 'previous_Recent_update';

    # save time of latest Recent file update
    print $previous_Recent_update_fh $Recent_updated;
    close $previous_Recent_update_fh;
    chomp $previous_Recent_update;

    print "RECENT file updated since last checked\n" if ($verbose);
    check_for_updated_modules();
}
else {
    print "RECENT file not updated since last checked, exit\n" if ($verbose);
}

print "==========>  ";    # indicate script end in output
system("date");

###### end of main script ######

sub kill_previous_run {

    # kill previous PID
    # if the script's previous run is still alive, kill it
    if ( -e "tester_PID" )    # PID for previous script run is in this file
    {
        print "fetching previous PID\n" if ($verbose);
        open my $tester_PID_fh, '<', 'tester_PID'
          or die "can't read tester_PID";
        my $previous_PID = <$tester_PID_fh>;
        $previous_PID = " " . $previous_PID . " ";
        print "previous PID is $previous_PID\n" if ($verbose);

        # command returns 1 if still alive, 0 if not
        my $previous_tester_alive = `ps $previous_PID | grep -c $previous_PID`;
        print "previous_test_alive is: $previous_tester_alive\n" if ($verbose);

        if ( $previous_tester_alive != 0 ) {
            print "Previous script instance still alive, killing it\n"
              if ($verbose);

            # using -15 is supposed to kill all PID descendants,
            # but it kills this currently running script also
            # a -1 SIGUP seems to work best
            system("kill -1 $previous_PID");
            sleep 10;    # allow some time to die

            # if that didn't kill the still running script quit this script
            $previous_tester_alive = `ps $previous_PID | grep -c $previous_PID`;
            if ( $previous_tester_alive != 0 ) {
                die "previous script instance didn't die";
            }
        }
        else {
            print "Previous script instance not running now.\n" if ($verbose);
        }
        close $tester_PID_fh;
    }
}

sub create_log_files {

    # contains text output from 'cpanm --test_only $module' command
    unless ( -d "testlogs" ) {
        mkdir "testlogs";
        print "testlogs directory not found, created it\n" if ($verbose);
    }

    # contains text output from 'cpanm-reporter' command
    unless ( -d "reporterlogs" ) {
        mkdir "reporterlogs";
        print "reporterlogs directory not found, created it\n" if ($verbose);
    }

    # each tested module's name is stored here
    unless ( -e "modules_tested.log" ) {
        open my $modules_tested_log_fh, '>', 'modules_tested.log'
          or die "can't create modules_tested.log";
        close $modules_tested_log_fh;
        print "modules_tested.log file not found, created it\n" if ($verbose);
    }

    # timestamp of update to Recent.recent file previous to current recent file
    unless ( -e "previous_Recent_update" ) {
        open my $previous_Recent_update_fh, '>', 'previous_Recent_update'
          or die "can't create previous_Recent_update";
        print $previous_Recent_update_fh "0";
        close $previous_Recent_update_fh;
    }

    # contains copies of Recent.recent files, epoch time read is in filename
    unless ( -d "recentlogs" ) {
        mkdir "recentlogs";
        print "recentlogs directory not found, created it\n" if ($verbose);
    }

# local copy list of modules to not test, entries to be added by this script's user
    unless ( -e "01.myDISABLED.yml" ) {
        open my $myDISABLED_fh, '>', '01.myDISABLED.yml'
          or die "can't create 01.myDISABLED.yml";
        close $myDISABLED_fh;
        print "01.myDISABLED.yml file not found, created empty copy\n"
          if ($verbose);
    }
}

sub get_recent_file {

    # get the latest list of new or updated modules
    $Recent = YAML::Load( get("http://www.cpan.org/authors/RECENT.recent") );

########### begin for testing only ###########
    {
        # comment this code if not needed,
        # save copy of recent file to aid troubleshooting
        ( my $s, my $usec ) = gettimeofday;
        chomp $s;
        chomp $usec;
        my $rcnt = "recentlogs/rcnt" . "$s";
        LWP::Simple::getstore( "http://www.cpan.org/authors/RECENT.recent",
            "$rcnt" );
    }
########### end for testing only ###########

    # get and save a copy of list of modules which are not to be tested
    # file is maintained by CPAN tester ANDK
    LWP::Simple::getstore(
"http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml",
        "01.DISABLED.yml"
    );
    return ($Recent);
}

sub check_for_updated_modules {

    # we know the RECENT.recent file has been updated,
    # are there any new or updated modules to test?
    for my $recent_entry ( reverse @{ $Recent->{recent} } ) {

        # check only files ending in .tar.gz
        next unless ( $recent_entry->{path} =~ /\.tar\.gz$/ );
        print "found module $recent_entry->{path}\n" if ($verbose);

        my $Disabled = YAML::LoadFile('01.DISABLED.yml');

        # no need to repeat file check here
        #          or die "no local copy of 01.DISABLED.yml found\n";

        # script user's edition of
        # list of modules not to be tested
        # if 01.myDISABLED.yml is present but empty this code will die
        my $myDisabled = YAML::LoadFile('01.myDISABLED.yml');

        #          or die "no local copy of 01.myDISABLED.yml found\n";

        # isolate author/module name
        my $module = $recent_entry->{path};
        $module =~ s/\.tar\.gz//;
        my @name = split '/', $module;
        print "$module \n" if ($verbose);
        chomp $name[4];
        $module = $name[3] . '/' . $name[4];
        print "$name[3] $name[4]\n" if ($verbose);

        open my $disabled_list_fh, '>>', 'disabled_list.txt'
          or die "can't open disabled_list.txt";

        open my $enabled_list_fh, '>>', 'enabled_list.txt'
          or die "can't open enabled_list.txt";

        # check if this module is included in either disabled list
        # if it is, don't test this module
        # keep separate lists of enabled and disabled module names
        if (   ( $module =~ /$Disabled->{match}{distribution}/ )
            or ( $module =~ /$myDisabled->{match}{distribution}/ ) )
        {
            print $disabled_list_fh "$module \n";
            print "$module found in disabled list, do not test\n" if ($verbose);
            close $disabled_list_fh;
            close $enabled_list_fh;
            next;
        }
        else {
            print $enabled_list_fh "$module \n";
            print "$module not found in disabled list, continue\n"
              if ($verbose);
            close $disabled_list_fh;
            close $enabled_list_fh;
        }

        # module already been tested?
        # keep a list of tested modules in modules_tested.log
        # if a current module has already been tested
        # skip testing it
        my $already_tested = 0;
        open my $modules_tested_log_fh, '<', 'modules_tested.log'
          or die "cannot read modules_tested.log\n";
        while (<$modules_tested_log_fh>) {
            if (/$recent_entry->{path}/) {
                close $modules_tested_log_fh;
                print "$recent_entry->{path} has been tested, skip it\n"
                  if ($verbose);
                $already_tested = 1;
                last;
            }
        }

        # module hasn't been tested
        if ( $already_tested == 0 ) {
            close $modules_tested_log_fh;
            print "$recent_entry->{path} has not been tested, test it\n"
              if ($verbose);

            # update list of modules attempted to be tested
            # add this module to list
            open my $modules_tested_log_fh, '>>', 'modules_tested.log'
              or die "can't open modules_tested.log";

            my $timestamp = `date`;
            ( my $s, my $usec ) = gettimeofday;
            chomp $s;
            chomp $usec;
            my $this_check = "$s" . "." . "$usec ";

            # add current epoch time and formatted date and time
            # to module name entry, save in modules_tested file
            print $modules_tested_log_fh
              "$recent_entry->{path} $this_check $timestamp";
            close $modules_tested_log_fh;
            print
"added to modules tested log:  $recent_entry->{path} $this_check $timestamp"
              if ($verbose);
        }
    }
}

