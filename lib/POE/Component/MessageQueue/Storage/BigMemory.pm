#
# Copyright 2007, 2008 Paul Driver <frodwith@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

package POE::Component::MessageQueue::Storage::BigMemory::MessageElement;
use Heap::Elem;
use base qw(Heap::Elem);

sub new
{
	my ($class, $message) = @_;
	my $self = $class->SUPER::new;

	$self->val($message);	
	bless($self, $class);
}

sub cmp
{
	my ($self, $other) = @_;
	return $self->val->timestamp <=> $other->val->timestamp;
}

1;

package POE::Component::MessageQueue::Storage::BigMemory;
use Moose;
with qw(POE::Component::MessageQueue::Storage);

use Heap::Fibonacci;

use constant empty_hashref => (is => 'ro', default => sub { {} });

# claimer_id => heap element
has 'claimed'   => empty_hashref;
# queue_name => heap of messages
has 'unclaimed' => empty_hashref;
# message_id => info hash
has 'messages'  => empty_hashref;

has 'message_heap' => (
	is      => 'rw',
	default => sub { Heap::Fibonacci->new },
);

# Where messages are stored:
#   -- A heap of all unclaimed messages sorted by timestamp
#   -- Per destination heaps for unclaimed messages
#   -- A hash of claimant => messages.
#
# There is also a hash of ids to info about heap elements and such.

sub _make_heap_elem
{
	POE::Component::MessageQueue::Storage::BigMemory::MessageElement->new(@_);
}

sub store
{
	my ($self, $msg, $callback) = @_;

	my $elem = _make_heap_elem($msg);
	my $main = _make_heap_elem($msg);
	$self->message_heap->add($main);

	my $info = $self->messages->{$msg->id} = {
		message => $msg,
		main    => $main,
	};

	if ($msg->claimed) 
	{
		$self->claimed->{$msg->claimant}->{$msg->destination} = $elem;
	}
	else
	{
		my $heap = 
			($self->unclaimed->{$msg->destination} ||= Heap::Fibonacci->new);
		$heap->add($elem);
		$info->{unclaimed} = $elem;
	}

	my $id = $msg->id;
	$self->log(info => "Added $id.");
	goto $callback if $callback;
}

sub get
{
	my ($self, $ids, $callback) = @_;
	@_ = ([map $_->{message}, grep $_,
	       map $self->messages->{$_}, @$ids]);
	goto $callback;
}

sub get_all
{
	my ($self, $callback) = @_;
	@_ = ([map $_->{message}, values %{$self->messages}]);
	goto $callback;
}

sub get_oldest
{
	my ($self, $callback) = @_;
	my $top = $self->message_heap->top;
	@_ = ($top && $top->val);
	goto $callback;
}

sub claim_and_retrieve
{
	my ($self, $destination, $client_id, $callback) = @_;
	my $message;
	my $heap = $self->unclaimed->{$destination};
	if ($heap)
	{
		my $top = $heap->top;
		$message = $top->val if $top;
		$self->claim($message->id, $client_id) if $message;
	}
	@_ = ($message);
	goto $callback;
}

sub remove
{
	my ($self, $ids, $callback) = @_;

	foreach my $id (@$ids)
	{
		my $info = delete $self->messages->{$id};
		next unless $info && $info->{message};
		my $msg = $info->{message};

		$self->message_heap->delete($info->{main});
		if ($msg->claimed)
		{
			delete $self->claimed->{$msg->claimant}->{$msg->destination};
		}
		else
		{
			$self->unclaimed->{$msg->destination}->delete($info->{unclaimed});
		}
	}

	goto $callback if $callback;
}

sub empty 
{
	my ($self, $callback) = @_;

	%{$self->$_} = () foreach qw(messages claimed unclaimed);
	$self->message_heap(Heap::Fibonacci->new);
	goto $callback if $callback;
}

