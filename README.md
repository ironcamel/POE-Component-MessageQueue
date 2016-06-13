# NAME

POE::Component::MessageQueue - A STOMP based message queue server

# USAGE

If you are only interested in running with the recommended storage backend and
some predetermined defaults, you can use the included command line script:

    POE::Component::MessageQueue version 0.2.12
    Copyright 2007-2011 David Snopek (http://www.hackyourlife.org)
    Copyright 2007, 2008 Paul Driver <frodwith@gmail.com>
    Copyright 2007 Daisuke Maki <daisuke@endeworks.jp>

    mq.pl [--port|-p <num>]               [--hostname|-h <host>]
          [--front-store <str>]           [--front-max <size>] 
          [--granularity <seconds>]       [--nouuids]
          [--timeout|-i <seconds>]        [--throttle|-T <count>]
                  [--dbi-dsn <str>]               [--mq-id <str>]
                  [--dbi-username <str>]          [--dbi-password <str>]
          [--pump-freq|-Q <seconds>]
          [--data-dir <path_to_dir>]      [--log-conf <path_to_file>]
          [--stats-interval|-i <seconds>] [--stats]
          [--pidfile|-p <path_to_file>]   [--background|-b]
          [--crash-cmd <path_to_script>]
          [--debug-shell] [--version|-v]  [--help|-h]

    SERVER OPTIONS:
      --port     -p <num>     The port number to listen on (Default: 61613)
      --hostname -h <host>    The hostname of the interface to listen on 
                              (Default: localhost)

    STORAGE OPTIONS:
      --storage <str>         Specify which overall storage engine to use.  This
                              affects what other options are value.  (can be
                              default or dbi)
      --front-store -f <str>  Specify which in-memory storage engine to use for
                              the front-store (can be memory or bigmemory).
      --front-max <size>      How much message body the front-store should cache.
                              This size is specified in "human-readable" format
                              as per the -h option of ls, du, etc. (ex. 2.5M)
      --timeout -i <secs>     The number of seconds to keep messages in the 
                              front-store (Default: 4)
      --pump-freq -Q <secs>   How often (in seconds) to automatically pump each
                              queue.  Set to zero to disable this timer entirely
                              (Default: 0)
      --granularity <secs>    How often (in seconds) Complex should check for
                              messages that have passed the timeout.  
      --[no]uuids             Use (or do not use) UUIDs instead of incrementing
                              integers for message IDs.  (Default: uuids)
      --throttle -T <count>   The number of messages that can be stored at once 
                              before throttling (Default: 2)
      --data-dir <path>       The path to the directory to store data 
                              (Default: /var/lib/perl_mq)
      --log-conf <path>       The path to the log configuration file 
                              (Default: /etc/perl_mq/log.conf)

      --dbi-dsn <str>         The database DSN when using --storage dbi
      --dbi-username <str>    The database username when using --storage dbi
      --dbi-password <str>    The database password when using --storage dbi
      --mq-id <str>           A string uniquely identifying this MQ when more
                              than one MQ use the DBI database for storage

    STATISTICS OPTIONS:
      --stats                 If specified the, statistics information will be 
                              written to $DATA_DIR/stats.yml
      --stats-interval <secs> Specifies the number of seconds to wait before 
                              dumping statistics (Default: 10)

    DAEMON OPTIONS:
      --background -b         If specified the script will daemonize and run in the
                              background
      --pidfile    -p <path>  The path to a file to store the PID of the process

      --crash-cmd  <path>     The path to a script to call when crashing.
                              A stacktrace will be printed to the script's STDIN.
                              (ex. 'mail root@localhost')

    OTHER OPTIONS:
      --debug-shell           Run with POE::Component::DebugShell
      --version    -v         Show the current version.
      --help       -h         Show this usage message

# SYNOPSIS

## Subscriber

    use Net::Stomp;
    
    my $stomp = Net::Stomp->new({
      hostname => 'localhost',
      port     => 61613
    });
    
    # Currently, PoCo::MQ doesn't do any authentication, so you can put
    # whatever you want as the login and passcode.
    $stomp->connect({ login => $USERNAME, passcode => $PASSWORD });
    
    $stomp->subscribe({
      destination => '/queue/my_queue.sub_queue',
      ack         => 'client'
    });
    
    while (1)
    {
      my $frame = $stomp->receive_frame;
      print $frame->body . "\n";
      $stomp->ack({ frame => $frame });
    }
    
    $stomp->disconnect();

## Producer

    use Net::Stomp;
    
    my $stomp = Net::Stomp->new({
      hostname => 'localhost',
      port     => 61613
    });
    
    # Currently, PoCo::MQ doesn't do any authentication, so you can put
    # whatever you want as the login and passcode.
    $stomp->connect({ login => $USERNAME, passcode => $PASSWORD });
    
    $stomp->send({
      destination => '/queue/my_queue.sub_queue',
      body        => 'I am a message',
      persistent  => 'true',
    });
    
    $stomp->disconnect();

## Server

If you want to use a different arrangement of storage engines or to embed PoCo::MQ
inside another application, the following synopsis may be useful to you:

    use POE;
    use POE::Component::Logger;
    use POE::Component::MessageQueue;
    use POE::Component::MessageQueue::Storage::Default;
    use Socket; # For AF_INET
    use strict;

    my $DATA_DIR = '/tmp/perl_mq';

    # we create a logger, because a production message queue would
    # really need one.
    POE::Component::Logger->spawn(
      ConfigFile => 'log.conf',
      Alias      => 'mq_logger'
    );

    POE::Component::MessageQueue->new({
      port     => 61613,            # Optional.
      address  => '127.0.0.1',      # Optional.
      hostname => 'localhost',      # Optional.
      domain   => AF_INET,          # Optional.
      
      logger_alias => 'mq_logger',  # Optional.

      # Required!!
      storage => POE::Component::MessageQueue::Storage::Default->new({
        data_dir     => $DATA_DIR,
        timeout      => 2,
        throttle_max => 2
      })
    });

    POE::Kernel->run();
    exit;

# DESCRIPTION

This module implements a message queue \[1\] on top of [POE](https://metacpan.org/pod/POE) that communicates
via the STOMP protocol \[2\].

There exist a few good Open Source message queues, most notably ActiveMQ \[3\] which
is written in Java.  It provides more features and flexibility than this one (while
still implementing the STOMP protocol), however, it was (at the time I last used it)
very unstable.  With every version there was a different mix of memory leaks, persistence
problems, STOMP bugs, and file descriptor leaks.  Due to its complexity I was
unable to be very helpful in fixing any of these problems, so I wrote this module!

This component distinguishes itself in a number of ways:

- No OS threads, its asynchronous.  (Thanks to [POE](https://metacpan.org/pod/POE)!)
- Persistence was a high priority.
- A strong effort is put to low memory and high performance.
- Message storage can be provided by a number of different backends.
- Features to support high-availability and fail-over.  (See the ["#HIGH AVAILABILITY"](#high-availability) section below)

## Special STOMP headers

You can see the main STOMP documentation here: [http://stomp.codehaus.org/Protocol](http://stomp.codehaus.org/Protocol)

PoCo::MQ implements a number of non-standard STOMP headers:

- **persistent**

    Set to the string "true" to request that a message be persisted.  Not setting this header
    or setting it to any other value, means that a message is non-persistent.

    Many storage engines ignore the "persistent" header, either persisting all messages or 
    no messages, so be sure to check the documentation for your storage engine.

    Using the Complex or Default storage engines, persistent messages will always be sent
    to the back store and non-persistent messages will be discarded eventually.

- **expire-after**

    For non-persistent messages, you can set this header to the number of seconds this
    message must be kept before being discarded.  This is ignored for persistent messages.

    Many storage engines ignore the "expire-after" header, so be sure to check the
    documentation for your storage engine.

    Using the Complex or Default storage engines, this header will be honored.  If it isn't
    specified, non-persistent messages are discarded when pushed out of the front store.

- **deliver-after**

    For both persistent or non-persistent messages, you can set this header to the number of
    seconds this message should be held before being delivered.  In other words, this allows
    you to delay delivery of a message for an arbitrary number of seconds.

    All the storage engines in the standard distribution support this header.  **But it will not
    work without a pump frequency enabled!**  If using mq.pl, enable with --pump-freq or if creating
    a [POE::Component::MessageQueue](https://metacpan.org/pod/POE::Component::MessageQueue) object directly, pass pump\_frequency as an argument to new().

## Queues and Topics

In PoCo::MQ there are two types of _destinations_: **queues** and **topics**

- **queue**

    Each message is only delivered to a single subscriber (not counting
    messages that were delivered but not ACK'd).  If there are multiple
    subscribers on a single queue, the messages will be divided amoung them,
    roughly equally.

- **topic**

    Each message is delivered to every subscriber.  Topics don't support any kind
    of persistence, so to get a message, a subscriber _must_ be connected at the
    time it was sent.

All destination names start with either "/queue/" or "/topic/" to distinguish
between queues and topics.

## Tips and Tricks

- **Logging!  Use it.**

    PoCo::MQ uses [POE::Component::Logger](https://metacpan.org/pod/POE::Component::Logger) for logging which is based on
    [Log::Dispatch](https://metacpan.org/pod/Log::Dispatch).  By default **mq.pl** looks for a log file at:
    "/etc/perl\_mq/log.conf".  Or you can specify an alternate location with the
    _--log-conf_ command line argument.  

- **Using the login/passcode to track clients in the log.**

    Currently the login and passcode aren't used by PoCo::MQ for auth, but they
    _are_ written to the log file.  In the log file clients are only identified
    by the client id.  But if you put information identifying the client in the
    login/passcode you can connect that to a client id by finding it in the log.

# STORAGE

When creating an instance of this component you must pass in a storage object
so that the message queue knows how to store its messages.  There are some storage
backends provided with this distribution.  See their individual documentation for 
usage information.  Here is a quick break down:

- [POE::Component::MessageQueue::Storage::Memory](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Memory) -- The simplest storage engine.  It keeps messages in memory and provides absolutely no presistence.
- [POE::Component::MessageQueue::Storage::BigMemory](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::BigMemory) -- An alternative memory storage engine that is optimized for large numbers of messages.
- [POE::Component::MessageQueue::Storage::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::DBI) -- Uses Perl [DBI](https://metacpan.org/pod/DBI) to store messages.  Depending on your database configuration, using directly may not be recommended because the message bodies are stored in the database.  Wrapping with [POE::Component::MessageQueue::Storage::FileSystem](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::FileSystem) allows you to store the message bodies on disk.  All messages are stored persistently.  (Underneath this is really just [POE::Component::MessageQueue::Storage::Generic](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic) and [POE::Component::MessageQueue::Storage::Generic::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic::DBI))
- [POE::Component::MessageQueue::Storage::FileSystem](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::FileSystem) -- Wraps around another storage engine to store the message bodies on the filesystem.  This can be used in conjunction with the DBI storage engine so that message properties are stored in DBI, but the message bodies are stored on disk.  All messages are stored persistently regardless of whether a message has set the persistent header or not.
- [POE::Component::MessageQueue::Storage::Generic](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic) -- Uses [POE::Component::Generic](https://metacpan.org/pod/POE::Component::Generic) to wrap storage modules that aren't asynchronous.  Using this module is the easiest way to write custom storage engines.
- [POE::Component::MessageQueue::Storage::Generic::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic::DBI) -- A synchronous [DBI](https://metacpan.org/pod/DBI)-based storage engine that can be used inside of Generic.  This provides the basis for the [POE::Component::MessageQueue::Storage::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::DBI) module.
- [POE::Component::MessageQueue::Storage::Throttled](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Throttled) -- Wraps around another engine to limit the number of messages sent to be stored at once.  Use of this module is **highly** recommended!  If the storage engine is unable to store the messages fast enough (ie. with slow disk IO) it can get really backed up and stall messages coming out of the queue, allowing execessive producers to basically monopolize the server, preventing any messages from getting distributed to subscribers.  Also, it will significantly cuts down the number of open FDs when used with [POE::Component::MessageQueue::Storage::FileSystem](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::FileSystem).  Internally it makes use of [POE::Component::MessageQueue::Storage::BigMemory](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::BigMemory) to store the throttled messages.
- [POE::Component::MessageQueue::Storage::Complex](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Complex) -- A configurable storage engine that keeps a front-store (something fast) and a back-store (something persistent), allowing you to specify a timeout and an action to be taken when messages in the front-store expire, by default, moving them into the back-store.  This optimization allows for the possibility of messages being handled before ever having to be persisted.  Complex is capable to correctly handle the persistent and expire-after headers.
- [POE::Component::MessageQueue::Storage::Default](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Default) -- A combination of the Complex, BigMemory, FileSystem, DBI and Throttled modules above.  It will keep messages in BigMemory and move them into FileSystem after a given number of seconds, throttling messages passed into DBI.  The DBI backend is configured to use SQLite.  It is capable to correctly handle the persistent and expire-after headers.  This is the recommended storage engine and should provide the best performance in the most common case (ie. when both providers and consumers are connected to the queue at the same time).

# CONSTRUCTOR PARAMETERS

- storage => SCALAR

    The only required parameter.  Sets the object that the message queue should use for
    message storage.  This must be an object that follows the interface of
    [POE::Component::MessageQueue::Storage](https://metacpan.org/pod/POE::Component::MessageQueue::Storage) but doesn't necessarily need to be a child
    of that class.

- alias => SCALAR

    The session alias to use.

- port => SCALAR

    The optional port to listen on.  If none is given, we use 61613 by default.

- address => SCALAR

    The option interface address to bind to.  It defaults to INADDR\_ANY or INADDR6\_ANY
    when using IPv4 or IPv6, respectively.

- hostname => SCALAR

    The optional name of the interface to bind to.  This will be converted to the IP and
    used as if you set _address_ instead.  If you set both _hostname_ and _address_,
    _address_ will override this value.

- domain => SCALAR

    Optionally specifies the domain within which communication will take place.  Defaults
    to AF\_INET.

- logger\_alias => SCALAR

    Optionally set the alias of the POE::Component::Logger object that you want the message
    queue to log to.  If no value is given, log information is simply printed to STDERR.

- message\_class => SCALAR

    Optionally set the package name to use for the Message object.  This should be a child
    class of POE::Component::MessageQueue::Message or atleast follow the same interface.

    This allows you to add new message headers which the MQ can recognize.

- pump\_frequency => SCALAR

    Optionally set how often (in seconds) to automatically pump each queue.  If zero or
    no value is given, then this timer is disabled entirely.

    When disabled, each queue is only pumped when its contents change, meaning 
    when a message is added or removed from the queue.  Normally, this is enough.  However,
    if your storage engine holds back messages for any reason (ie. to delay their 
    delivery) it will be necessary to enable this, so that the held back messages will
    ultimately be delivered.

    _You must enable this for the message queue to honor the deliver-after header!_

- observers => ARRAYREF

    Optionally pass in a number of objects that will receive information about events inside
    of the message queue.

    Currently, only one observer is provided with the PoCo::MQ distribution:
    [POE::Component::MessageQueue::Statistics](https://metacpan.org/pod/POE::Component::MessageQueue::Statistics).  Please see its documentation for more information.

# HIGH AVAILABILITY

From version 0.2.10, PoCo::MQ supports a features to enable high availability.

- **Clustering**

    You can now run multiple MQs which share the same back-store, behind a reverse-proxy load-balancer with
    automatic fail-over, if one of the MQs goes down.

    See the the clustering documentation for more information:

    [POE::Component::MessageQueue::Manual::Clustering](https://metacpan.org/pod/POE::Component::MessageQueue::Manual::Clustering)

- **DBI fail-over**

    The DBI storage engine can be configured with a list of database servers.  If one of them is not available
    or goes down, it will fail-over to the next one.

    If you set up several database servers with master-to-master replication, this will allow the MQ to seemlessly
    handle failure of one of the databases.

    See the DBI storage engine documentation for more information:

    [POE::Component::MessageQueue::Storage::Generic::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic::DBI)

# REFERENCES

- \[1\]

    [http://en.wikipedia.org/wiki/Message\_Queue](http://en.wikipedia.org/wiki/Message_Queue) -- General information about message queues

- \[2\]

    [http://stomp.codehaus.org/Protocol](http://stomp.codehaus.org/Protocol) -- The informal "spec" for the STOMP protocol

- \[3\]

    [http://www.activemq.org/](http://www.activemq.org/) -- ActiveMQ is a popular Java-based message queue

# UPGRADING FROM OLDER VERSIONS

If you used any of the following storage engines with PoCo::MQ 0.2.9 or older:

- [POE::Component::MessageQueue::Storage::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::DBI)

The database format has changed!

**Note:** When using [POE::Component::MessageQueue::Storage::Default](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Default) (meaning mq.pl
\--storage default) the database will be automatically updated in place, so you don't
need to worry about this.

Included in the distribution, is a schema/ directory with a few SQL scripts for 
upgrading:

- upgrade-0.1.7.sql -- Apply if you are upgrading from version 0.1.6 or older.
- upgrade-0.1.8.sql -- Apply if your are upgrading from version 0.1.7 or after applying
the above upgrade script.  This one has a SQLite specific version: upgrade-0.1.8-sqlite.sql).
- upgrade-0.2.3.sql -- Apply if you are upgrading from version 0.2.2 or older (after
applying the above upgrade scripts).
- upgrade-0.2.9-mysql.sql -- Doesn't apply to SQLite users!  Apply if you are upgrading from version
0.2.8 or older (after applying the above upgrade scripts).
- upgrade-0.2.10-mysql.sql -- Doesn't apply to SQLite users!  Apply if you are upgrading from version
0.2.9 or older (after applying the above upgrade scripts).

# CONTACT

Please check out the Google Group at:

[http://groups.google.com/group/pocomq](http://groups.google.com/group/pocomq)

Or just send an e-mail to: pocomq@googlegroups.com

# DEVELOPMENT

If you find any bugs, have feature requests, or wish to contribute, please
contact us at our Google Group mentioned above.  We'll do our best to help you
out!

Development is coordinated via Bazaar (See [http://bazaar-vcs.org](http://bazaar-vcs.org)).  The main
Bazaar branch can be found here:

[http://code.hackyourlife.org/bzr/dsnopek/perl\_mq/devel.mainline](http://code.hackyourlife.org/bzr/dsnopek/perl_mq/devel.mainline)

We prefer that contributions come in the form of a published Bazaar branch with the
changes.  This helps facilitate the back-and-forth in the review process to get
any new code merged into the main branch.

There is also an official git mirror hosted on GitHub here:

[https://github.com/dsnopek/POE--Component--MessageQueue](https://github.com/dsnopek/POE--Component--MessageQueue)

We will also accept contributions via git and GitHub pull requests!

# FUTURE

The goal of this module is not to support every possible feature but rather to
be small, simple, efficient and robust.  For the most part expect incremental
changes to address those areas.

Beyond that we have a TODO list (shown below) called **"The Long Road To
1.0"**.  This is a list of things we feel we need to have inorder to call the
product complete.  That includes management and monitoring tools for sysadmins
as well as documentation for developers.

- **Full support for STOMP**: Includes making sure we are robust to clients
participating badly in the protocol.
- **Authentication and authorization**: This should be highly pluggable, but
basically (as far as authorization goes) each user can get read/write/admin
perms for a queue which are inherited by default to sub-queues (as separated
by the dot character).
- **Monitoring/management tools**:  It should be possible for an admin to monitor the
overall state of the queue, ie: (1) how many messages for what queues are in
the front-store, throttled, back-store, etc, (2) information on connected
clients, (3) data/message thorough put, (4) daily/weekly/monthly trends, (X)
etc..  They should also be able to "peek" at any message at any point as well
as delete messages or whole queues.
The rough plan is to use special STOMP frames and "magic" queues/topics to
access special information or perform admin tasks.  Command line scripts for
simple things would be included in the main distribution and a full-featured
web-interface would be provided as a separate module.
- **Log rotation**: At minimum, documentation on how to set it up.
- **Docs on "using" the MQ**: A full tutorial from start to finish, advice on
writing good consumers/producers and solid docs on authoring custom storage
engines.

# APPLICATIONS USING PoCo::MQ

- [http://chessvegas.com](http://chessvegas.com)

    Chess gaming site ChessVegas.

# SEE ALSO

_External modules:_

[POE](https://metacpan.org/pod/POE),
[POE::Component::Server::Stomp](https://metacpan.org/pod/POE::Component::Server::Stomp),
[POE::Component::Client::Stomp](https://metacpan.org/pod/POE::Component::Client::Stomp),
[Net::Stomp](https://metacpan.org/pod/Net::Stomp),
[POE::Filter::Stomp](https://metacpan.org/pod/POE::Filter::Stomp),
[POE::Component::Logger](https://metacpan.org/pod/POE::Component::Logger),
[DBD::SQLite](https://metacpan.org/pod/DBD::SQLite),
[POE::Component::Generic](https://metacpan.org/pod/POE::Component::Generic)

_Storage modules:_

[POE::Component::MessageQueue::Storage](https://metacpan.org/pod/POE::Component::MessageQueue::Storage),
[POE::Component::MessageQueue::Storage::Memory](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Memory),
[POE::Component::MessageQueue::Storage::BigMemory](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::BigMemory),
[POE::Component::MessageQueue::Storage::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::DBI),
[POE::Component::MessageQueue::Storage::FileSystem](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::FileSystem),
[POE::Component::MessageQueue::Storage::Generic](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic),
[POE::Component::MessageQueue::Storage::Generic::DBI](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Generic::DBI),
[POE::Component::MessageQueue::Storage::Double](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Double),
[POE::Component::MessageQueue::Storage::Throttled](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Throttled),
[POE::Component::MessageQueue::Storage::Complex](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Complex),
[POE::Component::MessageQueue::Storage::Default](https://metacpan.org/pod/POE::Component::MessageQueue::Storage::Default)

_Statistics modules:_

[POE::Component::MessageQueue::Statistics](https://metacpan.org/pod/POE::Component::MessageQueue::Statistics),
[POE::Component::MessageQueue::Statistics::Publish](https://metacpan.org/pod/POE::Component::MessageQueue::Statistics::Publish),
[POE::Component::MessageQueue::Statistics::Publish::YAML](https://metacpan.org/pod/POE::Component::MessageQueue::Statistics::Publish::YAML)

_ID generator modules:_

[POE::Component::MessageQueue::IDGenerator](https://metacpan.org/pod/POE::Component::MessageQueue::IDGenerator),
[POE::Component::MessageQueue::IDGenerator::SimpleInt](https://metacpan.org/pod/POE::Component::MessageQueue::IDGenerator::SimpleInt),
[POE::Component::MessageQueue::IDGenerator::UUID](https://metacpan.org/pod/POE::Component::MessageQueue::IDGenerator::UUID)

# BUGS

We are serious about squashing bugs!  Currently, there are no known bugs, but
some probably do exist.  If you find any, please let us know at the Google group.

That said, we are using this in production in a commercial application for
thousands of large messages daily and we experience very few issues.

# AUTHORS

Copyright 2007-2011 David Snopek ([http://www.hackyourlife.org](http://www.hackyourlife.org))

Copyright 2007, 2008 Paul Driver <frodwith@gmail.com>

Copyright 2007 Daisuke Maki <daisuke@endeworks.jp>

# LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see &lt;http://www.gnu.org/licenses/>.
