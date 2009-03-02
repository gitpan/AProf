#!/usr/bin/perl

use utf8;
package AProf;

our $VERSION=0.1;

=head1 NAME

AProf - is a profiler for periodically running processes

=head1 VERSION 

0.1

=head1 SYNOPSIS

 use AProf;

 use AProf logfile => '/path/to/logfile';

 use AProf logfile => '/path/to/logfile',
            recursive => 1;

 use AProf logfile => 'STDOUT';

 use AProf logfile => 'NULL';

 my $report = AProf::full_log();

=head1 DESCRIPTION

This module is assigned for receiving statistics from periodically running
perl-programms when it is difficult to organize many test starts for them.

For using this profiler one should include into tested modules the
directive:

 use AProf;


The module will calculate the run time of each function of a tested module
and after finishing it will create a report in the B<logfile.> If the
B<logfile> isn't defined then B<STDERR> is used.

The following variants may be used as logfile:

=over

=item B<'STDOUT'> or B<'STDERR'>

To create a report in B<STDOUT> or B<STDERR> (the latter is
used on default).

=item B<'NULL'>

Not to create a report anywhere (similarly to /dev/null).

=item B<file_name>

To add a report into the file with the stated name (the main usage).

=back

You may write a report by yourself (for example if You want to keep it in
data base and not in a file). In this case You should set B<'NULL'> in the
logfile and receive a report by calling the function:

 my $report = AProf::full_log();

B<Note>: B<AProf> controls the operating time of functions included in the
module which it uses.

Other modules are not controlled. Other profiles usually allow to control
them also. In order to make AProf controlling all the used modules You
should use the option B<< recursive => 1 >> as it is shown in examples
above.

B<Note:> Remember that at recursive control the interception of some
functions is rather difficult or impossible. For example there are some
problems when setting hooks on B<AUTOLOAD> functions etc. The list of
modules and functions excluded from control can be found in the beginning
of I<AProf.pm> file in B<SKIP_MODULES> and B<SKIP_FUNCTIONS> arrays.

=head1 PROFILE FORMAT

When first writing into the file (a new report file) and also when calling
the function B<Aprof::full_log> in the very beginning there's produced two
lines of a headline with a description of the meaning of report fields. The
information is outputted into few columns:

=over

=item B<Function>

The name of the function which was controlled by the profiler.

=item B<calls>

The number of calls of the function during the whole working time.

=item B<average>

The average time needed for a single function performance.

=item B<max>

Maximum time of the performance of this function.

=item B<min>

Minimum time of the performance of this function.

=back

Before writing of a next data portion there's inserted a temporary
label like 'B<** Profiled at 2008-12-10 12:32:37 **>' into the log;
the logs' parser may use such labels for creating the diagrams of
the dependence of the function's run time from the current time,
time of the day etc.

When writing a report into the log there isn't generated a record about
those functions which have been never called during the work of the
profiler. However the function AProf::full_log includes into the report all
the controlled functions.

=head2 Parsing of logs.

For parsing logs and receiving the summary info from the profiler use the
module L<AProf::EasyParser>.

Example:
 perl -MAProf::EasyParser -e 'print aprof_report("filename.log")'

=head1 LICENSE

This profiler is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <http://www.gnu.org/licenses/>.

=head1 AUTHOR

Copyright (C) 2008 Dmitry E. Oboukhov <unera@debian.org>

=cut

use Time::HiRes qw(time);
use Fcntl ':seek', ':flock';
use Carp;

my @uses_array;

our @SKIP_MODULES =
(
    'UNIVERSAL', 'Time::HiRes',
    'B', 'Carp', 'CGI::Carp',
    'Exporter', 'Cwd', 'Config', 'CORE', 'CORE::GLOBAL',
    'DynaLoader', 'XSLoader', 'AutoLoader',
    'Errno', 'Fcntl', 'Template::Exception'
);

our @SKIP_FUNCTIONS =
(
	'DESTROY',
    'AUTOLOAD',
    'import',
);

our $DEBUG=0;

