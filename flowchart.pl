#!/usr/bin/perl


use Devel::Graph;
use v5.10;
use lib "/media/larry/sg2TB/cpantesters/.cpanm/latest-build/Devel-Graph-012/lib/Devel";

say "construct object";
my $grapher = Devel::Graph->new();
 
# read in code from a file
say "reading file";
my $graph_2 = $grapher->decompose( "scratch3.pl" );
say "printing file";
print $graph_2->as_ascii();


