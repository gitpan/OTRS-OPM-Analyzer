package OTRS::OPM::Analyzer::Utils::OPMFile;

# ABSTRACT: Parser for the .opm file

use Moose;
use Moose::Util::TypeConstraints;

use MIME::Base64 ();
use Path::Class;
use Try::Tiny;
use XML::LibXML;

# define types
subtype 'VersionString' =>
  as 'Str' =>
  where { $_ =~ m{ \A (?:[0-9]+) (?:\.[0-9]+){0,2} (?:_\d+)? \z }xms };

subtype 'FrameworkVersionString' =>
  as 'Str' =>
  where { $_ =~ m{ \A (?: (?:x|[0-9]+x?) \. ){2} (?: x | [0-9]+x? ) \z }xms };

subtype 'XMLTree' =>
  as 'Object' =>
  where { $_->isa( 'XML::LibXML::Document' ) };

# declare attributes
has name         => ( is  => 'rw', isa => 'Str', );
has version      => ( is  => 'rw', isa => 'VersionString', );
has vendor       => ( is  => 'rw', isa => 'Str', );
has url          => ( is  => 'rw', isa => 'Str', );
has license      => ( is  => 'rw', isa => 'Str', );
has description  => ( is  => 'rw', isa => 'Str', );
has error_string => ( is  => 'rw', isa => 'Str', );

has tree => (
    is       => 'rw',
    isa      => 'XMLTree',
);

has opm_file => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has files => (
    traits     => ['Array'],
    is         => 'rw',
    isa        => 'ArrayRef[HashRef]',
    auto_deref => 1,
    default    => sub{ [] },
    handles    => {
        add_file => 'push',
    },
);

has framework  => (
    traits     => ['Array'],
    is         => 'rw',
    isa        => 'ArrayRef[FrameworkVersionString]',
    auto_deref => 1,
    default    => sub { [] },
    handles    => {
        add_framework => 'push',
    },
);

has dependencies => (
    traits     => ['Array'],
    is         => 'rw',
    isa        => 'ArrayRef[HashRef[Str]]',
    auto_deref => 1,
    default    => sub { [] },
    handles    => {
        add_dependency => 'push',
    },
);


sub documentation {
    my ($self,%params) = @_;
    
    my $doc_file;
    my $found_file;
    
    for my $file ( $self->files ) {
        my $filename = $file->{filename};
        next if $filename !~ m{ \A doc/ }x;
        
        if ( !$doc_file ) {
            $doc_file   = $file;
            $found_file = $filename;
        }
        
        my $lang = $params{lang} || '';
        next if $lang && $filename !~ m{ \A doc/$lang/ }x;
        
        if ( $lang && $found_file !~ m{ \A doc/$lang/ }x ) {
            $doc_file   = $file;
            $found_file = $filename;
        }
        
        my $type = $params{type} || '';
        next if $type && $filename !~ m{ \A doc/[^/]+/.*\.$type \z }x;
        
        if ( $type && $found_file !~ m{ \A doc/$lang/ }x ) {
            $doc_file   = $file;
            $found_file = $filename;
            
            if ( !$lang || ( $lang && $found_file !~ m{ \A doc/$lang/ }x ) ) {                
                last;
            }
        }
    }
    
    return $doc_file;
}

