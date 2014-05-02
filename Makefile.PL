
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;

use File::ShareDir::Install;
install_share dist => "conf";


my %WriteMakefileArgs = (
  "ABSTRACT" => "Analyze OTRS add-ons (.opm files)",
  "AUTHOR" => "Renee Baecker <reneeb\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30",
    "File::ShareDir::Install" => "0.03"
  },
  "DISTNAME" => "OTRS-OPM-Analyzer",
  "EXE_FILES" => [
    "bin/opm_analyzer_test.pl",
    "bin/validate_opms.pl",
    "bin/de_opm.pl",
    "bin/opm_analyzer_test.pl",
    "bin/validate_opms.pl",
    "bin/de_opm.pl"
  ],
  "LICENSE" => "artistic_2",
  "NAME" => "OTRS::OPM::Analyzer",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Data::Dumper" => 0,
    "File::Basename" => 0,
    "File::Find::Rule" => 0,
    "File::Path" => 0,
    "File::Spec" => 0,
    "File::Temp" => 0,
    "FindBin" => 0,
    "HTML::Lint" => 0,
    "LWP::Simple" => 0,
    "MIME::Base64" => 0,
    "Module::CoreList" => 0,
    "Module::OTRS::CoreList" => 0,
    "Moose" => 0,
    "Moose::Role" => 0,
    "PPI" => 0,
    "Path::Class" => 0,
    "Perl::Critic" => 0,
    "Perl::Tidy" => 0,
    "Software::License" => 0,
    "Software::LicenseUtils" => 0,
    "Test::Exception" => 0,
    "Test::More" => 0,
    "Text::Diff" => 0,
    "Try::Tiny" => 0,
    "XML::LibXML" => 0,
    "YAML::Tiny" => 0
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "0.02",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);

{
package
MY;
use File::ShareDir::Install qw(postamble);
}


