package Proc::Forking;

###########################################################
# Fork package
# Gnu GPL2 license
#
# $Id: Forking.pm,v 1.17 2004/12/03 15:27:30 fabrice Exp $
# $Revision: 1.17 $
#
# Fabrice Dulaunoy <fabrice@dulaunoy.com>
###########################################################
# ChangeLog:
#
###########################################################
use strict;

use POSIX qw(:signal_h setsid WNOHANG);
use IO::File;
use Cwd;
use Sys::Load qw/getload/;
use vars qw($VERSION );

my $CVS_version = '$Revision: 1.17 $';
$CVS_version =~ s/\$//g;
my $CVS_date = '$Date: 2004/12/03 15:27:30 $';
my $REVISION = "version $CVS_version created $CVS_date";
$CVS_version =~ s/Revision: //g;
my $VERSIONA = $';
$VERSIONA =~ s/ //g;
$VERSION = do { my @rev = ( q$Revision: 1.17 $ =~ /\d+/g ); sprintf "%d." . "%d" x $#rev, @rev };
$REVISION =~ s/\$Date: //g;
my $DAEMON_PID;
$SIG{ CHLD } = \&garbage_child;
$SIG{ INT } = $SIG{ TERM } = $SIG{ HUP } =
  sub { killall_childs(); unlink $DAEMON_PID; };

my %PID;
my %NAME;

my @CODE;
$CODE[0]  = [ 0,  "success" ];
$CODE[1]  = [ 1,  "Can't fork a new process" ];
$CODE[2]  = [ 2,  "Can't open PID file" ];
$CODE[3]  = [ 3,  "Process already running with same PID" ];
$CODE[4]  = [ 4,  "maximun LOAD reached" ];
$CODE[5]  = [ 5,  "maximun number of processes reached" ];
$CODE[6]  = [ 6,  "error in parameters" ];
$CODE[7]  = [ 7,  "No function provided" ];
$CODE[8]  = [ 8,  "Can't fork" ];
$CODE[9]  = [ 9,  "PID already present in list of PID processes" ];
$CODE[10] = [ 10, " already present in list of NAME processes" ];
$CODE[11] = [ 11, "Can't chdir" ];
$CODE[12] = [ 12, "Can't chroot" ];
$CODE[13] = [ 13, "Can't become DAEMON" ];
$CODE[14] = [ 14, "Can't unlink PID file" ];

sub daemonize
{
    my @param = @_;
    my $self  = shift @param;
    if ( @param % 2 )
    {
        return ( $CODE[6][0], 0, $CODE[6][1] );
    }

    my %param    = @param;
    my $uid      = $param{ uid } if exists( $param{ uid } );
    my $gid      = $param{ gid } if exists( $param{ gid } );
    my $home     = $param{ home } if exists( $param{ home } );
    my $pid_file = $param{ pid_file } if exists( $param{ pid_file } );
    my $name     = $param{ name } if exists( $param{ name } );
    if ( defined( $name  ) )
            {
                my $exp_name = $name ;
                $exp_name =~ s/##/$$/g;
                $0 = $exp_name;
            }
    $DAEMON_PID = $pid_file;

    my $child = fork;
    if ( !defined $child )
    {
        return ( $CODE[13][0], 0, $CODE[13][1] );
    }
    exit 0 if $child;    # parent dies;
    my $ret  = create_pid_file( $pid_file, $$ );
    my $luid = -1;
    my $lgid = -1;
    if ( $uid ne '' )
    {
        $luid = $uid;
    }
    if ( $gid ne '' )
    {
        $lgid = $gid;
    }
    chown $luid, $lgid, $pid_file;
    if ( $home ne '' )
    {
        local ( $>, $< ) = ( $<, $> );
        my $cwd = $home;
        chdir( $cwd )  || return ( $CODE[11][0], 0, $CODE[11][1] );
        chroot( $cwd ) || return ( $CODE[12][0], 0, $CODE[12][1] );
        $< = $>;
    }

    if ( $gid ne '' )
    {
        $) = "$gid $gid";
    }

    if ( $uid ne '' )
    {
        $> = $uid;
    }
    POSIX::setsid();
    open( STDIN,  "</dev/null" );
    open( STDOUT, ">/dev/null" );
    open( STDERR, ">&STDOUT" );
    chdir '/';
    umask( 0 );
    $ENV{ PATH } = '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin';
    delete @ENV{ 'IFS', 'CDPATH', 'ENV', 'BASH_ENV' };
    $SIG{ CHLD } = \&garbage_child;
}

