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