sub claim
{
	my ($self, $ids, $client_id, $callback) = @_;

	foreach my $id (@$ids)
	{
		my $info = $self->messages->{$id} || next;
		my $message = $info->{message};
		my $destination = $message->destination;
	
		if ($message->claimed)
		{
			# According to the docs, we just Do What We're Told.
			$self->claimed->{$client_id}->{$destination} = 
				delete $self->claimed->{$message->claimant}->{$destination}
		}
		else
		{
			my $elem = $self->claimed->{$client_id}->{$destination} = 
				delete $self->messages->{$message->id}->{unclaimed};
			$self->unclaimed->{$destination}->delete($elem);
		}
		$message->claim($client_id);
		$self->log(info => "Message $id claimed by client $client_id");
	}
	goto $callback if $callback;
}

sub disown_all
{
	my ($self, $client_id, $callback) = @_;
	# We just happen to know that disown_destination is synchronous, so we can
	# ignore the usual callback dance
	foreach my $dest (keys %{$self->claimed->{$client_id}}) {
		$self->disown_destination($dest, $client_id)
	}
	goto $callback if $callback;
}

sub disown_destination
{
	my ($self, $destination, $client_id, $callback) = @_;
	my $elem = delete $self->claimed->{$client_id}->{$destination};
	if ($elem) 
	{
		my $message = $elem->val;
		$message->disown();
		$self->unclaimed->{$destination}->add($elem);
		$self->messages->{$message->id}->{unclaimed} = $elem;
	}
	goto $callback if $callback;
}

# We don't persist anything, so just call our complete handler.
sub storage_shutdown
{
	my ($self, $callback) = @_;
	goto $callback if $callback;
}

1;

__END__

=pod

=head1 NAME

POE::Component::MessageQueue::Storage::BigMemory -- In-memory storage engine
optimized for a large number of messages.

=head1 SYNOPSIS

  use POE;
  use POE::Component::MessageQueue;
  use POE::Component::MessageQueue::Storage::BigMemory;
  use strict;

  POE::Component::MessageQueue->new({
    storage => POE::Component::MessageQueue::Storage::BigMemory->new()
  });

  POE::Kernel->run();
  exit;

=head1 DESCRIPTION

An in-memory storage engine that is optimised for a large number of messages.
Its an alternative to L<POE::Componenent::MessageQueue::Storage::Memory>, which
stores everything in a Perl ARARY, which can slow the MQ to a CRAWL when the
number of messsages in this store gets big.  

store() is a little bit slower per message in this module and it uses
more memory per message. Everything else should be considerably more efficient,
though, especially when the number of messages starts to climb.  Many operations
in Storage::Memory are O(n*n).  Most operations in this module are O(1)!

I wouldn't suggest using this as your main storage engine because if messages
aren't removed by consumers, it will continue to consume more memory until it
explodes.  Check-out L<POE::Component::MessageQueue::Storage::Complex> which
can use  this module internally to keep messages in memory for a period of
time before moving them into persistent storage.

=head1 CONSTRUCTOR PARAMETERS

None to speak of!

=head1 SUPPORTED STOMP HEADERS

=over 4

=item B<persistent>

I<Ignored>.  Nothing is persistent in this store.

=item B<expire-after>

I<Ignored>.  All messages are kept until handled.

=back

=head1 SEE ALSO

L<POE::Component::MessageQueue>,
L<POE::Component::MessageQueue::Storage>

I<Other storage engines:>

L<POE::Component::MessageQueue::Storage::Memory>,
L<POE::Component::MessageQueue::Storage::FileSystem>,
L<POE::Component::MessageQueue::Storage::DBI>,
L<POE::Component::MessageQueue::Storage::Generic>,
L<POE::Component::MessageQueue::Storage::Generic::DBI>,
L<POE::Component::MessageQueue::Storage::Throttled>,
L<POE::Component::MessageQueue::Storage::Complex>,
L<POE::Component::MessageQueue::Storage::Default>

=cut