sub new
{
    my ( $class ) = @_;
    bless {
        _function  => $_[1],
        _args      => $_[2],
        _name      => $_[3],
        _pid       => $_[4],
        _pid_file  => $_[5],
        _home      => $_[6],
        _uid       => $_[7],
        _gid       => $_[8],
        _max_child => $_[9],
        _max_load  => $_[10],
        _pids      => $_[11],
        _names     => $_[12],
    }, $class;

}

sub fork_child
{
    my @param = @_;
    my $self  = shift @param;
    if ( @param % 2 )
    {
        return ( $CODE[6][0], 0, $CODE[6][1] );
    }
    my %param = @param;
    if ( !exists( $param{ function } ) )
    {
        return ( $CODE[7][0], 0, $CODE[7][1] );
    }
    $self->{ _function } = $param{ function };
    $self->{ _args }     = $param{ args } if exists( $param{ args } );
    $self->{ _name }     = $param{ name } if exists( $param{ name } );
    $self->{ _home }     = $param{ home } if exists( $param{ home } );
    $self->{ _uid }      = $param{ uid } if exists( $param{ uid } );
    $self->{ _gid }      = $param{ gid } if exists( $param{ gid } );
    if ( exists( $param{ pid_file } ) )
    {
        $self->{ _pid_file } = $param{ pid_file };
    }

    if ( exists( $param{ max_load } ) )
    {
        $self->{ _max_load } = $param{ max_load };
        if ( $self->{ _max_load } <= ( getload() )[0] )
        {
            return ( $CODE[4][0], 0, $CODE[4][1] );
        }
    }

    if ( exists( $param{ max_child } ) )
    {
        $self->{ _max_child } = $param{ max_child };
        if ( $self->{ _max_child } <= ( keys %{ $self->{ _pids } } ) )
        {
            return ( $CODE[5][0], 0, $CODE[5][1] );
        }
    }

    {
        my $pid;
        my $ret;
        if ( $pid = fork() )
        {
## in  parent
            $self->{ _pid } = $pid;
            my $pid_file;
            my $exp_name;
            if ( defined( $self->{ _name } ) )
            {
                $exp_name = $self->{ _name };
                $exp_name =~ s/##/$pid/g;
            }
            if ( defined( $self->{ _pid_file } ) )
            {
                $pid_file = $self->{ _pid_file };
                $pid_file =~ s/##/$pid/g;
            }
            if ( !defined( $self->{ _pids }{ $pid } ) )
            {
                $self->{ _pids }{ $pid }{ name } = $exp_name;
                if ( defined( $self->{ _pid_file } ) )
                {
                    $self->{ _pids }{ $pid }{ pid_file } = $pid_file;
                    $PID{ pid_file } = $pid_file;
                }
                if ( defined( $self->{ _home } ) )
                {
                    $self->{ _pids }{ $pid }{ home } = $self->{ _home };
                    $PID{ home } = $self->{ _home };
                }
            }
            else
            {
                return ( $CODE[9][0], $self->{ _pid }, $CODE[9][1] );
            }
            if ( !defined( $self->{ _names }{ $exp_name } ) )
            {
                $self->{ _names }{ $exp_name }{ pid } = $pid;
                $NAME{ $exp_name }{ pid } = $pid;
                if ( defined( $self->{ _pid_file } ) )
                {
                    $self->{ _names }{ $exp_name }{ pid_file } = $pid_file;
                    $NAME{ $exp_name }{ pid_file } = $pid_file;
                }
                if ( defined( $self->{ _home } ) )
                {
                    $self->{ _names }{ $exp_name }{ home } = $self->{ _home };
                    $NAME{ $exp_name }{ home } = $self->{ _home };
                }
            }
            else
            {
                return (
                    $CODE[10][0],
                    $self->{ _pid },
                    ( $self->{ _name } . $CODE[10][1] )
                );
            }
            return ( $CODE[0][0], $self->{ _pid }, $CODE[0][1] );
        }
        elsif ( defined $pid )
        {
## in  child
            $SIG{ HUP } = $SIG{ INT } = $SIG{ CHLD } = $SIG{ TERM } = 'DEFAULT';
            if ( defined( $self->{ _name } ) )
            {
                my $exp_name = $self->{ _name };
                $exp_name =~ s/##/$$/g;
                $0 = $exp_name;
            }

            $self->{ _pid } = $pid;
            if ( $self->{ _home } ne '' )
            {
                local ( $>, $< ) = ( $<, $> );
                my $cwd = $self->{ _home };
                chdir( $cwd )  || return ( $CODE[11][0], 0, $CODE[11][1] );
                chroot( $cwd ) || return ( $CODE[12][0], 0, $CODE[12][1] );
                $< = $>;
            }

            if ( $self->{ _gid } ne '' )
            {
                my $gid = $self->{ _gid };
                $) = "$gid $gid";
            }
            if ( $self->{ _uid } ne '' )
            {
                $> = $self->{ _uid };
            }
            my $pid_file = $self->{ _pid_file };
            $pid_file =~ s/##/$$/g;

            if ( defined $self->{ _pid_folder } )
            {
                $pid_file = $self->{ _pid_folder } . $pid_file;
            }
            $ret = create_pid_file( $pid_file, $$ );
            $self->{ _function }( $self->{ _args } );
            if ( defined $self->{ _pid_file } )
            {
                my $pid_file = $self->{ _pid_file };
                $pid_file =~ s/##/$$/g;

                if ( -e $pid_file )
                {
                    delete_pid_file( $pid_file );
                }
            }
            exit 0;
        }
        elsif ( $! == &POSIX::EAGAIN )
        {
            my $o0 = $0;
            $0 = "$o0: waiting to fork";
            sleep 5;
            $0 = $o0;
            redo;
        }
        else
        {
            return ( $CODE[8][0], 0, $CODE[8][1] );
        }
    }

}

