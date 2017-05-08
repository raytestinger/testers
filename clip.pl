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


my $Recent;

    # get the latest list of new or updated modules
    $Recent = YAML::Load( get("http://www.cpan.org/authors/RECENT.recent") );

        LWP::Simple::getstore( "http://www.cpan.org/authors/RECENT.recent",
            "rcnt" );

    # get and save a copy of list of modules which are not to be tested
    # file is maintained by CPAN tester ANDK
    LWP::Simple::getstore(
"http://cpansearch.perl.org/src/ANDK/CPAN-2.10/distroprefs/01.DISABLED.yml",
        "01.DISABLED.yml"
    );
