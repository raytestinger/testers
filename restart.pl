#!/usr/bin/perl

print "\n\nstarting script\n";
system("date");
system("ps -ef | grep restart.pl | grep -v grep");

unless ( -e "previous_PID" ) {
    print "File with previous PID NOT found\n";
}
else {
    print "file with previous_PID found\n";
    open my $previous_PID_fh, '<', "previous_PID";
    my $previous_PID = (<$previous_PID_fh>);
    chomp $previous_PID;
    close $previous_PID_fh;

    print "previous_PID is:  $previous_PID\n";

    unless ( kill 0, $previous_PID ) {
        print "previous PID is not running\n";
        system("ps -ef | grep restart.pl | grep -v grep");
    }
    else {
        print "previous_PID still alive; killing it\n";
	# testing shows PID must be negative to work,
	# perldoc -f kill says results will be undefined
	# if PID is negative
	$previous_PID *= -1;	# 
        kill -1, $previous_PID;
        sleep 1;
        system("ps -ef | grep restart.pl | grep -v grep");
	$previous_PID *= -1;	# 
        if ( kill 0, $previous_PID ) {
            print "previous_PID still alive, quit\n";
            system("ps -ef | grep restart.pl | grep -v grep");
            exit;
        }
    }
}
print "save my PID\n";
my $my_PID = $$;
open $previous_PID_fh, '>', "previous_PID";
print $previous_PID_fh "$my_PID";
close $previous_PID_fh;
print "current PID $my_PID saved to file\n";

my $rand = int( rand(400) ) + 10;
print "waiting $rand seconds\n";
sleep $rand;
system("ps -ef | grep restart.pl | grep -v grep");
print "exiting script\n";

