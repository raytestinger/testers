#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect(          
    "dbi:SQLite:dbname=smoke.db", 
    "",                          
    "",                          
    { RaiseError => 1 },         
) or die $DBI::errstr;

my $sth = $dbh->prepare("SELECT * FROM smoke LIMIT 5");
$sth->execute();

my $row;
while ($row = $sth->fetchrow_arrayref()) {
    print "@$row[0] @$row[1] @$row[2] @$row[3] \n";
}

$sth->finish();
$dbh->disconnect();
