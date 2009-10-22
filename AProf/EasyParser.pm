#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use open qw(:std :utf8);

use utf8;
package AProf::EasyParser;
use base qw(Exporter);
use Carp;

our $VERSION=0.6;
our @EXPORT=qw(aprof_report aprof_report_array);


my %sortby_variants = 
(
    function    => "Function",
    calls       => "Calls",
    average     => "Average time",
    total       => "Total time",
    max         => "Max time",
    min         => "Min time"
);

sub aprof_report_array
{
    my $file=shift;
    my $sortby=shift||'total';
    $sortby='total' unless exists $sortby_variants{$sortby};
    
    croak "Usage: aprof_report('file_name.log')" unless defined $file;
    croak "File $file not found" unless -f $file;
    open my $fh, '<', $file or croak "Can not read '$file': $!";
    my @rlines=map { chomp; s/\s+/ /g; $_ } <$fh>;
    my @data=
        map { 
            $_=[split / /];
            {
                function    =>      $$_[0],
                calls       =>      $$_[1],
                average     =>      $$_[2],
                max         =>      $$_[3],
                min         =>      $$_[4],
                total       =>      $$_[2]*$$_[1]
            }
        } grep /^\S+ \d+(?: \d+\.\d+){3}$/, @rlines;
    return undef unless @data;

    my %report;
    my $i=0;
    
    for my $log(@data)
    {
        $i++;
        next unless $log->{calls};
        my $foo=$log->{function};
        if (exists $report{$foo})
        {
            $report{$foo}{calls}+=$log->{calls};
            $report{$foo}{total}+=$log->{total};
            $report{$foo}{average}=$report{$foo}{total}/$report{$foo}{calls};
            $report{$foo}{max}=$log->{max} if $report{$foo}{max}<$log->{max};
            $report{$foo}{min}=$log->{min} if $report{$foo}{min}>$log->{min};
            next;
        }
        $report{$foo}={ %$log };
    }

    my $profiled_count=grep
        /\*\* Profiled at \d{4}-\d\d-\d\d \d\d(?::\d\d){2} \*\*/,
        @rlines;
    
    return 
    {
        src    => \@rlines,
        pcount => $profiled_count,
        report => [ sort { $a->{function} cmp $b->{function} } values %report ]
    } if $sortby eq 'function';
    return
    {
        src     => \@rlines,
        pcount  => $profiled_count,
        report  => [ sort { $b->{$sortby} <=> $a->{$sortby} } values %report ]
    };
}

sub aprof_report
{
    my $file=shift;
    my $sortby=shift||'total';
    $sortby='total' unless exists $sortby_variants{$sortby};

    my $r=aprof_report_array $file, $sortby;
    return '' unless defined $r;

    my $report=sprintf " ** AProf profiler the results **\n\n" .
        "total starts: %d\n   sorted by: '%s'\n\n".
        "-"x 80 . "\n".
        "%-22s %5s" . " %12s"x 4 . "\n" .
        "-"x 80 . "\n",
            $$r{pcount},
            $sortby_variants{$sortby},
            map { $sortby_variants{$_} } 
            qw(function calls total average max min);

    for (@{$r->{report}})
    {
        $report .= sprintf "%-22s %5d"." %.12s"x 4 . "\n",
            $$_{function},
            $$_{calls},
            map { sprintf "%.10f", $_ }
                $$_{total},
                $$_{average},
                $$_{max},
                $$_{min};
    }
    return $report;
}

1;
