package cells;
use strict;
use POSIX qw(:sys_wait_h mkfifo);
use Fcntl qw(:flock);
use File::Spec;
use File::Basename;
use JSON::PP;
use URI::Escape;
use IO::Socket::UNIX qw( SOCK_STREAM SOMAXCONN );


#THIS FUNCTION MOST LIKELY HAS RACE CONDITIONS
sub delete_temp_files{
    if(-e pidlocks_dir()){
        my @lockfiles = get_directory_contents(pidlocks_dir());
        for my $file(@lockfiles){
            if(not file_is_locked($file)){
                unlink $file or die "can't delete $file: $!";
            }
        }
    }
    my @active_pids = get_active_pids();

    delete_unmentioned_pidfiles_in_dir(sockets_dir(), [@active_pids] );
    delete_unmentioned_pidfiles_in_dir(working_pids_dir(), [@active_pids] );
    delete_unmentioned_pidfiles_in_dir(current_tasks_dir(), [@active_pids] );

    my @ancestry_dirs = get_directory_contents(ancestry_dir());
    for my $ancestry_dir(@ancestry_dirs){
        delete_unmentioned_pidfiles_in_dir($ancestry_dir, [@active_pids]);
        my @leftovers = get_directory_contents($ancestry_dir);
        unless(@leftovers){
            rmdir $ancestry_dir or die "can't delete $ancestry_dir: $!";
        }
    }
}

sub delete_unmentioned_pidfiles_in_dir{
    my $dir = shift;
    my @mentioned_pids = @{ shift() };
    my %mentioned_pid_h = map {$_ => 1} @mentioned_pids;
    if(-e $dir){
        my @pidfiles = get_directory_contents($dir);
        for my $pid_file(@pidfiles){
            my $pid = basename $pid_file;
            if($mentioned_pid_h{$pid}){
                #mentioned, no delete
            }else{
                unlink $pid_file or die "can't delete $pid_file: $!";
            }
        }
    }
}

sub get_active_pids{
    my @active_pids;
    if(-e pidlocks_dir()){
        my @lockfiles = get_directory_contents(pidlocks_dir());
        for my $file(@lockfiles){
            if( file_is_locked($file)){
                push @active_pids, basename $file;
            }
        }
    }
    return @active_pids;
}

sub root_dir{
    return 'perl_cells_data';
}

sub get_directory_contents{
    my $dir = shift;

    opendir(my $dh, $dir) or die "Can't open directory $dir: $!\n";
    my @files = grep !/^\.\.?$/, readdir($dh);
    @files = map {File::Spec->catdir($dir, $_)} @files;
    return @files;
}

sub pidlocks_dir{
    return File::Spec->catdir(root_dir(), 'pidlocks');
}

sub sockets_dir{
    return File::Spec->catdir(root_dir(), 'sockets');
}

sub ancestry_dir{
    return File::Spec->catdir(root_dir(), 'ancestry');
}


sub working_pids_dir{
    return File::Spec->catdir(root_dir(), 'working_pids');
}

sub current_tasks_dir{
    return File::Spec->catdir(root_dir(), 'current_tasks');
}

sub socket_path_for_pid{
    my $pid = shift;
    return File::Spec->catdir(sockets_dir(), $pid);
}

sub lockfile_path_for_pid{
    my $pid = shift;
    return File::Spec->catdir(pidlocks_dir(), $pid);
}

sub working_pids_path_for_pid{
    my $pid = shift;
    return File::Spec->catdir(working_pids_dir(), $pid);
}

sub current_task_path_for_pid{
    my $pid = shift;
    return File::Spec->catdir(current_tasks_dir(), $pid);
}

sub get_pids_from_lockfiles{
    my @pids = get_directory_contents(pidlocks_dir());

    @pids = map {basename $_} @pids;

    return @pids;
}

sub ancestry_path_for_parent_child_pids{
    my $parent = shift;
    my $child = shift;

    return File::Spec->catdir(ancestry_dir(), $parent, $child);
}

sub make_fifo{
    my $path = shift;
    mkfifo($path, 0700) or die "mkfifo $path failed: $!";
}

