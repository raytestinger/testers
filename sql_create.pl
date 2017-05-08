#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect(          
    "dbi:SQLite:dbname=smoke.db", 
    "",
    "",
    { RaiseError => 1}
) or die $DBI::errstr;

$dbh->do("DROP TABLE IF EXISTS smoke");

$dbh->do("CREATE TABLE smoke(Id INT PRIMARY KEY,Module TEXT,Author TEXT,Optional_Dir TEXT,Revision TEXT,Cpan_Test_Disabled TEXT,Tester_Test_Disabled TEXT,Perlbuild TEXT,Test_Complete TEXT,Test_Date TEXT,Test_Duration INT,Cpanm_Report TEXT,Cpanm_Test_Result TEXT,Cpanm_Reporter_Result TEXT,Cpanm_Reporter_Sent TEXT,Script_Name TEXT,Script_Revision TEXT,Script_Date TEXT)");

$dbh->do("INSERT INTO smoke VALUES(1,'Moose','ETHER','','2.2004','enabled','enabled',
'5.24.0-debug','completed','20170415','400','present','Pass','Pass','Yes','Smoker.pl',
'1.2','20160830')");

$dbh->do("INSERT INTO smoke VALUES(2,'Test-CheckManifest','RENEEB','','1.31','enabled','enabled',
'5.24.0-default','completed','20170416','300','present','Pass','Pass','Yes','Smoker.pl',
'1.2','20160830')");

$dbh->disconnect();