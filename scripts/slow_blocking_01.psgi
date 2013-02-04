use strictures;

my $app = sub {
  sleep 5;
  return [200, ['Content-Type'=>'text/plain'],
  ["Hello World!\n"]];
};