sub kill_child
{
    my $self   = shift;
    my $pid    = shift;
    my $signal = shift || 15;
    kill $signal => $pid;
    my $state = kill 0 => $pid;
    if ( !$state )
    {
        my $name = $self->{ $pid }{ name };
        if ( defined $self->{ _pids }{ $pid }{ pid_file } )
        {
            my $pid_file = $self->{ _pids }{ $pid }{ pid_file };
            $pid_file =~ s/##/$pid/g;
            delete $self->{ _pids }{ $pid }{ pid_file };
            delete $self->{ _names }{ $name }{ pid_file };
            if ( defined $self->{ _pid_file }{ _home } )
            {
                $pid_file = $self->{ _pid_file }{ _home } . $pid_file;
            }
            if ( -e $pid_file )
            {
                delete_pid_file( $pid_file );
            }
        }
        delete $self->{ _pids }{ $pid }{ name };
        delete $self->{ _pids }{ $pid };

        delete $self->{ _names }{ $name }{ pid };
        delete $self->{ _names }{ $name };

        delete $PID{ $pid }{ name };
        delete $PID{ $pid };

        delete $NAME{ $name }{ pid };
        delete $NAME{ $name };
    }
##	$self->clean_childs();;
}

sub killall_childs
{
    my $self   = shift;
    my $signal = shift || 15;
    my $pids   = $self->{ _pids };
    my %pids   = %{ $pids };
    foreach ( keys %pids )
    {
        kill $signal => $_;
    }
    $self->clean_childs();

#    $SIG{ INT } = $SIG{ TERM } = $SIG{ HUP } = 'DEFAULT';
}

sub list_pids
{
    my $self = shift;
    return $self->{ _pids };
}

sub list_names
{
    my $self = shift;
    return $self->{ _names };
}

sub pid_nbr
{
    my $self = shift;
    return ( scalar( keys %{ $self->{ _pids } } ) );
}

sub clean_childs
{
    my $self = shift;
    my @pid_remove_list;
    my @name_remove_list;

    foreach my $child ( keys %{ $self->{ _pids } } )
    {

        my $state = kill 0 => $child;
        if ( !$state )
        {
            my $name = $self->{ _pids }{ $child }{ name };
            if ( defined $self->{ _pids }{ $child }{ pid_file } )
            {
                my $pid_file = $self->{ _pids }{ $child }{ pid_file };
                delete $self->{ _pids }{ $child }{ pid_file };
                delete $self->{ _names }{ $name }{ pid_file };
                if ( defined $self->{ _pids }{ $child }{ home } )
                {
                    $pid_file = $self->{ _pids }{ $child }{ home } . $pid_file;
                }

                if ( -e $pid_file )
                {
                    delete_pid_file( $pid_file );
                }
            }
            delete $self->{ _pids }{ $child }{ name };
            delete $self->{ _pids }{ $child };
            delete $self->{ _names }{ $name }{ pid };
            delete $self->{ _names }{ $name };
            push @pid_remove_list,  $child;
            push @name_remove_list, $name;
        }
    }
    return \@pid_remove_list, \@name_remove_list;
}