sub open_for_reading{
    my $path = shift;
    open(my $fh, "<", $path) or die "cannot open $path: $!";
    return $fh;
}

sub open_for_writing{
    my $path = shift;
    open(my $fh, ">", $path) or die "cannot open $path: $!";
    return $fh;
}

sub ensure_parent_dir_exist{
    my $path = shift;

    my $parent = chop_path($path);
    prep_and_check_dir($parent);
}

sub chop_path{
    my $path = shift;
    my @dirs = File::Spec->splitdir($path);
    pop @dirs;
    return File::Spec->catdir(@dirs);
}

sub prep_and_check_dir{
    my $dir = shift;

    if($dir eq ''){
        #root always exists
        return;
    }

    if(not -e $dir){
        my $parent = chop_path($dir);
        prep_and_check_dir($parent);
        mkdir $dir or die "can't create dir: $!";
    }
    if(not (-r $dir and -w $dir)){
        die "something is wrong with $dir";
    }
}

sub acquire_lockfile{ #NONBLOCKING THIS MAY NOT BE RIGHT
    #returns lock fh
    my $lockfile = shift;
    my $lock_fh;
    unless(open $lock_fh, ">", $lockfile){
        die "cant open lockfile: $!";
    }
    if(flock($lock_fh, LOCK_EX|LOCK_NB)){
        #was able to lock
        return $lock_fh
    }else{
        die "cant lock lockfile";
    }
}

sub unlock_lock_fh{
    my $lock_fh = shift;
    flock($lock_fh, LOCK_UN) or die "can't unlock: $!";
    close($lock_fh) or die "can't close lock fh: $!";
}

sub file_is_locked{
    my $lockfile = shift;
    my $lock_fh;
    unless(open $lock_fh, "<", $lockfile){
        #cant open
        #not locked
        return 0;
    }
    if(flock($lock_fh, LOCK_EX|LOCK_NB)){
        #was able to lock -- which means no one else was locking it
        unlock_lock_fh($lock_fh);
        return 0;
    }else{
        #already locked
        close($lock_fh) or die "can't close lock fh: $!";
        return 1;
    }
}

sub acquire_lock_for_path{
    my $lockfile_path = shift;
    cells::ensure_parent_dir_exist($lockfile_path);
    my $lock_fh = cells::acquire_lockfile($lockfile_path);
    return $lock_fh;
}

sub get_contents_of_file{ #RETURNS UNDEF IN CASE FILE DOES NOT EXIST
    my $path = shift;

    if(not -e $path){
        die "$path does not exist";
    }

    if(open(my $f, '<', $path)){
        my $string = do { local($/); <$f> };
        close($f);
        return $string;
    }else{
        die "can't open $path: $!";
    }
}

sub set_contents_of_file{
    my $path = shift;
    my $contents = shift;
    cells::ensure_parent_dir_exist($path);
    my $fh = cells::open_for_writing($path);
    print $fh $contents;
    close($fh) or die "Cant close $path: $!";
}

sub encode_hash{
    my $hash = shift;
    return uri_escape(encode_json($hash));
}

sub decode_hash{
    my $msg = shift;
    return decode_json(uri_unescape($msg));
}

sub send_hash_to_pid_and_wait_for_response{
    my $hash = shift;
    my $pid  = shift;

    my $message = encode_hash($hash);

    my $socket_path = cells::socket_path_for_pid($pid);
    my $socket = IO::Socket::UNIX->new(
       Type => SOCK_STREAM,
       Peer => $socket_path,
    ) or die("Can't connect to server: $!\n");

    print $socket "$message\n";
    my $resp_line = <$socket> ;
    close $socket;
    chomp $resp_line;

    my $resp_hash = decode_hash($resp_line);
    return $resp_hash;
}

sub create_listener_socket_for_pid{
    my $pid = shift;
    my $socket_path = cells::socket_path_for_pid($pid);
    cells::ensure_parent_dir_exist($socket_path);

    unlink($socket_path);

    my $listener = IO::Socket::UNIX->new(
       Type   => SOCK_STREAM,
       Local  => $socket_path,
       Listen => SOMAXCONN,
    ) or die("Can't create server socket: $!\n");
    return $listener;
}

1;