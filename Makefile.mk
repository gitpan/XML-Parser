# This Makefile is for the XML::Parser extension to perl.
#
# It was generated automatically by MakeMaker version
# 2.30 (Revision: ) from the contents of
# Makefile.PL. Don't edit this file, edit Makefile.PL instead.
#
#	ANY CHANGES MADE HERE WILL BE LOST!
#
#   MakeMaker Parameters:

#	DIR => [q[Expat]]
#	NAME => q[XML::Parser]
#	VERSION_FROM => q[Parser.pm]
#	dist => { COMPRESS=>q[gzip], SUFFIX=>q[.gz] }

# --- MakeMaker constants section:
NAME = XML::Parser
DISTNAME = XML-Parser
NAME_SYM = XML_Parser
VERSION = 2.30
VERSION_SYM = 2_30
XS_VERSION = 2.30
INST_LIB = MacintoshHD:MacPerl Ä:site_perl
INST_ARCHLIB = MacintoshHD:MacPerl Ä:site_perl
PERL_LIB = MacintoshHD:MacPerl Ä:site_perl
PERL = miniperl
FULLPERL = perl

MODULES = :Parser:Encodings:Japanese_Encodings.msg \
	:Parser:Encodings:README \
	:Parser:Encodings:big5.enc \
	:Parser:Encodings:euc-kr.enc \
	:Parser:Encodings:iso-8859-2.enc \
	:Parser:Encodings:iso-8859-3.enc \
	:Parser:Encodings:iso-8859-4.enc \
	:Parser:Encodings:iso-8859-5.enc \
	:Parser:Encodings:iso-8859-7.enc \
	:Parser:Encodings:iso-8859-8.enc \
	:Parser:Encodings:iso-8859-9.enc \
	:Parser:Encodings:windows-1250.enc \
	:Parser:Encodings:x-euc-jp-jisx0221.enc \
	:Parser:Encodings:x-euc-jp-unicode.enc \
	:Parser:Encodings:x-sjis-cp932.enc \
	:Parser:Encodings:x-sjis-jdk117.enc \
	:Parser:Encodings:x-sjis-jisx0221.enc \
	:Parser:Encodings:x-sjis-unicode.enc \
	:Parser:LWPExternEnt.pl \
	Parser.pm
PMLIBDIRS = Parser


.INCLUDE : $(PERL_SRC)BuildRules.mk


# FULLEXT = Pathname for extension directory (eg DBD:Oracle).
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
# ROOTEXT = Directory part of FULLEXT (eg DBD)
# DLBASE  = Basename part of dynamic library. May be just equal BASEEXT.
FULLEXT = XML:Parser
BASEEXT = Parser
ROOTEXT = XML:

# Handy lists of source code files:
XS_FILES= 
C_FILES = 
H_FILES = 


.INCLUDE : $(PERL_SRC)ext:ExtBuildRules.mk


# --- MakeMaker dlsyms section:

dynamic :: Parser.exp


Parser.exp: Makefile.PL
	$(PERL) "-I$(PERL_LIB)" -e 'use ExtUtils::Mksymlists; Mksymlists("NAME" => "XML::Parser", "DL_FUNCS" => {  }, "DL_VARS" => []);'


# --- MakeMaker dynamic section:

all :: dynamic

install :: do_install_dynamic

install_dynamic :: do_install_dynamic


# --- MakeMaker static section:

all :: static

install :: do_install_static

install_static :: do_install_static


# --- MakeMaker clean section:

# Delete temporary files but do not touch installed files. We don't delete
# the Makefile here so a later make realclean still has a makefile to use.

clean ::
	Set OldEcho {Echo}
	Set Echo 0
	Directory Expat
	If "`Exists -f Makefile.mk`" != ""
	    $(MAKE) clean
	End
	Set Echo {OldEcho}
		$(RM_RF) 
	$(MV) Makefile.mk Makefile.mk.old


# --- MakeMaker realclean section:

# Delete temporary files (via clean) and also delete installed files
realclean purge ::  clean
	Set OldEcho {Echo}
	Set Echo 0
	Directory Expat
	If "`Exists -f Makefile.mk.old`" != ""
	    $(MAKE) realclean
	End
	Set Echo {OldEcho}
		Set OldEcho {Echo}
	Set Echo 0
	Directory Expat
	If "`Exists -f Makefile.mk`" != ""
	    $(MAKE) realclean
	End
	Set Echo {OldEcho}
		$(RM_RF) Makefile.mk Makefile.mk.old


# --- MakeMaker postamble section:


# --- MakeMaker rulez section:

install install_static install_dynamic :: 
	$(PERL_SRC)PerlInstall -l $(PERL_LIB)
	$(PERL_SRC)PerlInstall -l "MacintoshHD:MacPerl Ä:site_perl:"

.INCLUDE : $(PERL_SRC)BulkBuildRules.mk


# End.