sub test_pid
{
    my $self  = shift;
    my $child = shift;
    my $state;
    if ( defined $self->{ _pids }{ $child } )
    {
        $state = kill 0 => $child;
    }
    return ( $state, ( $self->{ _pids }{ $child }{ name } ) );
}

sub test_name
{
    my $self = shift;
    my $name = shift;
    my $state;
    if ( defined( $self->{ _names }{ $name }{ pid } ) )
    {
        $state = kill 0 => ( $self->{ _names }{ $name }{ pid } );
    }
    return ( $state, ( $self->{ _names }{ $name }{ pid } ) );
}

sub version
{
    my $self = shift;
    return $VERSION;
}

sub revision
{
    my $self = shift;
    return $REVISION;
}

sub create_pid_file
{
    my $file    = shift;
    my $pid_num = shift;
    if ( -z $file )
    {
        if ( !( -w $file && unlink $file ) )
        {
            return ( $CODE[14][0], $pid_num, $CODE[14][1] );
        }
    }
    if ( -e $file )
    {

# pid file already exists
        my $fh      = IO::File->new( $file );
        my $pid_num = <$fh>;

        if ( kill 0 => $pid_num )
        {
            return ( $CODE[3][0], $pid_num, $CODE[3][1] );
        }
        if ( !( -w $file && unlink $file ) )
        {
            return ( $CODE[14][0], $pid_num, $CODE[14][1] );
        }
    }
    my $fh = IO::File->new( $file, O_WRONLY | O_CREAT | O_EXCL, 0644 );
    if ( !$fh ) { return ( $CODE[2][0], $pid_num, $CODE[2][1] ); }
    print $fh $pid_num;
    return ( $CODE[0][0], $pid_num, $CODE[0][1] );
}

sub delete_pid_file
{
    my $file = shift;
    if ( -e $file )
    {
        if ( !( -w $file && unlink $file ) )
        {
            Carp::carp "Can't unlink PID file $file";
        }
    }
}

sub garbage_child
{
    while ( ( my $child = waitpid( -1, WNOHANG ) ) > 0 )
    {
        my $name = $PID{ $child }{ name };
        if ( defined $PID{ $child }{ pid_file } )
        {
            my $pid_file = $PID{ $child }{ pid_file };
            $pid_file =~ s/##/$child/g;
            delete $PID{ $child }{ pid_file };
            delete $NAME{ $name }{ pid_file };
            if ( defined $PID{ $child }{ home } )
            {
                $pid_file = $PID{ $child }{ home } . $pid_file;
            }

            if ( -e $pid_file )
            {
                delete_pid_file( $pid_file );
            }
        }

        delete $PID{ $child }{ name };
        delete $PID{ $child };

        delete $NAME{ $name }{ pid };
        delete $NAME{ $name };
    }
    $SIG{ CHLD } = \&garbage_child;
}

1;

=head1 ABSTRACT

The B<Proc::Forking.pm> module provides a set of tool to fork and daemonize.
The module fork a function code

=head1 SYNOPSIS

