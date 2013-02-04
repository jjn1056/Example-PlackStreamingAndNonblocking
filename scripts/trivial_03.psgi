use strictures;

my $app = sub {
  return sub {
    my $writer = (my $responder = shift)->(
      [ 200, [ 'Content-Type' => 'text/plain' ]]);

    $writer->write("Hello World!\n");
    $writer->close;
  };
};
