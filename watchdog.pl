#!/usr/bin/perl

use v5.12;
use Parallel::ForkManager;

my $TIMEOUT = 10;
my $pm      = Parallel::ForkManager->new(5);
my @jobs    = 1 .. 20;
my $killed  = 0;

# Hash of PID => time started or last known good
my %watching;

# While there is still work to do, or there are still active workers
while ( @jobs || $pm->running_procs ) {

    # Check to see if any workers are finished
    $pm->reap_finished_children;

    # Check to see if any workers need to be killed because of the
    # timeout. We must do this if we've reached the limit of the number
    # of jobs we want (we wait for a slot to open up), or if we've got
    # no more work to give out.
    if ( !@jobs || $pm->running_procs >= $pm->max_procs ) {
        say sprintf "[$$] Checking jobs (%d killed, %d running, %d left)",
          $killed, scalar $pm->running_procs, scalar @jobs;
        for my $pid ( $pm->running_procs ) {
            if ( $watching{$pid} + $TIMEOUT <= time ) {

                # XXX: You can add a concern check here
                # Passed concern check, reset timeout
                # $watching{ $pid } = time;
                # Failed concern check, kill it
                say "[$$] Killed [$pid] at " . time;
                kill 'KILL', $pid;
                $killed++;
            }
        }
        sleep $TIMEOUT / 4;
        next;
    }

    # Start a new job
    my $job = shift @jobs;
    my $pid = $pm->start;

    # Parent process: Start tracking the job worker
    if ($pid) {

        # Add to the watchdog timer
        $watching{$pid} = time;
        say "[$$] Started Job#$job [$pid] at $watching{ $pid }";
        next;
    }

    # put your application code here
    # Child process: Start the job
    srand;    # Reinitialize the random number in children
    my $time = int( rand() * ( $TIMEOUT * 2 ) );
    say "[$$] Sleeping for $time";
    sleep $time;
    say "[$$] Finished!";

    $pm->finish;
}

$pm->reap_finished_children;