=over 3

          use strict;
          use Proc::Forking;
          use Data::Dumper;
          use Time::HiRes qw(usleep); # to allow micro sleep
	  
          my $f = Proc::Forking->new();

          $f->daemonize(
              uid      => 1000,
              gid      => 1000,
#              home     => "/tmp",
              pid_file => "/tmp/master.pid"
          );

          open( STDOUT, ">>/tmp/master.log" );
          my $nbr = 0;
	  my tmout;

          while ( 1 )
          {
              if ( $nbr < 20)
              {
                  my $extra = "other parameter";
                  my ( $status, $pid, $error ) = $f->fork_child(
                         function => \&func,
                         name     => "new_name.##",
                         args     => [ "hello SOMEONE", 3, $extra ],
                         pid_file => "/tmp/fork.##.pid",
                         uid      => 1000,
                         gid      => 1000,
                         home     => "/tmp",
                         max_load => 1.5,
                  );
                  if ( $status == 4 ) # if the load become to high
                  {
                      print "Max load reached, do a little nap\n";
		      usleep(100000);
                      next;
                  }
		    elsif ( $status ) # if another kind of error

                {
                      print "PID=$pid\t error=$error\n";
                      print Dumper( $f->list_names() );
                      print Dumper( $f->list_pids() );
                      exit;
                  }
              }
              $nbr = $f->pid_nbr;
              usleep(10); # always a good idea to put a small sleep to allow task swapper to gain some free resources
          }
	  

   sub func
   {
       my $ref  = shift;
       my @args = @$ref;
       my ( $data, $time_mout, $sockC ) = @args;
       $SIG{ USR1 } = sub { open my $log, ">>/tmp/log.s"; print $log "signal USR1 received\n"; close $log; };
       if ( !$tmout )
       {
           $tmout = 3;
       }

       for ( 1 .. 4 )
       {
           open my $fh, ">>/tmp/log";
           if ( defined $fh )
           {
               print $fh "TMOUT = $time_mout  " . time . " PID=$$  cwd=" . Cwd::cwd() . " name =$0\n";
               $fh->close;
           }
           sleep $time_outmout + rand( 5 );
       }
   }


=head1 REQUIREMENT

The B<Proc::Forking> module need the following modules

	POSIX
	IO::File
	Cwd
	Sys::Load

=head1 METHODS

=over 1

The Fork module is object oriented and provide the following method

=over 3

=head2 new

To create of a new pool of child: 

	my $f = Proc::Forking->new();

=back 3

=head2 fork_child

To fork a process

	my ( $status, $pid, $error ) = $f->fork_child(
              function => \&func,
              name     => "new_name.$_",
              args     => [ "\thello SOMEONE",3, $other param],
              pid_file => "/tmp/fork.$_.pid",
              uid      => 1000,
              gid      => 1000,
              home     => "/tmp",
              max_load => 5,
              max_child => 5
              );
	
The only mandatory parameter is the reference to the function to fork (function => \&func)
The normal return value is an array with: 3 elements (see B<RETURN VALUE>)

=over 2

=head3 function

=over 3

I<function> is the reference to the function to use as code for the child. It is the only mandatory parameter.

=back 2

=head3 name

=over 3

I<name> is the name for the newly created process (affect new_name  to $0 in the child).
A ## (double sharp ) into the name is replaced with the PID of the process created.

=back 2

=head3 home

=over 3

the I<path> provided will become the working directory of the child with a chroot.
Be carefull for the files created into the process forked, authorizasions and paths are relative to this chroot

=back 2

=head3 uid

=over 3

the child get this new I<uid> (numerical value)
Be carefull for the files created into the process forked, authorizasions and paths are relative to this chroot

=back 2

=head3 gid

=over 3

the child get this new I<gid> (numerical value)
Be carefull for the files created into the process forked, authorizasions and paths are relative to this chroot

=back 2

=head3 pid_file

=over 3

I<pid_file> givse the file containing the pid of the child (be care of uid, gid and chroot because the pid_file is created by the child)
A ## (double sharp ) into the name is expanded with the PID of the process created

=back 2

=head3 max_load

=over 3

if the "1 minute" load is greater than I<max_load>, the process is not forked
and the function will return [ 4, 0, "maximun LOAD reached" ]

=back 2

=head3 max_child

=over 3

if the number of running child is greater than max_child, the process is not forked
and the function return [ 5, 0,  "maximun number of processes reached" ]

=back 2

=back 3

=head2 kill_child

	$f->kill_child(PID[,SIGNAL]);
 
 This function kill with a signal 15 (by default) the process with the provided PID
 An optional signal could be provided


=head2 killall_childs

	$f->killall_childs([SIGNAL]);

This function kills all processes with a signal 15 (by default)
An optional signal could be provided
 
=head2 list_pids

	my $pid = $f->list_pids;

This function return a reference to a HASH like 

       {
          '1458' => {
                      'pid_file' => '/tmp/fork.3.pid',
                      'name' => 'new_name.3',
                      'home' => '/tmp'
                    },
          '1454' => {
                      'pid_file' => '/tmp/fork.1.pid',
                      'name' => 'new_name.1',
                      'home' => '/tmp'
                    },
          '1456' => {
                      'pid_file' => '/tmp/fork.2.pid',
                      'name' => 'new_name.2',
                      'home' => '/tmp'
                    }
        };


