use ExtUtils::MakeMaker;
use Config;
use English;

$define = '';

if ($PERL_VERSION >= 5.005) {
    $define = '-DHAS_NEWSVPVN ';
}

$define .= ($Config{cc} =~ /cl\.exe/i) ? '/Fo$@' : '-o $@';

@expat_files = qw(expat/xmltok/xmltok.c expat/xmltok/xmlrole.c
                  expat/xmlparse/xmlparse.c expat/xmlparse/hashtable.c);

@extras = ();

push(@extras,
     CAPI => 'TRUE')
    if ($PERL_VERSION >= 5.005 and $OSNAME eq 'MSWin32'
	and $Config{archname} =~ /-object\b/i);

push(@extras,
     ABSTRACT => "Lowlevel access to James Clark's expat XML parser",
     AUTHOR        => 'Clark Cooper (coopercl@sch.ge.com)')
    if ($ExtUtils::MakeMaker::Version >= 5.4301);
     
WriteMakefile(
              NAME	=> 'XML::Parser::Expat',
	      C       => ['Expat.c', @expat_files],
              OBJECT    => '$(O_FILES)',
              DEFINE    => $define,
	      clean     => {FILES => 'expat/xml*/*.o'},
              INC       => "-Iexpat/xmltok -Iexpat/xmlparse",
              XSPROTOARG => '-noprototypes',
              VERSION_FROM => 'Expat.pm',
	      @extras
             );

