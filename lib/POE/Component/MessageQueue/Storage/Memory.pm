
package POE::Component::MessageQueue::Storage::Memory;

use strict;

use Data::Dumper;

sub new
{
	my $class = shift;
	my $args  = shift;

	my $dsn;
	my $username;
	my $password;
	my $options;

	if ( ref($args) eq 'HASH' )
	{
		$dsn      = $args->{dsn};
		$username = $args->{username};
		$password = $args->{password};
		$options  = $args->{options};
	}

	my $self = {
		message_id        => 0,
		claiming          => { },
		dispatch_message  => undef,
		destination_ready => undef,
		messages          => [ ],
	};

	bless  $self, $class;
	return $self;
}

sub set_dispatch_message_handler
{
	my ($self, $handler) = @_;
	
	$self->{dispatch_message} = $handler;
}

sub set_destination_ready_handler
{
	my ($self, $handler) = @_;

	$self->{destination_ready} = $handler;
}

sub get_next_message_id
{
	my $self = shift;
	return ++$self->{message_id};
}

sub store
{
	my ($self, $message) = @_;

	# push onto our array
	push @{$self->{messages}}, $message;
}

sub remove
{
	my ($self, $message_id) = @_;

	my $max = scalar @{$self->{messages}};

	# find the message and remove it
	for( my $i = 0; $i < $max; $i++ )
	{
		if ( $self->{messages}->[$i]->{message_id} == $message_id )
		{
			splice @{$self->{messages}}, $i, 1;
			last;
		}
	}
}

sub claim_and_retrieve
{
	my $self = shift;
	my $args = shift;

	my $destination;
	my $client_id;

	if ( ref($args) eq 'HASH' )
	{
		$destination = $args->{destination};
		$client_id   = $args->{client_id};
	}
	else
	{
		$destination = $args;
		$client_id   = shift;
	}

	my $max = scalar @{$self->{messages}};

	# look for an unclaimed message and take it
	for ( my $i = 0; $i < $max; $i++ )
	{
		my $message = $self->{messages}->[$i];

		if ( not defined $message->{in_use_by} )
		{
			if ( not defined $self->{dispatch_message} )
			{
				die "Pulled message from backstore, but there is no dispatch_message handler";
			}

			# claim it, yo!
			$message->{in_use_by} = $client_id;

			# dispatch message
			$self->{dispatch_message}->( $message, $destination, $client_id );

			# let it know that the destination is ready
			$self->{destination_ready}->( $destination );

			last;
		}
	}
	
	# we are always capable to attempt to claim
	return 1;
}

# unmark all messages owned by this client
sub disown
{
	my ($self, $client_id) = @_;

	foreach my $message ( @{$self->{message}} )
	{
		if ( $message->{in_use_by} == $client_id )
		{
			$message->{in_use_by} = undef;
		}
	}
}

1;
