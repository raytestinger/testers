#!/usr/bin/env perl

BEGIN { unshift @INC, "$ENV{HOME}/perl5/lib/perl5"; }
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
use File::Path::Tiny qw(mk );

# my @functions = ( 'current', 'file', 'smoke' );

# set default values for command line variables
my $function = 'current'; # others are file and smoke
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


# make sure directory tree is in place for this function
#foreach my $function (@functions) {
    my $function_cpanm_tree         = "$ENV{HOME}/testers/$function/.cpanm";
    my $function_cpanmreporter_tree = "$ENV{HOME}/testers/$function/.cpanmreporter";

    my $function_recent_log   = "$ENV{HOME}/testers/$function/recentlogs";
    my $function_reporter_log = "$ENV{HOME}/testers/$function/reporterlogs";
    my $function_test_log     = "$ENV{HOME}/testers/$function/testlogs";

    print "$function\n";
    print "$function_cpanm_tree\n";
    print "$function_cpanmreporter_tree\n";

    print "$function_recent_log\n";
    print "$function_reporter_log\n";
    print "$function_test_log\n";

    if ( !File::Path::Tiny::mk("$function_cpanm_tree") ) {
        die "Could not make path $function_cpanm_tree : $!";
    }

    if ( !File::Path::Tiny::mk("$function_cpanmreporter_tree") ) {
        die "Could not make path $function_cpanmreporter_tree : $!";
    }

    if ( !File::Path::Tiny::mk("$function_recent_log") ) {
        die "Could not make path $function_recent_log : $!";
    }

    if ( !File::Path::Tiny::mk("$function_reporter_log") ) {
        die "Could not make path $function_reporter_log : $!";
    }

    if ( !File::Path::Tiny::mk("$function_test_log") ) {
        die "Could not make path $function_test_log : $!";
    }

#}

