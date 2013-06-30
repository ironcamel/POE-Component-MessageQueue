
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "A Perl message queue based on POE that uses STOMP as its communication protocol.",
  "AUTHOR" => "David Snopek (http://www.hackyourlife.org), Paul Driver <frodwith\@gmail.com>, Daisuke Maki <daisuke\@endeworks.jp>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "POE-Component-MessageQueue",
  "EXE_FILES" => [
    "bin/mq.pl"
  ],
  "LICENSE" => "perl",
  "NAME" => "POE::Component::MessageQueue",
  "PREREQ_PM" => {
    "Best" => 0,
    "Carp" => 0,
    "DBD::SQLite" => "1.13",
    "DBI" => 0,
    "Data::Dumper" => 0,
    "Data::UUID" => 0,
    "Event::Notify" => 0,
    "Exception::Class::DBI" => 0,
    "Exception::Class::TryCatch" => 0,
    "File::Temp" => 0,
    "Heap" => "0.80",
    "Heap::Fibonacci" => "0.80",
    "IO::File" => 0,
    "IO::String" => 0,
    "Moose" => "2.0201",
    "MooseX::AttributeHelpers" => "0.08",
    "MooseX::MultiInitArg" => 0,
    "Net::Stomp" => 0,
    "POE" => "0.38",
    "POE::Component::Generic" => "0.1001",
    "POE::Component::Logger" => 0,
    "POE::Component::Server::TCP" => 0,
    "POE::Filter::Stomp" => "0.04",
    "POE::Wheel::ReadWrite" => 0,
    "Test::Exception" => 0,
    "Test::MockObject" => 0,
    "Test::More" => 0,
    "YAML" => 0
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "0.2.14",
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



