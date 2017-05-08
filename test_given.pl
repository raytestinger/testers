#!/usr/bin/env perl

#use v5.10;

my %functions = (
current => \&do_current,
list => \&do_list,
smoker => \&do_smoker,
);

foreach my $function ('current', 'list', 'smoker') {
my $do_function = $functions{$function};
$do_function->();
}

sub do_current {
    say "doing current";
}

sub do_list {
    say "doing list";
}

sub do_smoker {
    say "doing smoker";
}
