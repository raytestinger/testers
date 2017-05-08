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

my $function_home               = "$ENV{HOME}/testers/$function";
my $function_cpanm_home         = "$ENV{HOME}/testers/$function/.cpanm";
my $function_cpanmreporter_home = "$ENV{HOME}/testers/$function/.cpanmreporter";

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

my $modules_tested_log = "$function_home/modules_tested.log";

my %functions = (
    current => \&do_current,
    list    => \&do_list,
    smoker  => \&do_smoker,
);

# do this for all '$functions'
verify_directories_files();

print "\n\n==========>  ";    # indicate script start in output
system("date");

unless ( $function eq 'current' | $function eq 'list' | $function eq 'smoker' )
{
    die "variable \$function set to wrong value:  $function \n";
}

my $do_function = $functions{$function};
$do_function->();

# only called when script is entered
sub verify_directories_files {
    if ( !File::Path::Tiny::mk("$function_cpanm_home") ) {
        die "Could not make path $function_cpanm_home : $!";
    }
    print "Path $function_cpanm_home found\n" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_cpanmreporter_home") ) {
        die "Could not make path $function_cpanmreporter_home : $!";
    }
    print "Path $function_cpanmreporter_home found\n" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_recent_log") ) {
        die "Could not make path $function_recent_log : $!";
    }
    print "Path $function_recent_log found\n" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_reporter_log") ) {
        die "Could not make path $function_reporter_log : $!";
    }
    print "Path $function_reporter_log found\n" if ($verbose);

    if ( !File::Path::Tiny::mk("$function_test_log") ) {
        die "Could not make path $function_test_log : $!";
    }
    print "Path $function_test_log found\n" if ($verbose);

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
    print $script_PID_fh $script_PID;
    print "script PID is $script_PID, saving it\n" if ($verbose);
    close $script_PID_fh;

    my $Recent = get_recent_file();

    if ( check_for_updated_recent_file($Recent) ) {
        check_for_updated_modules($Recent);
    }

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
        print "previous PID is $previous_PID\n" if ($verbose);

        # command returns 1 if still alive, 0 if not
        my $previous_tester_alive = `ps $previous_PID | grep -c $previous_PID`;
        print
"previous_tester_alive is (1=alive; 0=not alive): $previous_tester_alive\n"
          if ($verbose);

        if ( $previous_tester_alive != 0 ) {
            print "Previous script instance still alive, killing it\n";

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
            print "Previous script instance not running now, continue\n"
              if ($verbose);

        }
    }
}

sub get_recent_file {

    # get the latest list of new or updated modules
    my $recent = YAML::Load( get($Recent_file_source) );

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
    return ($recent);
}

sub check_for_updated_recent_file {
    say "display _[0]";
    say Dumper $_[0];

    my $recent = $_[0];
    say "display recent";
    say Dumper $recent;

    # when was RECENT file updated?
    say "display Recent->....";
    say Dumper $recent->{meta}{minmax}{max};

    my $recent_updated = $recent->{meta}{minmax}{max};
    say "display recent_updated";
    say Dumper $recent_updated;

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
    if ( $recent_updated > $previous_Recent_update ) {
        open my $previous_Recent_update_fh, '>', "$previous_Recent_update_file";

        # save time of latest Recent file update
        print $previous_Recent_update_fh $recent_updated;
        close $previous_Recent_update_fh;
        chomp $previous_Recent_update;

        print "RECENT file updated since last checked\n" if ($verbose);
        return (1);    # file is updated
    }
    else {
        print "RECENT file not updated since last checked\n" if ($verbose);
        return (0);    # file is not updated
    }

    sub isolate_module_name {
        my $module = $_[0];

        # isolate author/module name
        $module =~ s/\.tar\.gz//;
        my @name = split '/', $module;
        print "$module \n" if ($verbose);
        chomp $name[4];
        $module = $name[3] . '/' . $name[4];
        print "$name[3] $name[4]\n" if ($verbose);
        return ($module);
    }

    sub check_for_updated_modules {
	say Dumper @_;
        my ($recent) = @_;
	say Dumper $recent;

        # we know the RECENT.recent file has been updated,
        # are there any new or updated modules to test?
        say "looking for files ending in .tar.gz" if ($verbose);
        for my $recent_entry ( reverse @{ $recent->{recent} } ) {
	    say "display recent_entry";
            say Dumper $recent_entry if ($verbose);

            # check only files ending in .tar.gz
            if ( $recent_entry->{path] =~ /\.tar\.gz$/ ) {
                say "found updated module recent_entry->{path}" if ($verbose);
            }
            else {
                next;
            }
            my $Disabled   = YAML::LoadFile($Disabled_file_copy);
            my $myDisabled = YAML::LoadFile($myDisabled_file_copy);

            my $module = isolate_module_name($recent_entry);

            open my $disabled_list_fh, '>>', $disabled_list
              or die "can't open $disabled_list";

            # check if this module is included in either disabled list
            # if it is, don't test this module
            # keep separate lists of enabled and disabled module names
            if ( $module =~ /$Disabled->{match}{distribution}/ )

       #                or ( $module =~ /$myDisabled->{match}{distribution}/ ) )
            {
                print $disabled_list_fh "$module \n";
                print "$module found in disabled list, do not test\n"
                  if ($verbose);
                close $disabled_list_fh;
                next;
            }

            # module already been tested?
            # keep a list of tested modules in modules_tested.log
            # if a current module has already been tested
            # skip testing it
            my $already_tested = 0;
            open my $modules_tested_log_fh, '<', $modules_tested_log
              or die "cannot read $modules_tested_log\n";
            while (<$modules_tested_log_fh>) {
                if (/$recent_entry/) {
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
                open my $modules_tested_log_fh, '>>', $modules_tested_log
                  or die "can't open $modules_tested_log";

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
}

sub do_list {
    say "doing list";
}

sub do_smoker {
    say "doing smoker";
}

