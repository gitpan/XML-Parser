BEGIN {print "1..14\n";}
END {print "not ok 1\n" unless $loaded;}
use XML::Parser;
$loaded = 1;
print "ok 1\n";

my $docstr =<<'End_of_Doc;';
<?xml version="1.0" encoding="US-ASCII" ?>
<!DOCTYPE foo SYSTEM 'foo.dtd'
  [
   <!ENTITY alpha 'a'>
   <!ELEMENT junk (bar|xyz+)>
   <!ATTLIST junk
         id ID #REQUIRED
         version CDATA #FIXED '1.0'
         color (red|green|blue) 'green'>
   <!ENTITY skunk "stinky animal">
   <!-- a comment -->
   <!NOTATION gif SYSTEM 'http://www.somebody.com/specs/GIF31.TXT'>
   <!ENTITY logo PUBLIC '//Widgets Corp/Logo' 'logo.gif' NDATA gif>
   <?DWIM a useless processing instruction ?>
   <!ELEMENT bar ANY>
  ]>
<foo/>
End_of_Doc;

my $entcnt = 0;
my %ents;
my @tests;

my $equivstr;

sub dh {
    my ($p, $data) = @_;

    $equivstr = $data;
}

sub eleh {
    my ($p, $name, $model) = @_;

    if ($name eq 'junk' and $model eq '(bar|xyz+)') {
	$tests[2]++;
	$p->default_current;
	$tests[3]++ if $equivstr eq '<!ELEMENT junk (bar|xyz+)>';
    }

    $tests[4]++ if ($name eq 'bar' and $model eq 'ANY');
}

sub enth {
    my ($p, $name, $val, $sys, $pub, $notation) = @_;

    $tests[5]++ if ($name eq 'alpha' and $val eq 'a');
    $tests[6]++ if ($name eq 'skunk' and $val eq 'stinky animal');
    $tests[7]++ if ($name eq 'logo' and !defined($val) and
		    $sys eq 'logo.gif' and $pub eq '//Widgets Corp/Logo'
		    and $notation eq 'gif');
}

sub doc {
    my ($p, $name, $sys, $pub, $intdecl) = @_;

    $tests[8]++ if $name eq 'foo';
    $tests[9]++ if $sys eq 'foo.dtd';
    $tests[10]++ if length($intdecl) == 439;
}

sub att {
    my ($p, $elname, $attname, $type, $default, $fixed) = @_;

    $tests[11]++ if ($elname eq 'junk' and $attname eq 'id'
		     and $type eq 'ID' and $default eq '#REQUIRED'
		     and not $fixed);
    $tests[12]++ if ($elname eq 'junk' and $attname eq 'version'
		     and $type eq 'CDATA' and $default eq "'1.0'" and $fixed);
    $tests[13]++ if ($elname eq 'junk' and $attname eq 'color'
		     and $type eq '(red|green|blue)'
		     and $default eq "'green'");
}
    
sub xd {
    my ($p, $version, $enc, $stand) = @_;

    if ($version eq '1.0' and $enc eq 'US-ASCII' and not defined($stand)) {
	$tests[14]++;
    }
}

my $parser = new XML::Parser(ErrorContext => 2);

$parser->setHandlers(Entity  => \&enth,
		     Element => \&eleh,
		     Attlist => \&att,
		     Doctype => \&doc,
		     XMLDecl => \&xd,
		     Default => \&dh);

$parser->parse($docstr);

for (2 .. 14) {
    print "not " unless $tests[$_];
    print "ok $_\n";
}
