# This Makefile is for the XML::Parser::Expat extension to perl.
#
# It was generated automatically by MakeMaker version
# 2.31 (Revision: ) from the contents of
# Makefile.PL. Don't edit this file, edit Makefile.PL instead.
#
#	ANY CHANGES MADE HERE WILL BE LOST!
#
#   MakeMaker Parameters:

#	ABSTRACT => q[Lowlevel access to James Clark's expat XML parser]
#	AUTHOR => q[Clark Cooper (coopercc@netheaven.com)]
#	C => [q[Expat.c]]
#	LIBS => q[-lexpat]
#	NAME => q[XML::Parser::Expat]
#	VERSION_FROM => q[Expat.pm]
#	XSPROTOARG => q[-noprototypes]

# --- MakeMaker constants section:
NAME = XML::Parser::Expat
DISTNAME = XML-Parser-Expat
NAME_SYM = XML_Parser_Expat
VERSION = 2.31
VERSION_SYM = 2_31
XS_VERSION = 2.31
INST_LIB = ::::lib
INST_ARCHLIB = ::::lib
PERL_LIB = ::::lib
PERL_SRC = ::::
MACPERL_SRC = ::::macos:
MACPERL_LIB = ::::macos:lib
PERL = ::::miniperl
FULLPERL = ::::perl
XSPROTOARG = -noprototypes
SOURCE =  Expat.c

MODULES = :Expat.pm \
	Expat.pm


.INCLUDE : $(MACPERL_SRC)BuildRules.mk


VERSION_MACRO = VERSION
DEFINE_VERSION = -d $(VERSION_MACRO)="¶"$(VERSION)¶""
XS_VERSION_MACRO = XS_VERSION
XS_DEFINE_VERSION = -d $(XS_VERSION_MACRO)="¶"$(XS_VERSION)¶""

MAKEMAKER = MacintoshHD:macperl_src:perl561:lib:ExtUtils:MakeMaker.pm
MM_VERSION = 5.45

# FULLEXT = Pathname for extension directory (eg DBD:Oracle).
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
# ROOTEXT = Directory part of FULLEXT (eg DBD)
# DLBASE  = Basename part of dynamic library. May be just equal BASEEXT.
FULLEXT = XML:Parser:Expat
BASEEXT = Expat
ROOTEXT = XML:Parser:
DEFINE =  $(XS_DEFINE_VERSION) $(DEFINE_VERSION)

# Handy lists of source code files:
XS_FILES= Expat.xs
C_FILES = Expat.c
H_FILES = encoding.h \
	expat.h


.INCLUDE : $(MACPERL_SRC)ExtBuildRules.mk


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


# --- MakeMaker htmlifypods section:

htmlifypods : pure_all
	$(NOOP)


# --- MakeMaker processPL section:


# --- MakeMaker clean section:

# Delete temporary files but do not touch installed files. We don't delete
# the Makefile here so a later make realclean still has a makefile to use.

clean ::
	$(RM_RF) Expat.c
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

# --- MakeMaker ppd section:
# Creates a PPD (Perl Package Description) for a binary distribution.
ppd:
	@$(PERL) -e "print qq{<SOFTPKG NAME=\"XML-Parser-Expat\" VERSION=\"2,31,0,0\">\n}. qq{\t<TITLE>XML-Parser-Expat</TITLE>\n}. qq{\t<ABSTRACT>Lowlevel access to James Clark's expat XML parser</ABSTRACT>\n}. qq{\t<AUTHOR>Clark Cooper (coopercc\@netheaven.com)</AUTHOR>\n}. qq{\t<IMPLEMENTATION>\n}. qq{\t\t<OS NAME=\"$(OSNAME)\" />\n}. qq{\t\t<ARCHITECTURE NAME=\"MacPPC\" />\n}. qq{\t\t<CODEBASE HREF=\"\" />\n}. qq{\t</IMPLEMENTATION>\n}. qq{</SOFTPKG>\n}" > XML-Parser-Expat.ppd

# --- MakeMaker postamble section:

# Add Expat.Lib.MrC to the list of MrC libs for building a (dynamic) extension.
# Expat.Lib.MrC has to be built before this Makefile is run; use the MPW Worksheet for PPC in order
# to build Expat.Lib.MrC for MacPerl 5.6.x or 5.8.x (dynamic loading for PPC only)

DYNAMIC_STDLIBS_MRC		+= ":expat-1.95.3:lib:Expat.Lib.MrC"

# --- MakeMaker rulez section:

install install_static install_dynamic :: 
	$(MACPERL_SRC)PerlInstall -l $(PERL_LIB)

.INCLUDE : $(MACPERL_SRC)BulkBuildRules.mk


# End.
