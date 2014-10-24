package OTRS::OPM::Analyzer::Role::BasicXMLCheck;

use Moose::Role;
use XML::LibXML;

with 'OTRS::OPM::Analyzer::Role::Base';

sub check {
    my ( $self, $document ) = @_;
    
    return if $document->{filename} !~ m{ \.xml \z }xms;
    
    my $content = $document->{content};    
    my $check_result = '';
    
    eval {
        my $parser = XML::LibXML->new;
        $parser->parse_string( $content );
    } or $check_result = $@;
    
    return $check_result;
}

no Moose::Role;

1;

__END__

=pod

=head1 NAME

OTRS::OPM::Analyzer::Role::BasicXMLCheck

=head1 VERSION

version 0.01

=head1 AUTHOR

Renee Baecker <reneeb@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Renee Baecker.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