The I<pid_file> element in the HASH is only present if we provide the corresponding tag in the constructor B<fork_child>
Same for I<home> element

=head2 list_names

	my $name = $f->list_names;

This function return a reference to a HASH like  
          
	  {
          'new_name.2' => {
                            'pid_file' => '/tmp/fork.2.pid',
                            'pid' => 1456,
                            'home' => '/tmp'
                          },
          'new_name.3' => {
                            'pid_file' => '/tmp/fork.3.pid',
                            'pid' => 1458,
                            'home' => '/tmp'
                          },
          'new_name.1' => {
                            'pid_file' => '/tmp/fork.1.pid',
                            'pid' => 1454,
                            'home' => '/tmp'
                          }
        };

The I<pid_file> element in the HASH is only present if we provide the corresponding tag in the constructor B<fork_child>
Same for I<home> element
	
	
=head2 pid_nbr

	$f->pid_nbr

This function return the number of process

=head2 clean_childs

	my (@pid_removed , @name_removed) =$f->clean_childs
	
This function return the list of pid(s) removed because no more responding and the corresponding list of name(s)

=head2 test_pid

	my @state = $f->test_pid(PID);
	
This function return a ARRAY with 
the first element is the status (1 = running and 0 = not running) 
the second element is the NAME of process if the process with the PID is present in pid list and running

=head2 test_name

	my @state = $f->test_pid(NAME);
	
This function return a ARRAY with
the first element is the status (1 = running and 0 = not running)
the second element is the PID of the process if the process with the NAME is present in name list and running
	
=head2 version

	$f->version;

Return the version number

=head2 revision

	$f->revision;

Return the CVS revision


=head2 daemonize

	$f->daemonize(
		uid=>1000,
		gid => 1000,
		home => "/tmp",
		pid_file => "/tmp/master.pid"
		name => "DAEMON"
		);
		
This function put the main process in daemon mode and detaches it from console
All parameter are optional
The I<pid_file> is always created in absolute path, bafore any chroot either if I<home> is provided.
After it's creation, the file is chmod according to the provided uid and gig
When process is kill, the  pid_file is deleted

=head3 uid

=over 3

the process get this new uid  (numerical value)

=back 2

=head3 gid

=over 3

the process get this new gid (numerical value)

=back 2

=head3 home

=over 3

the path provided become the working directory of the child with a chroot

=back 2

=head3 pid_file

I<pid_file> specified the path to the pid_file for the child
Be carefull of uid, gid and chroot because the pid_file is created by the child)

=head3 name

=over 3

I<name> is the name for the newly created process (affect new_name  to $0 in the child).
A ## (double sharp ) into the name is replaced with the PID of the process created.

=head1 RETURN VALUE

I<fork_child()> constructor returns an array of 3 elements:
        
	1) the numerical value of the status
        2) th epid if the fork succeed
        3) the text of the status
	
the different possible values are:

	[ 0, PID, "success" ];
	[ 1, 0, "Can't fork a new process" ];
	[ 2, PID, "Can't open PID file" ];
	[ 3, PID, "Process already running with same PID" ];
	[ 4, 0, "maximun LOAD reached" ];
	[ 5, 0,  "maximun number of processes reached" ];
	[ 6, 0, "error in parameters" ];
	[ 7, 0, "No function provided" ];
	[ 8, 0  "Can't fork" ];
	[ 9, PID, "PID already present in list of PID processes" ];
	[ 10, PID, " already present in list of NAME processes" ];
	[ 11, 0, "Can't chdir" ];
	[ 12, 0  "Can't chroot" ];
	[ 13, 0, "Can't become DAEMON" ];
	[ 14, PID, "Can't unlink PID file" ];


=head1 TODO

=item *

May be a kind of IPC

=item *

A log, debug and/or syslog part 

=item *

A good test.pl for the install

=head1 AUTHOR

Fabrice Dulaunoy <fabrice@dulaunoy.com>

4 Augustus 2004

=head1 LICENSE

Under the GNU GPL2

    
    This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public 
    License as published by the Free Software Foundation; either version 2 of the License, 
    or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program; 
    if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

    Proc::Forking    Copyright (C) 2004 DULAUNOY Fabrice  Proc::Forking comes with ABSOLUTELY NO WARRANTY; 
    for details See: L<http://www.gnu.org/licenses/gpl.html> 
    This is free software, and you are welcome to redistribute it under certain conditions;
   
