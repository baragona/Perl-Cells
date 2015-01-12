package PerlCellsDancer;
use Dancer2;

our $VERSION = '0.1';

use Data::Dumper;
use JSON::PP();

use cells;


get '/' => sub {
    template 'index';
};

get '/start' => sub {
    template 'start' =>{
        first_code => ' "Enter some perl code here to run it!" ',
    };
};

post '/run_code' => sub{
    my $code = param "code";

    if(not defined $code){
        status 400; #bad request
        return "You didn't give any code to run";
    }

    my @pids = cells::get_active_pids();

    #print Dumper \@pids;

    my $pid = cells::get_default_pid_to_send_commands_to();
    if($pid){
        my $mesg = {code => $code};
        my $resp = cells::send_hash_to_pid_and_wait_for_response($mesg, $pid);
        return JSON::PP::encode_json( $resp );
    }else{
        status 500;
        return "No process to send commands to.";
    }

};

true;
