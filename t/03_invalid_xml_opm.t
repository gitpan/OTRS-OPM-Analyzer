#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use OTRS::OPM::Analyzer::Utils::OPMFile;

use File::Basename;
use File::Spec;

my $opm_file = File::Spec->catfile( dirname(__FILE__), 'data', 'QuickMergeInvalid-3.3.2.opm' );
my $opm      = OTRS::OPM::Analyzer::Utils::OPMFile->new( opm_file => $opm_file );

isa_ok $opm, 'OTRS::OPM::Analyzer::Utils::OPMFile';

$opm->parse;

like $opm->error_string, qr/Could not parse .opm/ms, 'error_string';

done_testing();

