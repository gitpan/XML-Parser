BEGIN {print "1..6\n";}
END {print "not ok 1\n" unless $loaded;}
use XML::Parser;
$loaded = 1;
print "ok 1\n";

my $doc =<<'End_of_doc;';
<?xml version="1.0" encoding="ISO-8859-1"?>
<!DOCTYPE foo SYSTEM "t/foo.dtd"
  [
    <!ENTITY % foo "IGNORE">
    <!ENTITY % bar "INCLUDE">
  ]
>
<foo>Happy, happy
<bar>&joy;, &joy;</bar>
</foo>
End_of_doc;


my $gotinclude = 0;
my $gotignore = 0;

my $bartxt = '';

sub start {
  my ($xp, $el, %atts) = @_;

  if ($el eq 'foo') {
    print "not " if defined($atts{top});
    print "ok 2\n";
  }
  elsif ($el eq 'bar') {
    print "not " unless (defined $atts{xyz} and $atts{xyz} eq 'b');
    print "ok 3\n";
  }
}

sub char {
  my ($xp, $text) = @_;

  $bartxt .= $text if $xp->current_element eq 'bar';
}

sub attl {
  my ($xp, $el, $att, $type, $dflt, $fixed) = @_;

  $gotinclude = 1 if ($el eq 'bar' and $att eq 'xyz' and $dflt eq "'b'");
  $gotignore = 1 if ($el eq 'foo' and $att eq 'top' and $dflt eq '"hello"');
}

$p = new XML::Parser(ParseParamEnt => 1,
		     ErrorContext  => 2,
		     Handlers => {Start   => \&start,
				  Char    => \&char,
				  Attlist => \&attl
				 }
		    );

$p->parse($doc);

print "not " unless $bartxt eq "\xe5\x83\x96, \xe5\x83\x96";
print "ok 4\n";

print "not " unless $gotinclude;
print "ok 5\n";

print "not " if $gotignore;
print "ok 6\n";