sub parse {
    my ($self) = @_;

    $self->error_string( '' );
    
    if ( !-e $self->opm_file ) {
        $self->error_string( 'File does not exist' );
        return;
    }
   
    my $tree;
    try {
        my $parser = XML::LibXML->new;
        $tree      = $parser->parse_file( $self->opm_file );

        $self->tree( $tree );
    }
    catch {
        $self->error_string( 'Could not parse .opm: ' . $_ );
        return;
    };

    return if $self->error_string;
    
    # check if the opm file is valid.
    try {
        my $xsd = do{ local $/; <DATA> };
        XML::LibXML::Schema->new( string => $xsd )
    }
    catch {
        $self->error_string( 'Could not validate against XML schema: ' . $_ );
        #return;
    };
    
    my $root = $tree->getDocumentElement;
    
    # collect basic data
    $self->vendor(    $root->findvalue( 'Vendor' ) );
    $self->name(      $root->findvalue( 'Name' ) );
    $self->license(   $root->findvalue( 'License' ) );
    $self->version(   $root->findvalue( 'Version' ) );
    $self->url(       $root->findvalue( 'URL' ) );
    
    # retrieve framework information
    my @frameworks = $root->findnodes( 'Framework' );
    
    FILE:
    for my $framework ( @frameworks ) {
        my $framework_version = $framework->textContent;
        
        # push framework info to attribute
        $self->add_framework( $framework_version );
    }

    # retrieve file information
    my @files = $root->findnodes( 'Filelist/File' );
    
    FILE:
    for my $file ( @files ) {
        my $name = $file->findvalue( '@Location' );
        
        #next FILE if $name !~ m{ \. (?:pl|pm|pod|t) \z }xms;
        my $encode         = $file->findvalue( '@Encode' );
        next FILE if $encode ne 'Base64';
        
        my $content_base64 = $file->textContent;
        my $content        = MIME::Base64::decode( $content_base64 );
        
        # push file info to attribute
        $self->add_file({
            filename => $name,
            content  => $content,
        });
    }
    
    # get description - english if available, any other language otherwise
    my @descriptions = $root->findnodes( 'Description' );
    my $description_string;
    
    DESCRIPTION:
    for my $description ( @descriptions ) {
        $description_string = $description->textContent;
        my $language        = $description->findvalue( '@Lang' );
        
        last DESCRIPTION if $language eq 'en';
    }
    
    $self->description( $description_string );
    
    # get OTRS and CPAN dependencies
    my @otrs_deps = $root->findnodes( 'PackageRequired' );
    my @cpan_deps = $root->findnodes( 'ModuleRequired' );
    
    my %types     = (
        PackageRequired => 'OTRS',
        ModuleRequired  => 'CPAN',
    );
    
    for my $dep ( @otrs_deps, @cpan_deps ) {
        my $node_type = $dep->nodeName;
        my $version   = $dep->findvalue( '@Version' );
        my $dep_name  = $dep->textContent;
        my $dep_type  = $types{$node_type};
        
        $self->add_dependency({
            type    => $dep_type,
            version => $version,
            name    => $dep_name,
        });
    }
    
    return 1;
}

sub as_sopm {
    my ($self) = @_;

    my $tree = $self->tree->cloneNode(1);
    my $root = $tree->getDocumentElement;
    
    my @build_host = $root->findnodes( 'BuildHost' );
    my @build_date = $root->findnodes( 'BuildDate' );
    
    $root->removeChild( $_ ) for @build_host;
    $root->removeChild( $_ ) for @build_date;

    #$build_host->unbindNode() if $build_host;
    #$build_date->unbindNode() if $build_date;
    
    my @files = $root->findnodes( 'Filelist/File' );
    for my $file ( @files ) {
        my ($encode) = $file->findnodes( '@Encode' );
        $encode->unbindNode() if $encode;
    
        $file->removeChildNodes();
    }
    
    return $tree->toString;
}

no Moose;

1;

=pod

=head1 NAME

OTRS::OPM::Analyzer::Utils::OPMFile - Parser for the .opm file

=head1 VERSION

version 0.03

=head1 SYNOPSIS

=head1 METHODS

=head2 new

=head2 parse

=head2 as_sopm

=head2 documentation

=head1 ATTRIBUTES

=over 4

=item * opm_file

=item * tree

=item * framework

=item * dependencies

=item * files

=item * error_string

=item * description

=item * license

=item * url

=item * vendor

=item * version

=item * name

=back

=head1 AUTHOR

Renee Baecker <reneeb@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Renee Baecker.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut

__DATA__
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" elementFormDefault="qualified">
    <xs:import namespace="http://www.w3.org/XML/1998/namespace"/>
    
    <xs:element name="otrs_package">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="Name" minOccurs="1" maxOccurs="1"/>
                <xs:element ref="Version"/>
                <xs:element ref="Vendor"/>
                <xs:element ref="URL"/>
                <xs:element ref="License"/>
                <xs:element ref="ChangeLog" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="Description" maxOccurs="unbounded" />
                <xs:element ref="Framework" maxOccurs="unbounded" />
                <xs:element ref="OS" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IntroInstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IntroUninstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IntroReinstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IntroUpgrade" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="PackageRequired" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="ModuleRequired" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="CodeInstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="CodeUpgrade" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="CodeUninstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="CodeReinstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="BuildDate" minOccurs="0" />
                <xs:element ref="BuildHost" minOccurs="0" />
                <xs:element ref="Filelist"/>
                <xs:element ref="DatabaseInstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="DatabaseUpgrade" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="DatabaseReinstall" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="DatabaseUninstall" minOccurs="0" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="version" use="required" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="ChangeLog">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Date" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Version" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="Description">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Lang" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Format" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Translatable" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="Filelist">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="File" maxOccurs="unbounded" />
            </xs:sequence>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="File">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Location" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Permission" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Encode" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="PackageRequired">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Version" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="ModuleRequired">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Version" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="IntroInstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Lang" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Title" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Translatable" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Format" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="IntroUninstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Lang" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Title" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Translatable" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Format" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="IntroReinstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Lang" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Title" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Translatable" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Format" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="IntroUpgrade">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Lang" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Title" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Translatable" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Format" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="CodeInstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="CodeUninstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="CodeReinstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="CodeUpgrade">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="Name" type="xs:token"/>
    <xs:element name="Vendor" type="xs:token"/>
    <xs:element name="URL" type="xs:token"/>
    <xs:element name="Framework" type="xs:token"/>
    <xs:element name="Version" type="xs:token"/>
    <xs:element name="License" type="xs:token"/>
    <xs:element name="OS" type="xs:token"/>
    <xs:element name="BuildDate" type="xs:token"/>
    <xs:element name="BuildHost" type="xs:token"/>
    
    
    <!--                -->
    <!-- Database stuff -->
    <!--                -->
    
    <xs:element name="DatabaseInstall">
        <xs:complexType>
            <xs:choice maxOccurs="unbounded">
                <xs:element ref="TableCreate" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="TableAlter" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="Insert" minOccurs="0" maxOccurs="unbounded" />
            </xs:choice>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    <xs:element name="DatabaseUninstall">
        <xs:complexType>
            <xs:choice maxOccurs="unbounded">
                <xs:element ref="TableDrop" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="TableAlter" minOccurs="0" maxOccurs="unbounded" />
            </xs:choice>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    <xs:element name="DatabaseReinstall">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="DatabaseUpgrade">
        <xs:complexType>
            <xs:choice maxOccurs="unbounded">
                <xs:element ref="TableCreate" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="TableAlter" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="Insert" minOccurs="0" maxOccurs="unbounded" />
            </xs:choice>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="TableCreate">
        <xs:complexType>
            <xs:choice maxOccurs="unbounded">
                <xs:element ref="Column" maxOccurs="unbounded" />
                <xs:element ref="ForeignKey" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="Index" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="Unique" minOccurs="0" maxOccurs="unbounded" />
            </xs:choice>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Name" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="TableAlter">
        <xs:complexType>
            <xs:choice maxOccurs="unbounded">
                <xs:element ref="ColumnAdd" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="ColumnChange" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="ColumnDrop" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="ForeignKeyCreate" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="ForeignKeyDrop" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IndexCreate" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="IndexDrop" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="UniqueCreate" minOccurs="0" maxOccurs="unbounded" />
                <xs:element ref="UniqueDrop" minOccurs="0" maxOccurs="unbounded" />
            </xs:choice>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Name" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="TableDrop">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <!-- Columns -->
    
    <xs:element name="Column">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="AutoIncrement" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Required" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Size" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="PrimaryKey" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Default" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="ColumnAdd">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="AutoIncrement" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Required" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Size" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="PrimaryKey" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Default" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="ColumnChange">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Default" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="NameOld" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="NameNew" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="AutoIncrement" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Required" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Size" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="PrimaryKey" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    <xs:element name="ColumnDrop">
        <xs:complexType>
            <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <!-- Foreign Keys -->
    
    <xs:element name="ForeignKey">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="Reference" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="ForeignTable" use="required" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="ForeignKeyCreate">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="Reference" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="ForeignTable" use="required" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="ForeignKeyDrop">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="Reference" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="ForeignTable" use="required" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="Reference">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Local" use="required" type="xs:anySimpleType"/>
                    <xs:attribute name="Foreign" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <!-- Unique columns -->
    
    <xs:element name="Unique">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="UniqueColumn" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="Name" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="UniqueColumn">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="UniqueCreate">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="UniqueDrop">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <!-- Index columns -->
    
    <xs:element name="Index">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="IndexColumn" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="Name" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="IndexColumn">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="IndexCreate">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="IndexDrop">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Name" use="required" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
    <!-- Insert stuff into database -->
    
    <xs:element name="Insert">
        <xs:complexType>
            <xs:sequence>
                <xs:element ref="Data" maxOccurs="unbounded" />
            </xs:sequence>
            <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
            <xs:attribute name="Table" use="required" type="xs:anySimpleType"/>
            <xs:attribute name="Version" use="optional" type="xs:anySimpleType"/>
        </xs:complexType>
    </xs:element>
    
    <xs:element name="Data">
        <xs:complexType>
            <xs:simpleContent>
                <xs:extension base="xs:string">
                    <xs:attribute name="Key" use="optional" type="xs:anySimpleType"/>
                    <xs:attribute name="Type" use="optional" type="xs:anySimpleType"/>
                </xs:extension>
            </xs:simpleContent>
        </xs:complexType>
    </xs:element>
    
</xs:schema>
