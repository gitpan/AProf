#!/usr/bin/perl

use warnings;
use strict;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                =>  'AProf',
    AUTHOR              => 'Dmitry E. Oboukhov <unera@debian.org>',
    VERSION_FROM        => './AProf.pm',
    ABSTRACT_FROM       => './AProf.pm',
    NO_META             => 0,
);
