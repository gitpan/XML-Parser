BEGIN {print "1..7\n";}
END {print "not ok 1\n" unless $loaded;}
use XML::Parser;
$loaded = 1;
print "ok 1\n";

################################################################
# Check namespaces

$docstring =<<'End_of_doc;';
<!-- 1 --> <RESERVATION xmlns:HTML="http://www.w3.org/TR/REC-html40">
 <!-- 2 --> <NAME HTML:CLASS="largeSansSerif">Layman, A</NAME>
 <!-- 3 --> <SEAT CLASS="Y" HTML:CLASS="largeMonotype">33B</SEAT>
 <!-- 4 --> <HTML:A HREF='/cgi-bin/ResStatus'>Check Status</HTML:A>
 <!-- 5 --> <DEPARTURE>1997-05-24T07:55:00+1</DEPARTURE></RESERVATION>
End_of_doc;

my $gname;

sub start
{
    my $p = shift;
    my $el = shift;
    if ($el eq 'SEAT')
    {
	print "not " unless $_[0] eq $_[2];
	print "ok 2\n";

	print "not " if $p->eq_name($_[0], $_[2]);
	print "ok 3\n";

	print "not "
	    unless $p->namespace($_[2]) eq 'http://www.w3.org/TR/REC-html40';
	print "ok 4\n";

	print "not " if $p->namespace($el);
	print "ok 5\n";

	print "not " unless $p->eq_name($gname, $_[2]);
	print "ok 6\n";
    }

    if ($el eq 'A')
    {
	print "not "
	    unless $p->namespace($el) eq 'http://www.w3.org/TR/REC-html40';
	print "ok 7\n";
    }
}

sub init
{
  my $p = shift;

  $gname = $p->generate_ns_name('CLASS', 'http://www.w3.org/TR/REC-html40');
}

$parser = new XML::Parser(Namespaces => 1,
			  Handlers => {Start => \&start, Init => \&init}
			  );

$parser->parse($docstring);
