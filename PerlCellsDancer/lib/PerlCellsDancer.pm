package PerlCellsDancer;
use Dancer2;

our $VERSION = '0.1';

use Data::Dumper;
use JSON::PP();
use Try::Tiny;
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
        my $resp;
        my $server_err;
        my $js_resp;
        try{
            $resp = cells::send_hash_to_pid_and_wait_for_response($mesg, $pid);
        }catch{
            $server_err = "Error sending message to pid $pid: $_";
        };
        if(not $server_err){
            if(defined $resp){
                try{
                    $js_resp = JSON::PP::encode_json( $resp );
                }catch{
                    $server_err = "JSON Encoding error: $_";
                };
            }else{
                $server_err = "Did not get a response?";
            }
        }
        if($server_err){
            status 500;
            return $server_err;
        }else{
            return $js_resp;
        }
    }else{
        status 500;
        return "No process to send commands to.";
    }

};

true;
