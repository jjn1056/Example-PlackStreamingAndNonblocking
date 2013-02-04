package Example::PlackStreamingAndNonblocking;

use Pod::Markdown;
use strictures;

(caller() ? 1 : do {
  (my $parser = Pod::Markdown->new)
    ->parse_from_file(__FILE__);
  print $parser->as_markdown });

=head1 NAME

Example::PlackStreamingAndNonblocking - About Plack / PSGI Streaming and nonblocking

=head1 DESCRIPTION

This article reviews the hows and whys of L<Plack> streaming and nonblocking
for the perspective of someone who is very unfamiliar with the topic, but has
experience with Perl and understands the basics of L<Plack>.  It takes the form
of a tutorial starting from a basic Plack application, and introduces both non
blocking and streaming concept using L<AnyEvent>.

The goals of these examples is to help the reader understand the problems we are
trying to solve using streaming and / or non blocking coding techniques, more 
then to give example cookbook style code.  As a result some of the examples
will be somewhat contrived for the purposes of eludication.

It would be helpful to have read the L<PSGI> specification, although you are not
expected to fully grasp all of it.  Some familiarity with the documentation
and tutorial of L<AnyEvent> would also assist you.

=head1 INTRODUCTION

Unless you are a Perl programmer who is very isolated from the broad trends of
community, you will have heard of L<PSGI> and its reference implementation,
L<Plack>, which has rapidly become a key element of best practices in building web
applications.  In summary, L<Plack> is 'superglue' which connects your web
application to an underlying server (thus making it available to consumers on
the internet or your local network.  In addition to this standard approach of
making your application 'internet ready', it provides an interface in which
shared middleware components can be used and reused across your applications
irrespective of what web development framework you are using.

Some parts of the L<PSGI> specification are easy to understand and can be
rapidly used by even newcomers to the language. One can write a well formed
Perl / Plack application in a few lines of code (C<scripts/trivial_01.psgi>);

    use strictures;

    my $app = sub {
      return [200, ['Content-Type'=>'text/plain'],
      ["Hello World!\n"]];
    };

If one ran the following application from the commandline, you could interact
with it from even a simple telnet prompt.

(In terminal one)

    $ plackup scripts/trivial_01.psgi 
    HTTP::Server::PSGI: Accepting connections at http://0:5000/

(In terminal two)

    $ telnet 127.0.0.1 5000
    Trying 127.0.0.1...
    Connected to localhost.
    Escape character is '^]'.
    GET / HTTP/1.0

    HTTP/1.0 200 OK
    Date: Sun, 03 Feb 2013 21:39:20 GMT
    Server: HTTP::Server::PSGI
    Content-Type: text/plain
    Content-Length: 12

    Hello World!
    Connection closed by foreign host.
    $ 

You can see a screen video capture of this very procedure in the C<share/videos/>
directory of this distribution.  Each code example will have a corresponding
example in this directory.

So, as I said, that part is easy, and it a key reason for L<PSGI> and L<Plack>
to have so seriously impacted Perl web application development.  However, there
are two interrelated parts of the L<PSGI> specification which are not always
as readily accessible to understanding.  That is Streaming and Non-blocking.
Documentation shows how the specification works, but it leaves out some
information about the point of using it, and when to use it over other possible
approaches.  This article will review Streaming and nonblocking code both
separately and interrelated, as well as try to help you understand when and why
you'd adopt this approach to building you application.

=head1 The Classic Approach to Web Scale

Before we can understand why we'd use L<PSGI> streaming and / or non blocking
approaches in our web applications, we need to step back and understand how web
technologies first evolved and how those technologies tried to meet ever growing
needs for scale and complexity.  Because in the end it doesn't matter how an
application is written if no one can access it, or if it performs so slowly as
to put an onerous burden on the user.

When I first began building web applications a standard approach would be to
use a forking webserver, such as Apache, which was a container for my web
application.  'Forking' is a type of technique that an operating system uses
to allow it to do (or appear to do) several things at once. In this type of
application Apache would 'fork' serveral processes, including a control process
which is responsible for launching additional child processes which each then
listens for connections and serves them when they arrive.

So for example say you have Apache with 10 child processes listening on port
80 for incoming web requests.  The first 10 requests that come in would all
get served immediately.  Now, as long as your application serves the response
quickly and the number in incoming requests are low, this model works very well
since nobody would seem to be required to wait for a response.

Think about it in more details.  Lets say you have Apache setup with ten
child processes each ready and waiting to response to an incoming request.  Let's
furthermore say that your response is well optimized, and only takes one tenth
of a second to complete.  That means in theory you could served a maximum of
100 requests per second (each process could serve 10 reponses in a second and
you have 10 processed running, 10*10=100).

In real life you are very likely to do worse, since you may have a very slow
client requesting a file (say someone on a 14.4K modem), or other network
congestion issues.  To some degree you can mitigate the problem using front
end caching proxies, and you can straightforwardly scale by adding more web
servers with load balancing systems to give the appearance of one big server,
but in the end you are ultimately going to have a fixed number of possible
simultaneous responses.  That is because in this model the request - response
B<blocks> the system, such that until it is finished that process is totally
tied up and not available to any other request.

Futhermore, modern web applications are being write that now require perhaps
several running connections per client.  Think about a modern interative
web application like Gmail.  Such an application might require several, long
running connections per client.  Under the classic blocking model you might
need many, many servers running in order to provide enough open, waiting
processes (think millions of people checking Gmail daily.

Lets build a simple plack application that shows the experience when lots
of people try to access a forking server all at once.  Lets furthermore
say that the server is doing some 'heavy lifting' and that the process
takes 5 seconds of work before it actually can response.  Here's the code
and you can see  it in C<scripts/slow_blocking_01.psgi>.

    use strictures;

    my $app = sub {
      sleep 5;
      return [200, ['Content-Type'=>'text/plain'],
      ["Hello World!\n"]];
    };

So, here I do C<sleep 5> to cause a five second delay before responding.  This
is contrived but certainly possible if you have an application that does a lot
of database checks and processing before responding.  Lets run this application
under C<Starman> which is a preforking server (it by default preforks 5 times
and thus can serve 5 requests at a time).  We will use Apache ab to access the
server 100 times with a concurrency of 100 (in other words one hundred total
requests to the server, and one hundred clients trying to hit the server at once.

Can you guess how long this test will take to complete?

As before, see C<share/videos> for screencast.

(In terminal one)

    $ plackup scripts/slow_blocking_01.psgi --server Starman
    2013/02/03-17:52:32 Starman::Server (type Net::Server::PreFork) starting! pid(11719)
    Resolved [*]:5000 to [0.0.0.0]:5000, IPv4
    Binding to TCP port 5000 on host 0.0.0.0 with IPv4
    Setting gid to "20 20 20 12 61 79 80 81 98"
    Starman: Accepting connections at http://*:5000/

(In terminal two)

    $ ./ab -n 100 -c 100 http://127.0.0.1:5000/
    This is ApacheBench, Version 2.3 <$Revision: 1178079 $>
    Benchmarking 127.0.0.1 (be patient).....done
        
    Server Hostname:        127.0.0.1
    Server Port:            5000

    Document Path:          /
    Document Length:        13 bytes

    Concurrency Level:      100
    Time taken for tests:   100.062 seconds
    Complete requests:      100
    Failed requests:        0
    Write errors:           0
    Total transferred:      11400 bytes
    HTML transferred:       1300 bytes
    Requests per second:    1.00 [#/sec] (mean)
    Time per request:       100062.073 [ms] (mean)
    Time per request:       1000.621 [ms] (mean, across all concurrent requests)
    Transfer rate:          0.11 [Kbytes/sec] received

If you watch the video (or run it yourself) you can see the L<Starman> running
application serve 5 requests, block for a few seconds, serve 5 more, etc.
until you serve the last bunch.  In the end the whole things takes about 100
seconds (think 5 seconds and you handle 5 at a time, so thats 20 bunches = 100
seconds give or take a bit of overhead).

Ok, so again, that example was a bit contrived, and yes there are many many
things you can do when using a pre-forking server like L<Starman> or Apache
to help scale.  You can more static assets to stand alone servers or onto a
CDN network like Akamai, you can move computational expensive server jobs to
stand alone job queues, you can use front edge caching to speed up the bits
that don't get updated a lot, etc.  In fact, I spent and spend a lot of time
advising people just how to achieve scale using this very type of technology.
So I am not saying its bad technology and that there's no available options
when faced with these types of issues.  However for certain types of web
applications that we are writing today, applications like Gmail where you
mght have tens or hundreds of thousands clients hitting your servers all at
once, its going to get complicated and possible very expensive.  If your
application has high variation in usage patterns, you might have a lot of
expensive equipment just sitting around during those low usage times.

So, what to do?

=head1 Nonblocking with AnyEvent

The root issue in the classic approach to web scale lies in how each of the
forked processes block until the entire request response cycle is completed.
During that time, the process is basically owned by the client making the
request.  This places an uppper limited on both the number of responses you can
serve in a second as well as the total number of clients you can server at the
same time.

That bears repeating because there is a difference between an application that
can server a lot of reponses per second, and one that can server many clients
at the same time.  Remember, if you have an Apache server with a process that
takes 1/10 second and ten forked children ready to go, thats a peak one hundred
requests per second, but no more than 10 at one time.

So if issue is blocking, what to do?

Perl offers several approaches to building non-blocking applications, and L<Plack>
supports this.  We will use L<AnyEvent> since that system is well supported and
there is documentation around to help out.

L<AnyEvent> is a sort of common API on top of many possible event loops, which
makes it easy to get started.  The idea behind the event loop is that you build
an application that responds to events, but the actual response processing does
not need to block the rest of the application.  It does this by using a feature
of modern operating systems that lets it switch very quickly under the covers,
thus giving the appearance of many things happening all at the same time.

Now, remember, using an event loop like this is not some magic way to find
power your server does not already have.  At best it just lets you make more
efficient usage of what you already have.  So that means at some point as you
add more and more event actions running all at once, you will eventually start
to see the server slowdown.  BUT, the key is it will slowdown and continue to
non block, rather than make other pending request wait around.  This can give
the appearance of being able to serve many many more clients all at the same
time, unlike in the previous example, where the last group of 5 request had to
wait nearly 100 seconds before even having their request acknowledged (and my
server was 99.9% idle).

Let's translate the previous example of a slow application. You can see the
code as well in C<scripts/long_job_anyevent.psgi>.  I'll start with the end
goal and then we will back up and follow the thinking that got us there.

    use AnyEvent;
    use strictures;
      
    my $app = sub {
      my $env = shift;
     
      return sub {
        my $writer = (my $responder = shift)->(
          [ 200, [ 'Content-Type', 'text/plain' ]]);
     
        $writer->write("Starting: ${\scalar(localtime)}\n");

        my $cb = sub {
          my $message = shift;
          $writer->write("Finishing: $message\n");
          $writer->close;
        };
     
       my $watcher;
       $watcher = AnyEvent->timer(
        after => 5,
        cb => sub {
          $cb->(scalar localtime);
          undef $watcher; # cancel circular-ref
        });

      };
    };

Now, I've added a few extra bits of output so as to make it easier to see what
is going on, but overall there's quite a bit more complexity here.  Let's try
to break it down a bit.  In the introduction we used the most simple form of a
L<PSGI> appliction, which as you recalled looked like this:

    use strictures;

    my $app = sub {
      return [200, ['Content-Type'=>'text/plain'],
      ["Hello World!\n"]];
    };

Basically we have an anonymous subroutine that gets executed for each request
being handled.  This subroutine is required to return an arrayref of three
parts, an Integer which is a valid HTTP status code number, an arrayref of
pairs being the key / value parts of HTTP headers, and an arrayref (or a file
handle) which is the actual body content of the response.

However, if the server supports it, you can instead of the three item Tuple
return a second subroutine, which is a delayed response that the server executes
when it is ready.  The idea here is to defer processing of the request / response.
So you could rewrite this application as follows (c<scripts/trivial_02.psgi>).

    use strictures;

    my $app = sub {
      return sub {
        (my $responder = shift)->([200,
          ['Content-Type'=>'text/plain'],
          ["Hello World!\n"]]);
      }
    };

So, doing this alone doesn't really buy you a lot, but it is the basis for our
nonblocking application as well as our streaming example, which we'll get to
later on in the article.

The key to the non blocking example is to notice that when calling the C<$responder>
coderef, we are passing only part of the response, the HTTP status codes and
the HTTP Header meta data pairs.  When C<$responder is called like this, you
get a C<$writer> object that you can use to send the HTTP body response.  You do
so by calling the ->write method on it.  You can repeatedly call ->write until
you are finished, at which point you need to signal the server that you are done
by calling ->close.  So Here's a sort of ultimate version of the trivial application
using the delayed response and the streaming interface:

    use strictures;

    my $app = sub {
      return sub {
        my $writer = (my $responder = shift)->(
          [ 200, [ 'Content-Type' => 'text/plain' ]]);

        $writer->write("Hello World!\n");
        $writer->close;
      };
    };

As written this again is not really buying you anything, although if the body
of the response was large you could use this as a way to serve 'chunks' of it
which might reduce the memory footprint of the application.  We'll talk more
about streaming in a bit, but the key here is that the application is still a
blocking appliction, even though it is using the delayed and even streaming
response approach.  If you want non-blocking, you have to take this a step
further and involve an eventloop framework like L<AnyEvent>.  Lets see what
that would look like

    use strictures;

    my $app = sub {
      sleep 5;
      return [200, ['Content-Type'=>'text/plain'],
      ["Hello World!\n"]];
    };

As follows


    use strictures;

    my $app = sub {
      return sub {
        (my $responder = shift)->([200,
          ['Content-Type'=>'text/plain'],
          ["Hello World!\n"]]);
      }
    };



-high concurrany
-very dynamic or realtime data (not suitable for caching)
-each client needs lots of connections

is not a panacea
can play nice with other 'classic' scale techniques, job queues, caching,
even proxies to help deal with slow clients



=head1 SEE ALSO

The following modules or resources may be of interest.

L<Plack>, L<AnyEvent>, L<strictures>

=head1 AUTHOR

    John Napiorkowski C<< <jjnapiork@cpan.org> >>

=head1 COPYRIGHT & LICENSE

    Copyright 2013, John Napiorkowski C<< <jjnapiork@cpan.org> >>

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


