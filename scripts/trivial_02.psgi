use strictures;

my $app = sub {
  return sub {
    (my $responder = shift)->([200,
      ['Content-Type'=>'text/plain'],
      ["Hello World!\n"]]);
  }
};
