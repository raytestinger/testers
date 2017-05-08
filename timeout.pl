#!/usr/bin/perl

use v5.10;
use Parallel::ForkManager;

my $TIMEOUT = 10;    # How long a child is running before it should be killed
my $pm   = Parallel::ForkManager->new(5);    # 5 max workers
my @jobs = 1 .. 20;                          # How many fake jobs to run
my %watching;
while ( @jobs || $pm->running_procs ) {
    $pm->reap_finished_children;
    if ( $pm->running_procs >= $pm->max_procs || !@jobs ) {
        say sprintf "[%5s] %2s: Checking jobs (%d running, %d left)", '-----',
          '--', scalar $pm->running_procs, scalar @jobs;
        for my $pid ( $pm->running_procs ) {
            if ( $watching{$pid}{time} + $TIMEOUT < time ) {
                kill 'KILL', $pid;
                say sprintf "[%5d] %2d: Killed at %d", $pid,
                  $watching{$pid}{job}, time;
            }
        }
        sleep $TIMEOUT * 0.25;
        next;
    }
    my $job = shift @jobs;
    my $pid = $pm->start;
    if ($pid) {
        $watching{$pid}{time} = time;
        $watching{$pid}{job}  = $job;
        next;
    }
    say sprintf "[%5d] %2d: Started Job at %d", $$, $job, time;
    srand;    # Reinitialize the random number in children
    my $time = int( rand() * ( $TIMEOUT * 2 ) );
    say sprintf "[%5d] %2d: Sleeping for %d", $$, $job, $time;
    sleep $time;
    say sprintf "[%5d] %2d: Finished!", $$, $job;
    $pm->finish;
}
$pm->reap_finished_children;
