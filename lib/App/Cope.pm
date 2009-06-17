#!/usr/bin/env perl
package App::Cope;
use strict;
use warnings;
use 5.010_000;
use Carp;

use base 'Exporter';
our @EXPORT = qw[run mark line new_path];
our @EXPORT_OK = qw[get colourise];

our $VERSION = '0.99';

=head1 NAME

App::Cope - Functions for the cope program

=head1 SYNOPSIS

This file contains functions for F<cope>, and documentation of what
they do. If you want to learn how to use cope itself, see
App::Cope::Manual instead.

=cut

use App::Cope::Pty;

use IO::Handle;
use Term::ANSIColor;
use List::MoreUtils 'each_array';
use File::Spec;

=head1 DESCRIPTION

Rather embarrassingly, the technique for highlighting parts of a
string is used by modifying global variables. The process works
something like this:

1) Cope gets a string from a program's output.

2) The line and mark functions match against the string, now in C<$_>,
   and modify the hash C<%colours> at the start and end positions of
   the match with ANSI control codes to turn the colours on and off.

3) The string is colourised, and the control-code-laden string is
   printed as output.

Previously, the two functions modified C<$_> throughout, but then it
was impossible to match against an already-coloured part of the
string, as the control codes would get in the way.

=head1 MAIN FUNCTIONS

=head2 run( \&process )

=cut

our %colours;

sub run {
  my ( $process, @args ) = @_;
  croak "No arguments" unless @args;

  # don't run if told not to
  if ($ENV{NOCOPE} or not POSIX::isatty STDOUT) {
    exec @args;
  }

  # handle
  my $fh = new IO::Handle or croak "Failed handle: $!";
  $fh->fdopen( fileno STDIN, 'r' );
  $fh->autoflush;

  # pty
  my $pty = App::Cope::Pty->new;
  $pty->spawn( @args );

  # no suffering from buffering
  local $| = 1;

  while ( my $rout = $pty->read ) {
    my @bits = split /(\r|\n)/, $rout;
    print colourise( $process, $_ ) for @bits;
  }

  $fh->close  or carp "Failed close: $!";
  $pty->close or carp "Failed close: $!";
}

=head2 mark( $regexp, $colour )

The simpler of the highlighting functions; C<mark> takes a regex, and
one colour, and highlights the first part of the string matched in the
given colour.

  mark qr{open} => 'green bold';

=cut

sub mark {
  my ( $regex, $colour ) = @_;
  if (m/$regex/) {
    colour( $-[0], $+[0] => get( $colour, $& ) );
  }
}

=head2 line( $regexp, @colours )

The more complicated function; C<line> takes a regex, containing
parenthesised captures, and highlights each match with the relevant
colour in the array.

  line qr{^(\d+){/\w+)} => 'cyan bold', 'blue';

=cut

sub line {
  my $regexp = shift;

  my $offset = 0;
  while ( substr( $_, $offset ) =~ $regexp ) {

    # skip 0th entries - they just contain info about the entire match
    my @starts   = @-[ 1 .. $#- ];
    my @ends     = @+[ 1 .. $#+ ];
    my @colours  = @_;

    my $ea = each_array( @starts, @ends, @colours );
    while ( my ( $start, $end, $colour ) = $ea->() ) {

      # either $start or $end being undef means that there was nothing to
      # match, e.g. /(?: (\S+) )?/x where the match fails.
      if ( defined $start and defined $end ) {
	my $ss = $offset + $start;
	my $ee = $offset + $end;

        my $before = substr $_, $ss, $end - $start;
	my $c = get( $colour, $before );
	colour( $ss, $ee => $c );
      }
    }

    $offset += $+[0]; # mark everything up to here as done
  }

  return $offset; # still false if nothing's changed
}

=head1 HELPER FUNCTIONS

=head2 get( $colour, $str );

Returns a colour based on how a reference - an array, a hash, some
code, or just a scalar string - reacts to the text matched by a
regex. Used by C<mark> and C<line>.

  # simple scalar usage
  line qr/^Count: (\d+)/ => 'green';

  # passing a subroutine
  line qr/^Errors: (\d+)/ => sub {
    return 'red' if shift > 0;
  }

  # passing a hashref
  my %protocols = (
    'tcp' => 'magenta',
    'udp' => 'red',
    'raw' => 'red bold',
  );
  line qr/^\d+/(\w+)/ => \%protocols;

=cut

sub get {
  my ( $colour, $str ) = @_;
  given ( ref $colour ) {
    when ('ARRAY') { return get( shift @{$colour}, $str ) || ''; }
    when ('HASH')  { return get( $colour->{$str},  $str ) || ''; }
    when ('CODE')  { return get( &$colour($str),   $str ) || ''; }
    default        { return $colour; };
  }
}

=head2 colour( $begin, $end, $colour )

B<Modifies> the hash C<%colours>, in order to highlight the region
from $begin to $end in $colour.

=cut

sub colour {
  my ( $begin, $end, $colour ) = @_;
  $colours{$begin} = $colour;
  $colours{$end}   = '';
}

=head2 colourise

Uses the values in the hash C<%colours> to transform the string in
C<$_> to a colourised version of itself. This string is eventually
printed to stdout.

=cut

sub colourise(&$) {
  my $process = shift;
  $_ = shift;

  %colours = ();
  &$process if $_ ne "\n";

  for my $i ( sort { $b <=> $a } keys %colours ) {
    substr $_, $i, 0, color( $colours{$i} || 'reset' );
  }

  return $_;
}

=head2 new_path

Returns a new value for $ENV{PATH}, with the scripts directory
omitted, and the name of the executable to run in the new path.

=cut

sub new_path {
  my ( $vol, $dirs, $file ) = File::Spec->splitpath( $0 );
  $dirs =~ s{/$}{};

  my $path = $ENV{PATH};
  $path =~ s{^$dirs:}{};

  return ( $file, $path );
}

1;

__END__

=head1 AUTHOR

Benjamin Sago aka `cytzol' C<< <ben&cytzol,org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Benjamin Sago.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 70;
#   indent-tabs-mode: nil
# End:
# vi: set ts=2 sts=2 sw=2 tw=70 et