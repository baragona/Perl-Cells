#!/usr/bin/perl -w
use strict;
#use CGI::Application::PSGI;
use HTTP::Server::PSGI;

# my $psgi = sub {
#   my $env = shift;
#   my $app = PerlCellsWebApp->new({ QUERY => CGI::PSGI->new($env) });
#   CGI::Application::PSGI->run($app);
# };

my $psgi = PerlCellsWebApp->psgi_app();
my $server = HTTP::Server::PSGI->new(
  host => "127.0.0.1",
  port => 9091,
  timeout => 120,
);

$server->run($psgi);

#PerlCellsWebApp->new()->run;
# ----------------------------------------------------------
package PerlCellsWebApp;
use base 'CGI::Application';
use CGI::Application::Plugin::AutoRunmode;
use CGI::Carp qw(fatalsToBrowser);

sub default_runmode : StartRunmode {
  my $self = shift;
  my $q = $self->query;
  my $output = _page_header()
      . $q->div({-id=>'box1'},'This is div1')
      . $q->div({-id=>'box2'},'Another div, div2')
      . $q->button(-id=>'b1', -value=>'Alter div1')
      . $q->button(-id=>'b2', -value=>'Alter div2')
}
sub ajax_alter_div1 : Runmode {
  my $self = shift;
  scalar localtime . $self->query->p('Look Ma, no page reload!');;
}
sub ajax_alter_div2 : Runmode {
  my $self = shift;
  reverse $self->query->param('some_text');
}

sub _page_header {
  return '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
  <title>CGI-Application and jQuery</title>
  <meta http-equiv="Content-Language" content="en-us" />
  <style type="text/css">
      body { background-color: #eee }
      #box1, #box2 { border: 1px solid gray; width: 200px; height: 50px; padding: 4px; margin: 10px; }
      #box2        { border: 1px solid blue; }
  </style>
  <script type="text/javascript" src="/js/jquery-1.3.2.min.js"></script>
  <script type="text/javascript">
    $(function(){
      $("#b1").click(function() {
          $("#box1").load(
              "my_ajax.cgi",
              { rm: "ajax_alter_div1" }
              )
      });
      $("#b2").click(function() {
          $("#box2").load(
              "my_ajax.cgi",
              { rm: "ajax_alter_div2", some_text: $("#box2").text() }
              )
      });
    });
    </script>
</head>
';
}