#!/usr/bin/perl



for ($! = 1; $! <= 10000; $!++) {
    $errText = $!;
    chomp($errText);
    printf("%04d: %s\n", $!, $errText) if $! ne "Unknown Error";
}
