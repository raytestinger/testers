#!/usr/bin/env perl

my $login = getlogin || getpwuid($<);

print "$login";


