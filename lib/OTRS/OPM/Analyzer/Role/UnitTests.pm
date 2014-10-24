package OTRS::OPM::Analyzer::Role::UnitTests;

# ABSTRACT: checks if the add on has unit tests

use Moose::Role;
use PPI;

with 'OTRS::OPM::Analyzer::Role::Base';

sub check {
    my ($self,$opm) = @_;
    
    my $has_unittest = 0;
    
    FILE:
    for my $file ( $opm->files ) {
        if ( $file->{filename} =~ m{ /scripts/test/ .*?\.t \z } ) {
            $has_unittest = 1;
            last FILE;
        }
    }
    
    return $has_unittest;
}

no Moose::Role;

1;

__END__

=pod

=head1 NAME

OTRS::OPM::Analyzer::Role::UnitTests - checks if the add on has unit tests

=head1 VERSION

version 0.02

=head1 AUTHOR

Renee Baecker <reneeb@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Renee Baecker.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
