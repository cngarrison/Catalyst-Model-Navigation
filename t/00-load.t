#!perl -wT

use strict;
use warnings;

use Test::More tests => 1;

use_ok( 'Catalyst::Model::Navigation' );

diag( 'Testing Catalyst::Model::Navigation '
            . $Catalyst::Model::Navigation::VERSION );
