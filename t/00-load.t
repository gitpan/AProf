#!perl

use Test::More tests => 2;

BEGIN {
	use_ok( 'AProf', logfile    => 'NULL' );
	use_ok( 'AProf::EasyParser' );
}

diag( "Testing AProf $AProf::VERSION, Perl $], $^X" );
