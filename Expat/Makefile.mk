# This Makefile is for the XML::Parser::Expat extension to perl.
#
# It was generated automatically by MakeMaker version
# 2.30 (Revision: ) from the contents of
# Makefile.PL. Don't edit this file, edit Makefile.PL instead.
#
#	ANY CHANGES MADE HERE WILL BE LOST!
#
#   MakeMaker Parameters:

#	C => [q[Expat.c]]
#	LIBS => q[-lexpat]
#	NAME => q[XML::Parser::Expat]
#	VERSION_FROM => q[Expat.pm]
#	XSPROTOARG => q[-noprototypes]

# --- MakeMaker constants section:
NAME = XML::Parser::Expat
DISTNAME = XML-Parser-Expat
NAME_SYM = XML_Parser_Expat
VERSION = 2.30
VERSION_SYM = 2_30
XS_VERSION = 2.30
INST_LIB = MacintoshHD:MacPerl Ä:site_perl
INST_ARCHLIB = MacintoshHD:MacPerl Ä:site_perl
PERL_LIB = MacintoshHD:MacPerl Ä:site_perl
PERL = miniperl
FULLPERL = perl
XSPROTOARG = -noprototypes
SOURCE =  Expat.c

MODULES = Expat.pm


.INCLUDE : $(PERL_SRC)BuildRules.mk


# FULLEXT = Pathname for extension directory (eg DBD:Oracle).
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
# ROOTEXT = Directory part of FULLEXT (eg DBD)
# DLBASE  = Basename part of dynamic library. May be just equal BASEEXT.
FULLEXT = XML:Parser:Expat
BASEEXT = Expat
ROOTEXT = XML:Parser:

# Handy lists of source code files:
XS_FILES= Expat.xs \
	Expat_68K.xs
C_FILES = Expat.c
H_FILES = encoding.h


.INCLUDE : $(PERL_SRC)ext:ExtBuildRules.mk


# --- MakeMaker dist section skipped.

# --- MakeMaker dlsyms section:

dynamic :: Expat.exp


Expat.exp: Makefile.PL
	$(PERL) "-I$(PERL_LIB)" -e 'use ExtUtils::Mksymlists; Mksymlists("NAME" => "XML::Parser::Expat", "DL_FUNCS" => {  }, "DL_VARS" => []);'


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
	$(RM_RF) Expat_68K.c Expat.c
	$(MV) Makefile.mk Makefile.mk.old


# --- MakeMaker realclean section:

# Delete temporary files (via clean) and also delete installed files
realclean purge ::  clean
	$(RM_RF) Makefile.mk Makefile.mk.old


# --- MakeMaker dist_basics section skipped.

# --- MakeMaker dist_core section skipped.

# --- MakeMaker dist_dir section skipped.

# --- MakeMaker dist_test section skipped.

# --- MakeMaker dist_ci section skipped.

# --- MakeMaker install section skipped.

# --- MakeMaker postamble section:


# --- MakeMaker rulez section:

install install_static install_dynamic :: 
	$(PERL_SRC)PerlInstall -l $(PERL_LIB)
	$(PERL_SRC)PerlInstall -l "MacintoshHD:MacPerl Ä:site_perl:"

.INCLUDE : $(PERL_SRC)BulkBuildRules.mk


# End.