sub import
{
	my $ip=shift;
	my $package=caller;

	our $script_started;
	$script_started = Time::HiRes::time unless $script_started;

    printf STDERR "Called import 'AProf' from package $package\n\t%s\n",
        join '=>', @_ if $DEBUG;
    croak sprintf "See 'perldoc %s' for using this module", __PACKAGE__
        if scalar(@_)%2;

    my %opts=@_;
    $opts{recursive}||=0;
    $opts{recursive}=0
        if $opts{recursive} ne 1 and $opts{recursive} ne 'yes';

	push @uses_array,
	{
		caller  => [ caller ],
		import  => \%opts,
		package => $package
	};
}


# caller wrapper
sub _caller
{
	our $caller_proxy;
	my $expr=1 + shift||0;
	goto &$caller_proxy;
}

# function wrapper
sub _profile($$@)
{
	my $name=shift;
	my $code=shift;
	our %_hooks;
	our $caller_proxy;

	my ($result, @result);
	my $time_start = Time::HiRes::time;

	my $wa=wantarray;

    # if recursion is detected, statistic does not check
    my $recursion_detected=$_hooks{$name}{proc_started};
    $_hooks{$name}{proc_started}=1 unless $recursion_detected;

	eval
	{
#         local ($caller_proxy, *CORE::GLOBAL::caller)=
#         (
#             *CORE::GLOBAL::caller{CODE} || *CORE::caller{CODE},
#             \&_caller
#         ) unless defined $caller_proxy;

		if ($wa) { @result =  &$code }
	    elsif (defined $wa) { $result = &$code }
	    else { &$code }
	};

	my $time_end = Time::HiRes::time;
	my $work_time=$time_end-$time_start;

    unless($recursion_detected)
    {
        unless ($_hooks{$name}{count})
        {
    	    $_hooks{$name}{max_time}=$_hooks{$name}{min_time}=$work_time;
        }
        else
        {
    	    $_hooks{$name}{min_time}=$work_time
    	        if $work_time<$_hooks{$name}{min_time};
    	    $_hooks{$name}{max_time}=$work_time
    	        if $work_time>$_hooks{$name}{max_time};
        }

        $_hooks{$name}{sum_time} += $work_time;
        $_hooks{$name}{count}++;

        if ($DEBUG)
        {
    	    my $action=$@?'died':'called';
    	    my $type=defined($wa)?($wa?'ARRAY ':'SCALAR '):'VOID ';

            if ($wa or defined $wa)
            {
        	    printf STDERR "%s %s%s(%s) => %s\n",
        	        $action,
        	        $type,
        	        $name,
        	        join(',', @_),
        	        ($type eq 'VOID ')?'VOID':
        	            join(',', $wa?@result:
        	                defined($result)?$result:'undef');
            }
        }
        $_hooks{$name}{proc_started}=0;
    }

    die $@ if $@;
	return @result if $wa;
	return $result if defined $wa;
	return;
}

sub _set_one_hook($$$$)
{
    my ($p, $s, $c, $log)=@_;

    $log||='STDERR';
    our %_hooks;
    my $name="$p$s";

    return unless $s =~ /^[\w_][\w_\d]*$/;
    if (exists $_hooks{$name})
    {
    	push @{$_hooks{$name}{logfile}}, $log if $log;
    	return;
    }

    $_hooks{$name}=
    {
        package     => $p,
    	fname       => $name,
        code        => $c,
        count       => 0,
        max_time    => 0,
        min_time    => 0,
        sum_time    => 0,
        logfile     => [ $log?$log:() ],
    };

    no warnings 'redefine';
    no warnings 'prototype';
    no strict 'refs';

    my $is_constant=0;
    local $SIG{__WARN__}=sub { $is_constant=1 if $_[0]=~/^Constant sub/ };
    *{$name}=$c;
    unless ($is_constant)
    {
        *{$name}= sub {
        	unshift @_, $c;
        	unshift @_, $name;
        	goto &_profile;
        };
        print STDERR "Redefined function '$name' to AProf profiler\n"
            if $DEBUG;
    }
}

