BEGIN {print "1..2\n";}
END {print "not ok 1\n" unless $loaded;}
use XML::Parser;
$loaded = 1;
print "ok 1\n";

my $cnt = 0;

sub docnt {
  $cnt++;
}

my $p = new XML::Parser(Handlers => {Comment => \&docnt});

my $xpnb = $p->parse_start;

open(REC, 'samples/REC-xml-19980210.xml');

while (<REC>) {
  $xpnb->parse_more($_);
}

close(REC);

$xpnb->parse_done;

print "not " unless $cnt == 37;
print "ok 2\n";


