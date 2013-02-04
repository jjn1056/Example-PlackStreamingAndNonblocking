use strictures;
use AnyEvent;
use AnyEvent::Handle;

my $message = "Hello World!";

my $app = sub {

  open(my $fh, "<", \$message);

  return sub {
    my $writer = (my $responder = shift)->(
      [ 200, [ 'Content-Type' => 'text/plain' ]]);

    my $cb = sub {
      my $message = shift;
      $writer->write($message);
      $writer->close;
    };

    my $hd; $hd = AnyEvent::Handle->new(
      fh => $fh,
      on_error => sub {
        my ($hdl, $fatal, $msg) = @_;
        AE::log error => $msg;
        $hd->destroy;
      },
      on_read => sub {
        $cb->("fffff");
        undef $hd;
      },
    );

    
  };
};