sub _set_hooks()
{
	for (my $i=0; $i<@uses_array; $i++)
	{
		my $use = $uses_array[$i];
        my $package=$use->{package};
        next if $package eq __PACKAGE__;
		print STDERR "Processing module $package\n" if $DEBUG;
        $package .= '::' unless $package =~ /::$/;
        no strict 'refs';
        while(my ($sym, $glob)=each %{$package})
        {
            # recursion off
            next if $sym eq $package;

            # subpackage
            if ($sym =~ /::$/)
            {
                next unless $use->{import}{recursive};
                # pragmas
                next if $sym=~/^[a-z]/ and $sym ne 'main::';

                # This profiler
                my $tp=__PACKAGE__; next if $sym=~/^$tp\::$/;

                # package_name
            	my $p=($package eq 'main::')?$sym:"$package$sym";
                $p =~ s/::$//; next unless length $p;

                next if grep { $p eq $_ } @SKIP_MODULES;
                next if grep {
                    $_->{package} eq $p and
                    $_->{import}{recursive} eq $use->{import}{recursive}
                } @uses_array;
            	push @uses_array,
            	{
		            caller  => $use->{caller},
		            import  => $use->{import},
		            package => $p,
            	};

            	print STDERR "Package $p added to profiler list\n" if $DEBUG;
            	next;
            }
            next if grep { $sym eq $_ } @SKIP_FUNCTIONS;
            next if ref $glob or !$glob;
            my $code = *{$glob}{CODE};
            next unless $code;
            next unless 'CODE' eq ref $code;
            _set_one_hook $package, $sym, $code, $use->{import}{logfile};
        }
	}
}

sub _get_log_header()
{
	return sprintf "%-30s  %6s  %12s  %12s  %12s\n%s\n",
	    "Function", "calls", "average", "max", "min", "-"x 80;
}

sub _get_profiled_time_log_header()
{
	our $script_started;
    my @lt=localtime; $lt[4]++; $lt[5]+=1900;
    my $work_time = sprintf '%1.10f', Time::HiRes::time -  $script_started;
    my $curr_time = sprintf '%04d-%02d-%02d %02d:%02d:%02d', @lt[reverse 0 .. 5];

    return sprintf "%70s\n%-30s  %6s  %.12s  %.12s  %.12s\n",
        "** Profiled at $curr_time ** ",
        "[$0]", 1, ($work_time)x 3;
}

sub _get_one_log_line($)
{
	my $log=shift;
    my $average = 0;
    $average = $log->{sum_time}/$log->{count} if $log->{count};
    return sprintf "%-30s  %6d" . "  %.12s"x 3 . "\n",
    	$log->{fname},
    	$log->{count},
    	map { sprintf "%1.10f", $_ }
    	    $average,
    	    $log->{max_time},
            $log->{min_time};
}

sub full_log()
{
	our %_hooks;
	my $report = _get_log_header;
	$report   .= _get_profiled_time_log_header;
	for my $log(sort { $b->{sum_time} <=> $a->{sum_time} } values %_hooks)
	{
        $report .= _get_one_log_line $log;
	}
	return $report;
}

sub _savelog()
{
	our $already_saved;
	return if $already_saved;
    our %_hooks;
    my %lp;
	$already_saved=1;

    LOG: for my $log(sort { $b->{sum_time} <=> $a->{sum_time} } values %_hooks)
    {
    	for my $logname (@{$log->{logfile}})
    	{
    		next unless $log->{count};
    	    my $fo;
    	    unless (exists $lp{$logname})
    	    {
    		    my $file_logging;
                if ($logname eq 'STDERR')
                {
            	    $fo=\*STDERR;
                }
                elsif($logname eq 'STDOUT')
                {
            	    $fo=\*STDOUT;
                }
                elsif($logname eq 'NULL')
                {
            	    next LOG;
                }
                else
                {
                    $file_logging=1 if -f $logname;
            	    unless (open $fo, '>>', $logname)
            	    {
            	        carp "Can not append file '$logname': $!\n";
            	    }
                }
                $lp{$logname}={fh => $fo, is_file=>$file_logging};

                printf $fo _get_log_header unless $file_logging;
                printf $fo _get_profiled_time_log_header;
    	    }
    	    else
    	    {
    	        $fo=$lp{$logname}{fh};
    	    }
    	    if ($lp{$logname}{is_file})
    	    {
    	    	flock $lp{$logname}{fh}, LOCK_EX;
    	    	seek $lp{$logname}{fh}, 0, SEEK_END;
    	    }
    	    printf $fo _get_one_log_line $log;
            flock $lp{$logname}{fh}, LOCK_UN if $lp{$logname}{is_file};
    	}
    }
}

INIT { _set_hooks; }
END { _savelog; }

1;
