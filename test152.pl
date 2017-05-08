#!/usr/bin/env perl

use Data::Dumper;

open my $modules_tested_log_fh, '<', 'modules_tested.log';
my @modules = <$modules_tested_log_fh>;
close $modules_tested_log_fh;

foreach my $module_name (@modules) {
    $module_name =~ s/\s.*//;
    my @fields = split /\//, $module_name;
    print "\nmodule name split\n";

    print Dumper @fields;

    unless ( $fields[0] =~ /id/ )  { die "first field not id, exiting\n" };
    print "first field is \'id\', correct \n";
    unless ( $fields[1] =~ /[A-Z]/ ) {  die "second field not A-Z, exiting\n" };
    print "second field is [A-Z], correct \n";
    unless ( $fields[2] =~ /[A-ZA-Z]/ ) {  die "third field not A-ZA-Z, exiting\n" };
    print "third field is [A-ZA-Z],correct \n";
    unless ( $fields[3] =~ /[A-Z]*/ ) { die "fourth field not all upper case, exiting\n" };
    print "fourth field is all upper case, correct \n";
    unless ( $fields[4] =~ /\.tar\.gz/ ) { die "fifth field missing tar.gz, exiting\n" };
    print "fifth field has .tar.gz extension, correct \n";
}

