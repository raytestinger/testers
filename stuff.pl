#!/usr/bin/env perl

BEGIN { unshift @INC, "$ENV{HOME}/perl5/lib/perl5"; }

use strict;
use warnings;
use v5.10;
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
use File::Basename;

system("cpanm .");

