/*****************************************************************
** Expat.xs
**
** Copyright 1998 Larry Wall and Clark Cooper
** All rights reserved.
**
** This program is free software; you can redistribute it and/or
** modify it under the same terms as Perl itself.
**
*/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "patchlevel.h"
#include "xmlparse.h"
#include "encoding.h"

/* Version 5.005_5x (Development version for 5.006) doesn't like sv_...
   anymore, but 5.004 doesn't know about PL_sv..
   Don't want to push up required version just for this. */

#if PATCHLEVEL < 5
#define PL_sv_undef	sv_undef
#define PL_sv_no	sv_no
#define PL_sv_yes	sv_yes
#define PL_na		na
#endif

#define BUFSIZE 32768

#define NSDELIM  '|'

#define DTB_GROW 4096

#define XMLP_UPD(fld) \
  if (cbv->fld) {\
    if (cbv->fld != fld)\
      Perl_sv_setsv(cbv->fld, fld);\
  }\
  else\
    cbv->fld=newSVsv(fld)

/* These are flags set in the dflags field. They indicate whether the
   corresponding handler is set. All these handlers actually use expat's
   default handler. By setting and unsetting these in dflags, we can
   check whether we need to install or uninstall the expat default handler
   with a single look at dflags. */

#define INST_DFL	1
#define INST_ENT	2
#define INST_ELE	4
#define INST_ATT	8
#define INST_DOC	16
#define INST_XML	32
#define INST_DECL	(INST_ENT | INST_ELE | INST_ATT)
#define INST_INDT	(INST_DECL | INST_DOC)
#define INST_LOCAL	(INST_INDT | INST_XML)

typedef enum {
  PS_Initial = 0, PS_Docname, PS_Docextern, PS_Docsysid, PS_Docpubid,
  PS_Internaldecl, PS_Checkinternal, PS_Doctypend, PS_Entityname,
  PS_Elementname, PS_Attelname, PS_Entityval, PS_Entsysid, PS_Entpubid,
  PS_Declend, PS_Entndata, PS_Entnotation, PS_Elcontent, PS_Attdef,
  PS_Atttype, PS_Attmoretype, PS_Attval
} ParseState;

/* Values for which_decl */

#define DECL_INTENT	1
#define DECL_EXTENT	2
#define DECL_ELEMNT	3
#define DECL_ATTLST	4

typedef struct {
  SV* self_sv;
  XML_Parser p;

  AV* context;
  AV* new_prefix_list;
  HV *nstab;
  AV *nslst;

  unsigned int st_serial;
  unsigned int st_serial_stackptr;
  unsigned int st_serial_stacksize;
  unsigned int * st_serial_stack;

  SV *recstring;
  char *buffstrt;
  int bufflen;
  int	offset;
  int prev_offset;
  char * delim;
  STRLEN delimlen;

  unsigned ns:1;
  unsigned no_expand:1;

  unsigned in_local_hndlr:1;
  unsigned start_seen:1;
  unsigned attfixed:1;
  unsigned isparam:1;
  unsigned dflags:6;
  unsigned which_decl:3;

  ParseState local_parse_state;
  char * doctype_buffer;
  STRLEN dtb_offset;
  STRLEN dtb_len;
  STRLEN dtb_limit;

  /* Used by parse_local */

  int docname_offset;
  int docname_len;

  int intsub_offset;
  int intsub_len;

  int docsys_offset;
  int docsys_len;

  int docpub_offset;
  int docpub_len;

  int entnam_offset;
  int entnam_len;

  int entval_offset;
  int entval_len;

  int entsys_offset;
  int entsys_len;

  int entpub_offset;
  int entpub_len;

  int entnot_offset;
  int entnot_len;

  int elnam_offset;
  int elnam_len;

  int model_offset;
  int model_len;

  int attnam_offset;
  int attnam_len;

  int atttyp_offset;
  int atttyp_len;

  /* Callback handlers */

  SV* start_sv;
  SV* end_sv;
  SV* char_sv;
  SV* proc_sv;
  SV* cmnt_sv;
  SV* dflt_sv;

  /* These five are actually dealt with by default handler */

  SV* entdcl_sv;
  SV* eledcl_sv;
  SV* attdcl_sv;
  SV* doctyp_sv;
  SV* xmldec_sv;

  SV* unprsd_sv;
  SV* notation_sv;
  SV* extent_sv;

  SV* startcd_sv;
  SV* endcd_sv;
} CallbackVector;

static long AttDefaultFlag = 0;

static HV* EncodingTable = NULL;


/* Forward declaration */
static void
check_and_set_default_handler(XML_Parser parser,
			      CallbackVector *cbv,
			      int set,
			      unsigned int hflag);

#if PATCHLEVEL >= 5
#define mynewSVpv(s,len) newSVpvn((s),(len))
#else
/* ================================================================
** This is needed where the length is explicitly given. The expat
** library may sometimes give us zero-length strings. Perl's newSVpv
** interprets a zero length as a directive to do a strlen. This
** function is used when we want to force length to mean length, even
** if zero.
*/

static SV *
mynewSVpv(char *s, STRLEN len)
{
  register SV *sv;

  sv = newSV(0);
  sv_setpvn(sv, s, len);
  return sv;
}  /* End mynewSVpv */
#endif

static void
append_error(XML_Parser parser, char * err)
{
  dSP;
  CallbackVector * cbv;
  SV ** errstr;

  cbv = (CallbackVector*) XML_GetUserData(parser);
  errstr = hv_fetch((HV*)SvRV(cbv->self_sv),
		    "ErrorMessage", 12, 0);

  if (errstr && SvPOK(*errstr)) {
    SV ** errctx = hv_fetch((HV*) SvRV(cbv->self_sv),
			    "ErrorContext", 12, 0);
    int dopos = !err && errctx && SvOK(*errctx);

    if (! err)
      err = (char *) XML_ErrorString(XML_GetErrorCode(parser));

    sv_catpvf(*errstr, "\n%s at line %d, column %d, byte %d%s",
	      err,
	      XML_GetCurrentLineNumber(parser),
	      XML_GetCurrentColumnNumber(parser),
	      XML_GetCurrentByteIndex(parser),
	      dopos ? ":\n" : "");

    if (dopos)
      {
	int count;

	ENTER ;
	SAVETMPS ;
	PUSHMARK(sp);
	XPUSHs(cbv->self_sv);
	XPUSHs(*errctx);
	PUTBACK ;

	count = perl_call_method("position_in_context", G_SCALAR);

	SPAGAIN ;

	if (count >= 1) {
	  sv_catsv(*errstr, POPs);
	}

	PUTBACK ;
	FREETMPS ;
	LEAVE ;
      }
  }
}  /* End append_error */

static int
parse_stream(XML_Parser parser, SV * ioref, int close_it)
{
  dSP;
  SV *		tbuff;
  SV *		tsiz;
  char *	linebuff;
  STRLEN	lblen;
  STRLEN	br = 0;
  int		done = 0;
  int		ret = 1;
  char *	msg = NULL;
  CallbackVector * cbv;
  char		*buff = (char *) 0;
  int		leftover = 0;
  char		buffer[BUFSIZE];

  cbv = (CallbackVector*) XML_GetUserData(parser);

  ENTER;
  SAVETMPS;

  if (cbv->delim) {
    int cnt;
    SV * tline;

    PUSHMARK(SP);
    XPUSHs(ioref);
    PUTBACK ;

    cnt = perl_call_method("getline", G_SCALAR);

    SPAGAIN;

    if (cnt != 1)
      croak("getline method call failed");

    tline = POPs;

    if (! SvOK(tline)) {
      lblen = 0;

    }
    else {
      char *	chk;
      linebuff = SvPV(tline, lblen);
      chk = &linebuff[lblen - cbv->delimlen - 1];

      if (lblen > cbv->delimlen + 1
	  && *chk == *cbv->delim
	  && chk[cbv->delimlen] == '\n'
	  && strnEQ(++chk, cbv->delim + 1, cbv->delimlen - 1))
	lblen -= cbv->delimlen + 1;
    }

    PUTBACK ;
  }
  else {
    tbuff = newSV(0);
    tsiz = newSViv(BUFSIZE);
  }

  for (cbv->offset = 0, cbv->prev_offset = 0; ! done;)
    {
      int	bufleft;

      SAVETMPS;

      if (buff) {
	if (cbv->bufflen > (BUFSIZE >> 1)) {
	  int diff;

	  cbv->prev_offset = cbv->offset;
	  cbv->offset = XML_GetCurrentByteIndex(parser);
	  diff = cbv->offset - cbv->prev_offset;
	  leftover = cbv->bufflen - diff;
	  if (leftover < 0 || leftover >= BUFSIZE)
	    croak("parse_stream: bug in parse position calculation");
	  bufleft = BUFSIZE - leftover;
	  Move(&buffer[diff], buffer, leftover, char);
	}
	else {
	  leftover = cbv->bufflen;
	  bufleft = BUFSIZE;
	}
	buff = &buffer[leftover];
	*buff = '\0';
      }
      else {
	leftover = 0;
	buff = buffer;
	bufleft = BUFSIZE;
      }

      if (cbv->delim) {
	br = lblen > bufleft ? bufleft : lblen;
	if (br)
          Copy(linebuff, buff, br, char);
	linebuff += br;
	lblen -= br;
	done = lblen <= 0;
      }
      else {
	int cnt;
	SV * rdres;
	char * tb;

	sv_setiv(tsiz, bufleft);

	PUSHMARK(SP);
	EXTEND(SP, 3);
	PUSHs(ioref);
	PUSHs(tbuff);
	PUSHs(tsiz);
	PUTBACK ;

	cnt = perl_call_method("read", G_SCALAR);

	SPAGAIN ;

	if (cnt != 1)
	  croak("read method call failed");

	rdres = POPs;

	if (! SvOK(rdres))
	  croak("read error");

	tb = SvPV(tbuff, br);
	if (br > 0)
	  Copy(tb, buff, br, char);

	PUTBACK ;
      }

      if (br == 0) {
	done = 1;
      }
      else {
	cbv->buffstrt = buffer;
	cbv->bufflen  = br + leftover;
      }

      ret = XML_Parse(parser, buff, br, done);

      if (! ret)
	break;

      FREETMPS;
    }

  if (! ret)
    append_error(parser, msg);

  if (close_it) {
    PUSHMARK(SP);
    XPUSHs(ioref);
    PUTBACK ;
    perl_call_method("close", G_DISCARD);
  }

  if (! cbv->delim) {
    SvREFCNT_dec(tsiz);
    SvREFCNT_dec(tbuff);
  }
      
  FREETMPS;
  LEAVE;

  return ret;
}  /* End parse_stream */

static SV *
gen_ns_name(const char * name, HV * ns_table, AV * ns_list)
{
  char	*pos = strchr(name, NSDELIM);
  SV * ret;

  if (pos && pos > name)
    {
      SV ** name_ent = hv_fetch(ns_table, (char *) name,
				pos - name, TRUE);
      ret = newSVpv(&pos[1], 0);

      if (name_ent)
	{
	  int index;

	  if (SvOK(*name_ent))
	    {
	      index = SvIV(*name_ent);
	    }
	  else
	    {
	      av_push(ns_list,  newSVpv((char *) name, pos - name));
	      index = av_len(ns_list);
	      sv_setiv(*name_ent, (IV) index);
	    }

	  sv_setiv(ret, (IV) index);
	  SvPOK_on(ret);
	}
    }
  else
    ret = newSVpv((char *) name, 0);

  return ret;
}  /* End gen_ns_name */

static int
allwhite(const char *str, int len)
{
  const char *ptr = str;
  const char *lim = &str[len];

  for (; ptr < lim; ptr++) {
    if (! isSPACE(*ptr))
      return 0;
  }
    
  return 1;
}  /* End allwhite */

static int
parse_local(CallbackVector *cbv, const char *str, int len)
{
  unsigned int dflags;
  int   called_handler;
  int	brkstrt;

  if (cbv->doctype_buffer && len > 0) {
    STRLEN newlen = cbv->dtb_len + len;

    if (newlen > cbv->dtb_limit) {
	cbv->dtb_limit = ((newlen / DTB_GROW) + 1) * DTB_GROW;
	Renew(cbv->doctype_buffer, cbv->dtb_limit, char);
    }

    strncpy(cbv->doctype_buffer + cbv->dtb_len, (char *) str, len);
    cbv->dtb_len += len;
  }
	
  brkstrt = (len > 1 && *str == '<'); 

  if ((brkstrt && ((str[1] == '?' && ! strnEQ(str,"<?xml", 5))
		   || strnEQ(str, "<!--", 4))))
    return 0;

  if (allwhite(str, len))
    return cbv->doctype_buffer != 0;

  dflags = cbv->dflags;

  switch (cbv->local_parse_state) {
  case PS_Initial:
    if (brkstrt) {
      if ((dflags & INST_INDT) && len == 9 && strnEQ(str, "<!DOCTYPE", len)) {
	cbv->local_parse_state = PS_Docname;
	cbv->dtb_limit = DTB_GROW;
	New(319, cbv->doctype_buffer, cbv->dtb_limit, char);
	cbv->dtb_len = len;
	strncpy(cbv->doctype_buffer, str, len);
	check_and_set_default_handler(cbv->p, cbv, 0, INST_XML);
	return (dflags & INST_DOC);
      }
      else if ((dflags & INST_XML)
	       && strnEQ(str, "<?xml", 5)) {
	dSP;
	char qc;
	char *vno;
	STRLEN  vno_len;
	char *enc;
	STRLEN enc_len;
	char *stand;
	STRLEN st_len;
	char *match, *mtchend;

	match = "version=";
	vno_len = strlen(match);
	mtchend = match + vno_len;
	vno = ninstr((char *) str, (char *) (str + len), match, mtchend);
	vno += vno_len;
	qc = *vno++;
	vno_len = 0;
	while (vno[vno_len] != qc)
	  vno_len++;

	match = "encoding=";
	enc_len = strlen(match);
	mtchend = match + enc_len;
	enc = ninstr(vno + vno_len, (char *) (str + len), match, mtchend);
	if (enc) {
	  enc += enc_len;
	  qc = *enc++;
	  enc_len = 0;
	  while (enc[enc_len] != qc)
	    enc_len++;
	}

	match = "standalone=";
	st_len = strlen(match);
	mtchend = match + st_len;
	if (enc) {
	  stand = ninstr(enc + enc_len, (char *) (str + len), match, mtchend);
	}
	else {
	  stand = ninstr(vno + vno_len, (char *) (str + len), match, mtchend);
	}
	if (stand) {
	  stand += st_len;
	  qc = *stand++;
	  while (stand[st_len] != qc)
	    st_len++;
	}

	cbv->doctype_buffer = (char *) str;
	cbv->dtb_len = len;
	cbv->in_local_hndlr = 1;

	PUSHMARK(SP);
	XPUSHs(cbv->self_sv);
	XPUSHs(sv_2mortal(mynewSVpv(vno, vno_len)));
	if (enc || stand)
	  XPUSHs(enc
		 ? sv_2mortal(mynewSVpv(enc, enc_len))
		 : &PL_sv_undef);
	if (stand)
	  XPUSHs((strnEQ(stand, "no", 2)) ? &PL_sv_no : &PL_sv_yes);

	PUTBACK;
	perl_call_sv(cbv->xmldec_sv, G_DISCARD);

	cbv->in_local_hndlr = 0;
	cbv->doctype_buffer = 0;
	cbv->dtb_len = 0;
	check_and_set_default_handler(cbv->p, cbv, 0, INST_XML);
	return 1;
      }
    }
    return 0;

  case PS_Docname:
    cbv->local_parse_state = PS_Docextern;
    if (dflags & INST_DOC) {
      cbv->docname_offset = cbv->dtb_len - len;
      cbv->docname_len = len;
    }
    else
      return 0;
    break;

  case PS_Docextern:
    if (strnEQ(str, "SYSTEM", len)) {
      cbv->local_parse_state = PS_Docsysid;
    }
    else if (strnEQ(str, "PUBLIC", len)) {
      cbv->local_parse_state = PS_Docpubid;
    }
    else if (len == 1 && *str == '[') {
      cbv->local_parse_state = PS_Internaldecl;
      if (dflags & INST_DOC) {
	cbv->intsub_offset = cbv->dtb_len - len;
      }
    }
    else if (len == 1 && *str == '>') {
      goto doctype_end;
    }
    if (! (dflags & INST_DOC))
      return 0;
    break;

  case PS_Docsysid:
    cbv->local_parse_state = PS_Checkinternal;
    if (dflags & INST_DOC) {
      cbv->docsys_offset = cbv->dtb_len - len;
      cbv->docsys_len = len;
    }
    else
      return 0;
    break;

  case PS_Docpubid:
    cbv->local_parse_state = PS_Docsysid;
    if (dflags & INST_DOC) {
      cbv->docpub_offset = cbv->dtb_len - len;
      cbv->docpub_len    = len;
    }
    else
      return 0;
    break;

  case PS_Checkinternal:
    if (len == 1) {
      if (*str == '[') {
	cbv->local_parse_state = PS_Internaldecl;
	if (dflags & INST_DOC) {
	  cbv->intsub_offset = cbv->dtb_len - len;
	}
	else
	  return 0;
      }
      else if (*str == '>') {
	goto doctype_end;
      }
    }
    break;

  case PS_Internaldecl:
    if (brkstrt) {
      /* Note that expat already accepts handlers for Notation declarations */

      cbv->dtb_offset = cbv->dtb_len - len;

      if (strnEQ(str, "<!ENTITY", len)) {
	cbv->local_parse_state = PS_Entityname;
	cbv->isparam = 0;
      }
      else if (strnEQ(str, "<!ELEMENT", len)) {
	cbv->local_parse_state = PS_Elementname;
      }
      else if (strnEQ(str, "<!ATTLIST", len)) {
	cbv->local_parse_state = PS_Attelname;
      }
    }
    else if (len == 1 && *str == ']') {
      cbv->local_parse_state = PS_Doctypend;
      if (dflags & INST_DOC) {
	cbv->intsub_len = cbv->dtb_len - cbv->intsub_offset;
      }
    }
    break;

  case PS_Doctypend:
    goto doctype_end;

  case PS_Entityname:
    if (len == 1 && *str == '%') {
      cbv->isparam = 1;
    }
    else {
      cbv->local_parse_state = PS_Entityval;
      if (dflags & INST_ENT) {
	cbv->entnam_offset = cbv->dtb_len - len;
	cbv->entnam_len = len;
      }
    }
    break;

  case PS_Entityval:
    if (strnEQ(str, "SYSTEM", len)) {
      cbv->local_parse_state = PS_Entsysid;
      if (dflags & INST_ENT) {
	cbv->which_decl = DECL_EXTENT;
	cbv->entpub_len = 0;
      }
    }
    else if (strnEQ(str, "PUBLIC", len)) {
      cbv->local_parse_state = PS_Entpubid;
      if (dflags & INST_ENT) {
	cbv->which_decl = DECL_EXTENT;
      }
    }
    else if (len >= 2 ) {
      cbv->local_parse_state = PS_Declend;
      if (dflags & INST_ENT) {
	cbv->entval_offset = cbv->dtb_len - len + 1;	/* Account for '' */
	cbv->entval_len = len - 2;			/* Account for '' */
	cbv->which_decl = DECL_INTENT;
      }
    }
    break;

  case PS_Entsysid:
    cbv->local_parse_state = PS_Entndata;
    if (dflags & INST_ENT) {
      cbv->entsys_offset = cbv->dtb_len - len;
      cbv->entsys_len = len;
    }
    break;

  case PS_Entpubid:
    cbv->local_parse_state = PS_Entsysid;
    if (dflags & INST_ENT) {
      cbv->entpub_offset = cbv->dtb_len - len;
      cbv->entpub_len = len;
    }
    break;

  case PS_Entndata:
    if (len == 1 && *str == '>') {
      cbv->entnot_len = 0;
      goto declaration_end;
    }
    else if (strnEQ(str, "NDATA", len)) {
      cbv->local_parse_state = PS_Entnotation;
    }
    break;

  case PS_Entnotation:
    cbv->local_parse_state = PS_Declend;
    if (dflags & INST_ENT) {
      cbv->entnot_offset = cbv->dtb_len - len;
      cbv->entnot_len = len;
    }
    break;

  case PS_Declend:
    goto declaration_end;

  case PS_Elementname:
    cbv->local_parse_state = PS_Elcontent;
    if (dflags & INST_ELE) {
      cbv->elnam_offset = cbv->dtb_len - len;
      cbv->elnam_len = len;
      cbv->model_len = 0;
    }
    break;

  case PS_Elcontent:
    if (len == 1 && *str == '>') {
      cbv->which_decl = DECL_ELEMNT;
      goto declaration_end;
    }
    else if (dflags & INST_ELE ) {
      if (cbv->model_len == 0)
	cbv->model_offset = cbv->dtb_len - len;

      cbv->model_len = cbv->dtb_len - cbv->model_offset;
    }
    break;

  case PS_Attelname:
    cbv->local_parse_state = PS_Attdef;
    if (dflags & INST_ATT) {
      cbv->elnam_offset = cbv->dtb_len - len;
      cbv->elnam_len = len;
    }
    break;
      
  case PS_Attdef:
    if (len == 1 && *str == '>') {
      cbv->which_decl = DECL_ATTLST;
      goto declaration_end;
    }
    else if (dflags & INST_ATT) {
      cbv->attnam_offset = cbv->dtb_len - len;
      cbv->attnam_len = len;
      cbv->attfixed = 0;
    }
    cbv->local_parse_state = PS_Atttype;
    break;

  case PS_Atttype:
    if (dflags & INST_ATT) {
      cbv->atttyp_offset = cbv->dtb_len - len;
      cbv->atttyp_len = len;
    }
    if ((len == 1 && *str == '(')
	|| strnEQ(str, "NOTATION", len)) {
      cbv->local_parse_state = PS_Attmoretype;
    }
    else {
      cbv->local_parse_state = PS_Attval;
    }
    break;

  case PS_Attmoretype:
    if (dflags & INST_ATT) {
      cbv->atttyp_len = cbv->dtb_len - cbv->atttyp_offset;
    }
    if (len == 1 && *str == ')') {
      cbv->local_parse_state = PS_Attval;
    }
    break;

  case PS_Attval:
    if (strnEQ(str, "#FIXED", len)) {
      cbv->attfixed = 1;
    }
    else {
      cbv->local_parse_state = PS_Attdef;
      if (dflags & INST_ATT) {
	dSP;
	char *elname = &(cbv->doctype_buffer[cbv->elnam_offset]);
	char *attname = &(cbv->doctype_buffer[cbv->attnam_offset]);
	char *type    = &(cbv->doctype_buffer[cbv->atttyp_offset]);
	/* quotes kept on */
	char *dflt    = &(cbv->doctype_buffer[cbv->dtb_len - len]);

	cbv->in_local_hndlr = 1;

	PUSHMARK(SP);
	XPUSHs(cbv->self_sv);
	XPUSHs(sv_2mortal(mynewSVpv(elname, cbv->elnam_len)));
	XPUSHs(sv_2mortal(mynewSVpv(attname, cbv->attnam_len)));
	XPUSHs(sv_2mortal(mynewSVpv(type, cbv->atttyp_len)));
	XPUSHs(sv_2mortal(mynewSVpv(dflt, len)));
	if (cbv->attfixed)
	  XPUSHs(&PL_sv_yes);
	PUTBACK;
	perl_call_sv(cbv->attdcl_sv, G_DISCARD);

	cbv->in_local_hndlr = 0;
      }
    }
    break;

  }  /* End of switch(cbv->local_parse_state) */

  return 1;

declaration_end:
  called_handler = 0;
  if (dflags & INST_DECL) {
    if (cbv->which_decl == DECL_INTENT) {
      if (dflags & INST_ENT) {
	dSP;
	SV * nmsv;
	char *name = &(cbv->doctype_buffer[cbv->entnam_offset]);
	char *val  = &(cbv->doctype_buffer[cbv->entval_offset]);

	if (cbv->isparam) {
	  nmsv = newSVpv("%", 1);
	  sv_catpvn(nmsv, name, cbv->entnam_len);
	}
	else {
	  nmsv = mynewSVpv(name, cbv->entnam_len);
	}

	cbv->in_local_hndlr = 1;

	PUSHMARK(SP);
	XPUSHs(cbv->self_sv);
	XPUSHs(sv_2mortal(nmsv));
	XPUSHs(sv_2mortal(mynewSVpv(val, cbv->entval_len)));
	PUTBACK;
	perl_call_sv(cbv->entdcl_sv, G_DISCARD);

	cbv->in_local_hndlr = 0;
	called_handler = 1;
      }
    }
    else if (cbv->which_decl == DECL_EXTENT) {
      if (dflags & INST_ENT) {
	dSP;
	SV * nmsv;
	char *name = &(cbv->doctype_buffer[cbv->entnam_offset]);
	char *sysid = &(cbv->doctype_buffer[cbv->entsys_offset + 1]);
	char *pubid = (cbv->entpub_len
		       ? &(cbv->doctype_buffer[cbv->entpub_offset + 1])
		       : (char *) 0);

	if (cbv->isparam) {
	  nmsv = newSVpv("%", 1);
	  sv_catpvn(nmsv, name, cbv->entnam_len);
	}
	else {
	  nmsv = mynewSVpv(name, cbv->entnam_len);
	}

	cbv->in_local_hndlr = 1;

	PUSHMARK(SP);
	XPUSHs(cbv->self_sv);
	XPUSHs(sv_2mortal(nmsv));
	XPUSHs(&PL_sv_undef);
	XPUSHs(sv_2mortal(mynewSVpv(sysid, (cbv->entsys_len - 2))));
	XPUSHs((pubid ? sv_2mortal(mynewSVpv(pubid, (cbv->entpub_len - 2)))
		: &PL_sv_undef));
	if (cbv->entnot_len) {
	  char *notation = &(cbv->doctype_buffer[cbv->entnot_offset]);
	  XPUSHs(sv_2mortal(mynewSVpv(notation, cbv->entnot_len)));
	}
	PUTBACK;
	perl_call_sv(cbv->entdcl_sv, G_DISCARD);

	cbv->in_local_hndlr = 0;
	called_handler = 1;
      }
    }
    else if (cbv->which_decl == DECL_ELEMNT) {
      if (dflags & INST_ELE) {
	dSP;
	char *name = &(cbv->doctype_buffer[cbv->elnam_offset]);
	char *model = &(cbv->doctype_buffer[cbv->model_offset]);

	cbv->in_local_hndlr = 1;

	PUSHMARK(SP);
	XPUSHs(cbv->self_sv);
	XPUSHs(sv_2mortal(mynewSVpv(name, cbv->elnam_len)));
	XPUSHs(sv_2mortal(mynewSVpv(model, cbv->model_len)));
	PUTBACK;
	perl_call_sv(cbv->eledcl_sv, G_DISCARD);

	cbv->in_local_hndlr = 0;
	called_handler = 1;
      }
    }
    else if (cbv->which_decl == DECL_ATTLST) {
      if (dflags & INST_ATT) {
	/* Attlist declarations taken care of, 1 attribute at a time, under
	   the PS_Attval case in the switch above */

	called_handler = 1;
      }
    }

  }

  if (! called_handler && !(dflags & INST_DOC) && (dflags & INST_DFL)) {
    dSP;
    char *start = &(cbv->doctype_buffer[cbv->dtb_offset]);

    PUSHMARK(SP);
    XPUSHs(cbv->self_sv);
    XPUSHs(sv_2mortal(mynewSVpv(start, cbv->dtb_len - cbv->dtb_offset)));
    PUTBACK;
    perl_call_sv(cbv->dflt_sv, G_DISCARD);
  }

  cbv->local_parse_state = PS_Internaldecl;
  return 1;

doctype_end:
  if (dflags & INST_DOC) {
    dSP;
    char *name = &(cbv->doctype_buffer[cbv->docname_offset]);
    char *sysid = (cbv->docsys_len
		   ? &(cbv->doctype_buffer[cbv->docsys_offset + 1])
		   : (char *) 0);
    char *pubid = (cbv->docpub_len
		   ? &(cbv->doctype_buffer[cbv->docpub_offset + 1])
		   : (char *) 0);
    char *intsub = (cbv->intsub_len
		    ? &(cbv->doctype_buffer[cbv->intsub_offset])
		    : (char *) 0);

    cbv->dtb_offset = 0;
    cbv->in_local_hndlr = 1;

    PUSHMARK(SP);
    XPUSHs(cbv->self_sv);
    XPUSHs(sv_2mortal(mynewSVpv(name, cbv->docname_len)));
    if (sysid || pubid || intsub)
      XPUSHs(sysid
	     ? sv_2mortal(mynewSVpv(sysid, (cbv->docsys_len - 2)))
	     : &PL_sv_undef);
    if (pubid || intsub)
      XPUSHs(pubid
	     ? sv_2mortal(mynewSVpv(pubid, (cbv->docpub_len - 2)))
	     : &PL_sv_undef);
    if (intsub)
      XPUSHs(sv_2mortal(mynewSVpv(intsub, cbv->intsub_len)));
    PUTBACK;
    perl_call_sv(cbv->doctyp_sv, G_DISCARD);

    cbv->in_local_hndlr = 0;
  }
  cbv->local_parse_state = PS_Initial;
  check_and_set_default_handler(cbv->p, cbv, 0, INST_LOCAL);
  return 1;
}  /* End parse_local */

static void
characterData(void *userData, const char *s, int len)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 2);
  PUSHs(cbv->self_sv);
  PUSHs(sv_2mortal(mynewSVpv((char*)s,len)));
  PUTBACK;
  perl_call_sv(cbv->char_sv, G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End characterData */

static void
startElement(void *userData, const char *name, const char **atts)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;
  SV ** pcontext;
  unsigned   do_ns = cbv->ns;
  SV ** pnstab;
  SV ** pnslst;
  SV *  elname;

  if (! cbv->start_seen) {
    /* All of the local handlers deal with stuff in the prolog,
       which we won't see if we've started parsing the root element */

    if (cbv->dflags & INST_LOCAL) {
      check_and_set_default_handler(cbv->p, cbv, 0, INST_LOCAL);
    }

    cbv->start_seen = 1;
  }
    
  if (do_ns)
    elname = gen_ns_name(name, cbv->nstab, cbv->nslst);
  else
    elname = newSVpv((char *)name, 0);

  if (SvTRUE(cbv->start_sv))
    {
      const char **attlim = atts;

      while (*attlim)
	attlim++;

      ENTER;
      SAVETMPS;

      PUSHMARK(sp);
      EXTEND(sp, attlim - atts + 2);
      PUSHs(cbv->self_sv);
      PUSHs(elname);
      while (*atts)
	{
	  SV * attname;

	  attname = (do_ns ? gen_ns_name(*atts, cbv->nstab, cbv->nslst)
		     : newSVpv((char *) *atts, 0));
	    
	  if ((*atts)[-1] & 4) {
	    /* This attribute was defaulted */
	    
	    if (SvIOKp(attname)) {
	      SvIVX(attname) |= AttDefaultFlag;
	    }
	    else {
	      sv_setiv(attname, (IV) AttDefaultFlag);
	      SvPOK_on(attname);
	    }
	  }

	  atts++;
	  PUSHs(sv_2mortal(attname));
	  if (*atts)
	    PUSHs(sv_2mortal(newSVpv((char*)*atts++,0)));
	}
      PUTBACK;
      perl_call_sv(cbv->start_sv, G_DISCARD);

      FREETMPS;
      LEAVE;
    }

  av_push(cbv->context, elname);

  if (cbv->st_serial_stackptr >= cbv->st_serial_stacksize) {
    unsigned int newsize = cbv->st_serial_stacksize + 512;

    Renew(cbv->st_serial_stack, newsize, unsigned int);
    cbv->st_serial_stacksize = newsize;
  }

  cbv->st_serial_stack[++cbv->st_serial_stackptr] =  ++(cbv->st_serial);
  
  if (cbv->ns) {
    av_clear(cbv->new_prefix_list);
  }
} /* End startElement */

static void
endElement(void *userData, const char *name)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;
  SV *elname;

  elname = av_pop(cbv->context);
  
  if (! cbv->st_serial_stackptr) {
    croak("endElement: Start tag serial number stack underflow");
  }

  cbv->st_serial_stackptr--;

  if (SvTRUE(cbv->end_sv))
    {
      ENTER;
      SAVETMPS;

      PUSHMARK(sp);
      EXTEND(sp, 2);
      PUSHs(cbv->self_sv);
      PUSHs(elname);
      PUTBACK;
      perl_call_sv(cbv->end_sv, G_DISCARD);

      FREETMPS;
      LEAVE;
    }

  SvREFCNT_dec(elname);
}  /* End endElement */

static void
processingInstruction(void *userData, const char *target, const char *data)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 3);
  PUSHs(cbv->self_sv);
  PUSHs(sv_2mortal(newSVpv((char*)target,0)));
  PUSHs(sv_2mortal(newSVpv((char*)data,0)));
  PUTBACK;
  perl_call_sv(cbv->proc_sv, G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End processingInstruction */

static void
commenthandle(void *userData, const char *string)
{
  dSP;
  CallbackVector * cbv = (CallbackVector*) userData;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 2);
  PUSHs(cbv->self_sv);
  PUSHs(sv_2mortal(newSVpv((char*) string, 0)));
  PUTBACK;
  perl_call_sv(cbv->cmnt_sv, G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End commenthandler */

static void
startCdata(void *userData)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  if (cbv->startcd_sv) {
    ENTER;
    SAVETMPS;

    PUSHMARK(sp);
    XPUSHs(cbv->self_sv);
    PUTBACK;
    perl_call_sv(cbv->startcd_sv, G_DISCARD);

    FREETMPS;
    LEAVE;
  }
}  /* End startCdata */

static void
endCdata(void *userData)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  if (cbv->endcd_sv) {
    ENTER;
    SAVETMPS;

    PUSHMARK(sp);
    XPUSHs(cbv->self_sv);
    PUTBACK;
    perl_call_sv(cbv->endcd_sv, G_DISCARD);

    FREETMPS;
    LEAVE;
  }
}  /* End endCdata */

static void
nsStart(void *userdata, const XML_Char *prefix, const XML_Char *uri){
  dSP;
  CallbackVector* cbv = (CallbackVector*) userdata;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 3);
  PUSHs(cbv->self_sv);
  PUSHs(prefix ? sv_2mortal(newSVpv((char *)prefix, 0)) : &PL_sv_undef);
  PUSHs(uri ? sv_2mortal(newSVpv((char *)uri, 0)) : &PL_sv_undef);
  PUTBACK;
  perl_call_method("NamespaceStart", G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End nsStart */

static void
nsEnd(void *userdata, const XML_Char *prefix) {
  dSP;
  CallbackVector* cbv = (CallbackVector*) userdata;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 2);
  PUSHs(cbv->self_sv);
  PUSHs(prefix ? sv_2mortal(newSVpv((char *)prefix, 0)) : &PL_sv_undef);
  PUTBACK;
  perl_call_method("NamespaceEnd", G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End nsEnd */

static void
defaulthandle(void *userData, const char *string, int len)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  if (cbv->dflags & INST_LOCAL) {
    if (parse_local(cbv, string, len))
      return;
  }

  if (! cbv->dflt_sv)
    return;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 2);
  PUSHs(cbv->self_sv);
  PUSHs(sv_2mortal(mynewSVpv((char*)string, len)));
  PUTBACK;
  perl_call_sv(cbv->dflt_sv, G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End defaulthandle */

static void
unparsedEntityDecl(void *userData,
		   const char* entity,
		   const char* base,
		   const char* sysid,
		   const char* pubid,
		   const char* notation)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  ENTER;
  SAVETMPS;

  PUSHMARK(sp);
  EXTEND(sp, 6);
  PUSHs(cbv->self_sv);
  PUSHs(sv_2mortal(newSVpv((char*) entity, 0)));
  PUSHs(base ? sv_2mortal(newSVpv((char*) base, 0)) : &PL_sv_undef);
  PUSHs(sv_2mortal(newSVpv((char*) sysid, 0)));
  PUSHs(pubid ? sv_2mortal(newSVpv((char*) pubid, 0)) : &PL_sv_undef);
  PUSHs(sv_2mortal(newSVpv((char*) notation, 0)));
  PUTBACK;
  perl_call_sv(cbv->unprsd_sv, G_DISCARD);

  FREETMPS;
  LEAVE;
}  /* End unparsedEntityDecl */

static void
notationDecl(void *userData,
	     const char *name,
	     const char *base,
	     const char *sysid,
	     const char *pubid)
{
  dSP;
  CallbackVector* cbv = (CallbackVector*) userData;

  PUSHMARK(sp);
  XPUSHs(cbv->self_sv);
  XPUSHs(sv_2mortal(newSVpv((char*) name, 0)));
  if (base)
    {
      XPUSHs(sv_2mortal(newSVpv((char *) base, 0)));
    }
  else if (sysid || pubid)
    {
      XPUSHs(&PL_sv_undef);
    }

  if (sysid)
    {
      XPUSHs(sv_2mortal(newSVpv((char *) sysid, 0)));
    }
  else if (pubid)
    {
      XPUSHs(&PL_sv_undef);
    }
  
  if (pubid)
    XPUSHs(sv_2mortal(newSVpv((char *) pubid, 0)));

  PUTBACK;
  perl_call_sv(cbv->notation_sv, G_DISCARD);
}  /* End notationDecl */

static int
externalEntityRef(XML_Parser parser,
		  const char* open,
		  const char* base,
		  const char* sysid,
		  const char* pubid)
{
  dSP;

  int count;
  int ret = 0;
  int parse_done = 0;

  CallbackVector* cbv = (CallbackVector*) XML_GetUserData(parser);

  ENTER ;
  SAVETMPS ;
  PUSHMARK(sp);
  EXTEND(sp, pubid ? 4 : 3);
  PUSHs(cbv->self_sv);
  PUSHs(base ? sv_2mortal(newSVpv((char*) base, 0)) : &PL_sv_undef);
  PUSHs(sv_2mortal(newSVpv((char*) sysid, 0)));
  if (pubid)
    PUSHs(sv_2mortal(newSVpv((char*) pubid, 0)));
  PUTBACK ;
  count = perl_call_sv(cbv->extent_sv, G_SCALAR);

  SPAGAIN ;

  if (count >= 1)
    {
       SV * result = POPs;
       int type;

       if (result && (type = SvTYPE(result)) > 0)
         {
	   char *oldbuff;
	   int oldoff, oldlen;
	   XML_Parser entpar;
	   SV **pval = hv_fetch((HV*) SvRV(cbv->self_sv),
				  "Parser", 6, 0);

	   if (! pval || ! SvIOK(*pval))
	     croak("Can't get parser field");

	   entpar = XML_ExternalEntityParserCreate(parser, open, 0);

	   sv_setiv(*pval, (IV) entpar);

	   cbv->p = entpar;
	   oldbuff = cbv->buffstrt;
	   oldoff = cbv->offset;
	   oldlen = cbv->bufflen;

	   if (type == SVt_RV && SvOBJECT(result)) {
	     ret = parse_stream(entpar, result, 1);
	   }
	   else if (type == SVt_PVGV) {
	     ret = parse_stream(entpar,
				sv_2mortal(newRV((SV*) GvIOp(result))), 1);
	   }
	   else if (SvPOK(result)) {
	     STRLEN  eslen;
	     int pret;
	     char *entstr = SvPV(result, eslen);

	     cbv->buffstrt = entstr;
	     cbv->offset   = 0;
	     cbv->bufflen  = eslen;
	     ret = XML_Parse(entpar, entstr, eslen, 1);

	   }

	   if (! ret)
	     append_error(entpar, NULL);

	   parse_done = 1;
	   cbv->buffstrt = oldbuff;
	   cbv->offset = oldoff;
	   cbv->bufflen = oldlen;
	   cbv->p = parser;
	   sv_setiv(*pval, (IV) parser);

	   XML_ParserFree(entpar);
         }
    }

  if (! ret && ! parse_done)
    append_error(parser, "Handler couldn't resolve external entity");

  PUTBACK ;
  FREETMPS ;
  LEAVE ;

  return ret;
}  /* End externalEntityRef */

/*================================================================
** This is the function that expat calls to convert multi-byte sequences
** for external encodings. Each byte in the sequence is used to index
** into the current map to either set the next map or, in the case of
** the final byte, to get the corresponding Unicode scalar, which is
** returned.
*/

static int
convert_to_unicode(void *data, const char *seq) {
  Encinfo *enc = (Encinfo *) data;
  PrefixMap *curpfx;
  int count;
  int index = 0;

  for (count = 0; count < 4; count++) {
    unsigned char byte = (unsigned char) seq[count];
    unsigned char bndx;
    unsigned char bmsk;
    int offset;

    curpfx = &enc->prefixes[index];
    offset = ((int) byte) - curpfx->min;
    if (offset < 0)
      break;
    if (offset >= curpfx->len && curpfx->len != 0)
      break;

    bndx = byte >> 3;
    bmsk = 1 << (byte & 0x7);

    if (curpfx->ispfx[bndx] & bmsk) {
      index = enc->bytemap[curpfx->bmap_start + offset];
    }
    else if (curpfx->ischar[bndx] & bmsk) {
      return enc->bytemap[curpfx->bmap_start + offset];
    }
    else
      break;
  }

  return -1;
}  /* End convert_to_unicode */

static int
unknownEncoding(void *unused, const char *name, XML_Encoding *info)
{
  SV ** encinfptr;
  Encinfo *enc;
  int namelen;
  int i;
  char buff[42];

  namelen = strlen(name);
  if (namelen > 40)
    return 0;

  /* Make uppercase */
  for (i = 0; i < namelen; i++) {
    char c = name[i];
    if (c >= 'a' && c <= 'z')
      c -= 'a' - 'A';
    buff[i] = c;
  }

  if (! EncodingTable) {
    EncodingTable = perl_get_hv("XML::Parser::Expat::Encoding_Table", FALSE);
    if (! EncodingTable)
      croak("Can't find XML::Parser::Expat::Encoding_Table");
  }

  encinfptr = hv_fetch(EncodingTable, buff, namelen, 0);

  if (! encinfptr || ! SvOK(*encinfptr)) {
    /* Not found, so try to autoload */
    dSP;
    int count;

    ENTER;
    SAVETMPS;
    PUSHMARK(sp);
    XPUSHs(sv_2mortal(mynewSVpv(buff,namelen)));
    PUTBACK;
    perl_call_pv("XML::Parser::Expat::load_encoding", G_DISCARD);
    
    encinfptr = hv_fetch(EncodingTable, buff, namelen, 0);
    FREETMPS;
    LEAVE;

    if (! encinfptr || ! SvOK(*encinfptr))
      return 0;
  }

  if (! sv_derived_from(*encinfptr, "XML::Parser::Encinfo"))
    croak("Entry in XML::Parser::Expat::Encoding_Table not an Encinfo object");

  enc = (Encinfo *) SvIV((SV*)SvRV(*encinfptr));
  Copy(enc->firstmap, info->map, 256, int);
  info->release = NULL;
  if (enc->prefixes_size) {
    info->data = (void *) enc;
    info->convert = convert_to_unicode;
  }
  else {
    info->data = NULL;
    info->convert = NULL;
  }

  return 1;
}  /* End unknownEncoding */

static void
check_and_set_default_handler(XML_Parser parser,
			      CallbackVector *cbv,
			      int set,
			      unsigned int hflag)
{
  XML_DefaultHandler dflthndl;
  int docall = 0;

  if (set) {
    if (hflag == INST_DFL || ! cbv->start_seen) {
      if (! cbv->dflags) {
	docall = 1;
	dflthndl = defaulthandle;
      }

      cbv->dflags |= hflag;
    }
  }
  else {
    unsigned int newflags = cbv->dflags & ~ hflag;

    if (cbv->dflags && ! newflags) {
      dflthndl = (XML_DefaultHandler) 0;
      docall = 1;
    }

    cbv->dflags = newflags;
  }

  if (docall) {
    if (cbv->no_expand) 
      XML_SetDefaultHandler(parser, dflthndl);
    else
      XML_SetDefaultHandlerExpand(parser, dflthndl);
  }
}  /* End check_and_set_default_handler */

static void
recString(void *userData, const char *string, int len)
{
  CallbackVector *cbv = (CallbackVector*) userData;

  if (cbv->recstring) {
    sv_catpvn(cbv->recstring, (char *) string, len);
  }
  else {
    cbv->recstring = mynewSVpv((char *) string, len);
  }
}  /* End recString */

MODULE = XML::Parser::Expat PACKAGE = XML::Parser::Expat	PREFIX = XML_

XML_Parser
XML_ParserCreate(self_sv, enc_sv, namespaces)
        SV *                    self_sv
	SV *			enc_sv
	int			namespaces
    CODE:
	{
	  CallbackVector *cbv;
	  char *enc = (char *) (SvTRUE(enc_sv) ? SvPV(enc_sv,PL_na) : 0);
	  SV ** spp;

	  if (! AttDefaultFlag) {
	    SV * adf = perl_get_sv("XML::Parser::Expat::Attdef_Flag", 0);
	    AttDefaultFlag = SvIV(adf);
	  }

	  Newz(320, cbv, 1, CallbackVector);
	  cbv->self_sv = SvREFCNT_inc(self_sv);
	  Newz(325, cbv->st_serial_stack, 1024, unsigned int);
	  spp = hv_fetch((HV*)SvRV(cbv->self_sv), "NoExpand", 8, 0);
	  if (spp && SvTRUE(*spp))
	    cbv->no_expand = 1;

	  spp = hv_fetch((HV*)SvRV(cbv->self_sv), "Context", 7, 0);
	  if (! spp || ! *spp || !SvROK(*spp))
	    croak("XML::Parser instance missing Context");

	  cbv->context = (AV*) SvRV(*spp);
	  
	  cbv->ns = (unsigned) namespaces;
	  if (namespaces)
	    {
	      spp = hv_fetch((HV*)SvRV(cbv->self_sv), "New_Prefixes", 12, 0);
	      if (! spp || ! *spp || !SvROK(*spp))
	        croak("XML::Parser instance missing New_Prefixes");

	      cbv->new_prefix_list = (AV *) SvRV(*spp);

	      spp = hv_fetch((HV*)SvRV(cbv->self_sv), "Namespace_Table",
			     15, FALSE);
	      if (! spp || ! *spp || !SvROK(*spp))
	        croak("XML::Parser instance missing Namespace_Table");

	      cbv->nstab = (HV *) SvRV(*spp);

	      spp = hv_fetch((HV*)SvRV(cbv->self_sv), "Namespace_List",
			     14, FALSE);
	      if (! spp || ! *spp || !SvROK(*spp))
	        croak("XML::Parser instance missing Namespace_List");

	      cbv->nslst = (AV *) SvRV(*spp);

	      RETVAL = XML_ParserCreateNS(enc, NSDELIM);
	      XML_SetNamespaceDeclHandler(RETVAL,nsStart, nsEnd);
	    }
	    else
	    {
	      RETVAL = XML_ParserCreate(enc);
	    }
	    
	  cbv->p = RETVAL;
	  XML_SetUserData(RETVAL, (void *) cbv);
	  XML_SetElementHandler(RETVAL, startElement, endElement);
	  XML_SetUnknownEncodingHandler(RETVAL, unknownEncoding, 0);
	}
    OUTPUT:
	RETVAL

void
XML_ParserRelease(parser)
      XML_Parser parser
    CODE:
      {
        CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);

	SvREFCNT_dec(cbv->self_sv);
      }

void
XML_ParserFree(parser)
	XML_Parser parser
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);

	  Safefree(cbv->st_serial_stack);

	  if (cbv->doctype_buffer)
	    Safefree(cbv->doctype_buffer);

	  /* Clean up any SVs that we have */
	  /* (Note that self_sv must already be taken care of
	     or we couldn't be here */

	  if (cbv->recstring)
	    SvREFCNT_dec(cbv->recstring);

	  if (cbv->start_sv)
	    SvREFCNT_dec(cbv->start_sv);

	  if (cbv->end_sv)
	    SvREFCNT_dec(cbv->end_sv);

	  if (cbv->char_sv)
	    SvREFCNT_dec(cbv->char_sv);

	  if (cbv->proc_sv)
	    SvREFCNT_dec(cbv->proc_sv);

	  if (cbv->cmnt_sv)
	    SvREFCNT_dec(cbv->cmnt_sv);

	  if (cbv->dflt_sv)
	    SvREFCNT_dec(cbv->dflt_sv);

	  if (cbv->entdcl_sv)
	    SvREFCNT_dec(cbv->entdcl_sv);

	  if (cbv->eledcl_sv)
	    SvREFCNT_dec(cbv->eledcl_sv);

	  if (cbv->attdcl_sv)
	    SvREFCNT_dec(cbv->attdcl_sv);

	  if (cbv->doctyp_sv)
	    SvREFCNT_dec(cbv->doctyp_sv);

	  if (cbv->xmldec_sv)
	    SvREFCNT_dec(cbv->xmldec_sv);

	  if (cbv->unprsd_sv)
	    SvREFCNT_dec(cbv->unprsd_sv);

	  if (cbv->notation_sv)
	    SvREFCNT_dec(cbv->notation_sv);

	  if (cbv->extent_sv)
	    SvREFCNT_dec(cbv->extent_sv);

	  if (cbv->startcd_sv)
	    SvREFCNT_dec(cbv->startcd_sv);

	  if (cbv->endcd_sv)
	    SvREFCNT_dec(cbv->endcd_sv);

	  /* ================ */
	    
	  Safefree(cbv);
	  XML_ParserFree(parser);
	}

int
XML_ParseString(parser, s)
        XML_Parser			parser
	char *				s
	int				len = PL_na;
    CODE:
        {
	  CallbackVector * cbv;

          cbv = (CallbackVector *) XML_GetUserData(parser);

	  cbv->buffstrt = s;
	  cbv->offset = 0;
	  cbv->bufflen = len;
	  RETVAL = XML_Parse(parser, s, len, 1);
	  if (! RETVAL)
	    append_error(parser, NULL);
	}

    OUTPUT:
	RETVAL

int
XML_ParseStream(parser, ioref, delim)
	XML_Parser			parser
	SV *				ioref
	SV *				delim
    CODE:
	{
	  SV **delimsv;
	  CallbackVector * cbv;

	  cbv = (CallbackVector *) XML_GetUserData(parser);
	  if (SvOK(delim)) {
	    cbv->delim = SvPV(delim, cbv->delimlen);
	  }
	  else {
	    cbv->delim = (char *) 0;
	  }
	      
	  RETVAL = parse_stream(parser, ioref, 0);
	}

    OUTPUT:
	RETVAL

int
XML_ParsePartial(parser, s)
	XML_Parser			parser
	char *				s
	int				len = PL_na;
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);

	  RETVAL = XML_Parse(parser, s, len, 0);
	  if (! RETVAL)
	    append_error(parser, NULL);
	}

    OUTPUT:
	RETVAL


int
XML_ParseDone(parser)
	XML_Parser			parser
    CODE:
	{
	  RETVAL = XML_Parse(parser, "", 0, 1);
	  if (! RETVAL)
	    append_error(parser, NULL);
	}

    OUTPUT:
	RETVAL

void
XML_SetStartElementHandler(parser, start_sv)
	XML_Parser			parser
	SV *				start_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  XMLP_UPD(start_sv);
	}

void
XML_SetEndElementHandler(parser, end_sv)
	XML_Parser			parser
	SV *				end_sv
    CODE:
	{
	  CallbackVector *cbv = (CallbackVector*) XML_GetUserData(parser);
	  XMLP_UPD(end_sv);
	}

void
XML_SetCharacterDataHandler(parser, char_sv)
	XML_Parser			parser
	SV *				char_sv
    CODE:
	{
	  XML_CharacterDataHandler charhndl = (XML_CharacterDataHandler) 0;
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(char_sv))
	    {
	      XMLP_UPD(char_sv);
	      charhndl = characterData;
	    }

	  XML_SetCharacterDataHandler(parser, charhndl);
	}

void
XML_SetProcessingInstructionHandler(parser, proc_sv)
	XML_Parser			parser
	SV *				proc_sv
    CODE:
	{
	  XML_ProcessingInstructionHandler prochndl =
	    (XML_ProcessingInstructionHandler) 0;
	  CallbackVector* cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(proc_sv))
	    {
	      XMLP_UPD(proc_sv);
	      prochndl = processingInstruction;
	    }

	  XML_SetProcessingInstructionHandler(parser, prochndl);
	}

void
XML_SetCommentHandler(parser, cmnt_sv)
	XML_Parser			parser
	SV *				cmnt_sv
    CODE:
	{
	  XML_CommentHandler cmnthndl = (XML_CommentHandler) 0;
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(cmnt_sv))
	    {
	      XMLP_UPD(cmnt_sv);
	      cmnthndl = commenthandle;
	    }

	  XML_SetCommentHandler(parser, cmnthndl);
	}

void
XML_SetDefaultHandler(parser, dflt_sv)
	XML_Parser			parser
	SV *				dflt_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(dflt_sv))
	    {
	      XMLP_UPD(dflt_sv);
	      set = 1;
	    }

	  check_and_set_default_handler(parser, cbv, set, INST_DFL);
	}

void
XML_SetUnparsedEntityDeclHandler(parser, unprsd_sv)
	XML_Parser			parser
	SV *				unprsd_sv
    CODE:
	{
	  XML_UnparsedEntityDeclHandler unprsdhndl =
	    (XML_UnparsedEntityDeclHandler) 0;
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(unprsd_sv))
	    {
	      XMLP_UPD(unprsd_sv);
	      unprsdhndl = unparsedEntityDecl;
	    }

	  XML_SetUnparsedEntityDeclHandler(parser, unprsdhndl);
	}

void
XML_SetNotationDeclHandler(parser, notation_sv)
	XML_Parser			parser
	SV *				notation_sv
    CODE:
	{
	  XML_NotationDeclHandler nothndlr = (XML_NotationDeclHandler) 0;
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(notation_sv))
	    {
	      XMLP_UPD(notation_sv);
	      nothndlr = notationDecl;
	    }

	  XML_SetNotationDeclHandler(parser, nothndlr);
	}

void
XML_SetExternalEntityRefHandler(parser, extent_sv)
	XML_Parser			parser
	SV *				extent_sv
    CODE:
	{
	  XML_ExternalEntityRefHandler exthndlr =
	    (XML_ExternalEntityRefHandler) 0;
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);

	  if (SvTRUE(extent_sv))
	    {
	      XMLP_UPD(extent_sv);
	      exthndlr = externalEntityRef;
	    }

	  XML_SetExternalEntityRefHandler(parser, exthndlr);
	}
	   
void
XML_SetEntityDeclHandler(parser, entdcl_sv)
	XML_Parser			parser
	SV *				entdcl_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(entdcl_sv))
	    {
	      XMLP_UPD(entdcl_sv);
	      set = 1;
	    }

	  check_and_set_default_handler(parser, cbv, set, INST_ENT);
	}

void
XML_SetElementDeclHandler(parser, eledcl_sv)
	XML_Parser			parser
	SV *				eledcl_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(eledcl_sv))
	    {
	      XMLP_UPD(eledcl_sv);
	      set = 1;
	    }

	  check_and_set_default_handler(parser, cbv, set, INST_ELE);
	}

void
XML_SetAttListDeclHandler(parser, attdcl_sv)
	XML_Parser			parser
	SV *				attdcl_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(attdcl_sv))
	    {
	      XMLP_UPD(attdcl_sv);
	      set = 1;
	    }

	  check_and_set_default_handler(parser, cbv, set, INST_ATT);
	}

void
XML_SetDoctypeHandler(parser, doctyp_sv)
	XML_Parser			parser
	SV *				doctyp_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector*) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(doctyp_sv))
	    {
	      XMLP_UPD(doctyp_sv);
	      set = 1;
	    }

	  check_and_set_default_handler(parser, cbv, set, INST_DOC);
	}

void
XML_SetXMLDeclHandler(parser, xmldec_sv)
	XML_Parser			parser
	SV *				xmldec_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
	  int set = 0;

	  if (SvTRUE(xmldec_sv)) {
	    XMLP_UPD(xmldec_sv);
	    set = 1;
	  }

	  check_and_set_default_handler(parser, cbv, set, INST_XML);
	}

int
XML_SetBase(parser, base)
	XML_Parser			parser
	char*				base

char*
XML_GetBase(parser)
	XML_Parser			parser
    CODE:
	const char *ret = XML_GetBase(parser);
	ST(0) = sv_newmortal();
	sv_setpv((SV*)ST(0), ret);

void
XML_PositionContext(parser, lines)
	XML_Parser			parser
	int				lines
    PREINIT:
	CallbackVector *cbv = (CallbackVector *) XML_GetUserData(parser);
        char *pos = cbv->buffstrt;
	char *markbeg, *markend, *limit;
	int length, relpos;
	int  cnt;
	int parsepos = XML_GetCurrentByteIndex(parser) - 1;

    PPCODE:
	  if (! pos)
            return;
          parsepos -= cbv->offset;
	  if (parsepos < 0)
	    parsepos = 0;

	  if (parsepos >= cbv->bufflen)
	    croak("PositionContext: Parse position is outside of buffer");

	  for (markbeg = &pos[parsepos], cnt = 0; markbeg >= pos; markbeg--)
	    {
	      if (*markbeg == '\n')
		{
		  cnt++;
		  if (cnt > lines)
		    break;
		}
	    }

	  markbeg++;

          relpos = 0;
	  limit = &pos[cbv->bufflen];
	  for (markend = &pos[parsepos + 1], cnt = 0;
	       markend < limit;
	       markend++)
	    {
	      if (*markend == '\n')
		{
		  if (cnt == 0)
                     relpos = (markend - markbeg) + 1;
		  cnt++;
		  if (cnt > lines)
		    {
		      markend++;
		      break;
		    }
		}
	    }

	  length = markend - markbeg;
          if (relpos == 0)
            relpos = length;

          EXTEND(sp, 2);
	  PUSHs(sv_2mortal(mynewSVpv(markbeg, length)));
	  PUSHs(sv_2mortal(newSViv(relpos)));

SV *
GenerateNSName(name, namespace, table, list)
	SV *				name
	SV *				namespace
	SV *				table
	SV *				list
    CODE:
	{
	  STRLEN	nmlen, nslen;
	  char *	nmstr;
	  char *	nsstr;
	  char *	buff;
	  char *	bp;
	  char *	blim;

	  nmstr = SvPV(name, nmlen);
	  nsstr = SvPV(namespace, nslen);

	  /* Form a namespace-name string that looks like expat's */
	  New(321, buff, nmlen + nslen + 2, char);
	  bp = buff;
	  blim = bp + nslen;
	  while (bp < blim)
	    *bp++ = *nsstr++;
	  *bp++ = NSDELIM;
	  blim = bp + nmlen;
	  while (bp < blim)
	    *bp++ = *nmstr++;
	  *bp = '\0';

	  RETVAL = gen_ns_name(buff, (HV *) SvRV(table), (AV *) SvRV(list));
	  Safefree(buff);
	}	
    OUTPUT:
	RETVAL

void
XML_DefaultCurrent(parser)
	XML_Parser			parser
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);

	  if (cbv->dflags & INST_DFL) {
	    if (cbv->in_local_hndlr) {
	      PUSHMARK(sp);
	      EXTEND(sp, 2);
	      XPUSHs(cbv->self_sv);
	      XPUSHs(sv_2mortal(mynewSVpv(cbv->doctype_buffer
					  + cbv->dtb_offset,
					  cbv->dtb_len - cbv->dtb_offset)));
	      PUTBACK;
	      perl_call_sv(cbv->dflt_sv, G_DISCARD);
	    }
	    else
	      XML_DefaultCurrent(parser);
	  }
	}

SV *
XML_RecognizedString(parser)
	XML_Parser			parser
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);

	  if (cbv->in_local_hndlr) {
	    RETVAL = mynewSVpv(cbv->doctype_buffer + cbv->dtb_offset,
			       cbv->dtb_len - cbv->dtb_offset);
	  }
	  else {
	    if (cbv->recstring) {
	      sv_setpvn(cbv->recstring, "", 0);
	    }

	    if (cbv->no_expand)
	      XML_SetDefaultHandler(parser, recString);
	    else
	      XML_SetDefaultHandlerExpand(parser, recString);
	      
	    XML_DefaultCurrent(parser);

	    if (cbv->no_expand)
	      XML_SetDefaultHandler(parser, cbv->dflags ? defaulthandle : 0);
	    else
	      XML_SetDefaultHandlerExpand(parser,
					  cbv->dflags ? defaulthandle : 0);
	    RETVAL = newSVsv(cbv->recstring);
	  }
	}
    OUTPUT:
	RETVAL

int
XML_GetErrorCode(parser)
	XML_Parser			parser

int
XML_GetCurrentLineNumber(parser)
	XML_Parser			parser


int
XML_GetCurrentColumnNumber(parser)
	XML_Parser			parser

long
XML_GetCurrentByteIndex(parser)
	XML_Parser			parser

char *
XML_ErrorString(code)
	int				code
    CODE:
	const char *ret = XML_ErrorString(code);
	ST(0) = sv_newmortal();
	sv_setpv((SV*)ST(0), ret);

SV *
XML_LoadEncoding(data, size)
	char *				data
	int				size
    CODE:
	{
	  Encmap_Header *emh = (Encmap_Header *) data;
	  unsigned pfxsize, bmsize;

	  if (size < sizeof(Encmap_Header)
	      || ntohl(emh->magic) != ENCMAP_MAGIC) {
	    RETVAL = &PL_sv_undef;
	  }
	  else {
	    Encinfo	*entry;
	    SV		*sv;
	    PrefixMap	*pfx;
	    unsigned short *bm;
	    int namelen;
	    int i;

	    pfxsize = ntohs(emh->pfsize);
	    bmsize  = ntohs(emh->bmsize);

	    if (size != (sizeof(Encmap_Header)
			 + pfxsize * sizeof(PrefixMap)
			 + bmsize * sizeof(unsigned short))) {
	      RETVAL = &PL_sv_undef;
	    }
	    else {
	      /* Convert to uppercase and get name length */

	      for (i = 0; i < sizeof(emh->name); i++) {
		char c = emh->name[i];

		  if (c == (char) 0)
		    break;

		if (c >= 'a' && c <= 'z')
		  emh->name[i] -= 'a' - 'A';
	      }
	      namelen = i;

	      RETVAL = mynewSVpv(emh->name, namelen);

	      New(322, entry, 1, Encinfo);
	      entry->prefixes_size = pfxsize;
	      entry->bytemap_size  = bmsize;
	      for (i = 0; i < 256; i++) {
		entry->firstmap[i] = ntohl(emh->map[i]);
	      }

	      pfx = (PrefixMap *) &data[sizeof(Encmap_Header)];
	      bm = (unsigned short *) (((char *) pfx)
				       + sizeof(PrefixMap) * pfxsize);

	      New(323, entry->prefixes, pfxsize, PrefixMap);
	      New(324, entry->bytemap, bmsize, unsigned short);

	      for (i = 0; i < pfxsize; i++, pfx++) {
		PrefixMap *dest = &entry->prefixes[i];

		dest->min = pfx->min;
		dest->len = pfx->len;
		dest->bmap_start = ntohs(pfx->bmap_start);
		Copy(pfx->ispfx, dest->ispfx,
		     sizeof(pfx->ispfx) + sizeof(pfx->ischar), unsigned char);
	      }

	      for (i = 0; i < bmsize; i++)
		entry->bytemap[i] = ntohs(bm[i]);

	      sv = newSViv(0);
	      sv_setref_pv(sv, "XML::Parser::Encinfo", (void *) entry);
	  
	      if (! EncodingTable) {
		EncodingTable
		  = perl_get_hv("XML::Parser::Expat::Encoding_Table",
				FALSE);
		if (! EncodingTable)
		  croak("Can't find XML::Parser::Expat::Encoding_Table");
	      }

	      hv_store(EncodingTable, emh->name, namelen, sv, 0);
	    }
	  }
	}
    OUTPUT:
	RETVAL

void
XML_FreeEncoding(enc)
	Encinfo *			enc
    CODE:
	Safefree(enc->bytemap);
	Safefree(enc->prefixes);
	Safefree(enc);

SV *
XML_OriginalString(parser)
	XML_Parser			parser
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
	  long parsepos, parselim;

	  if (cbv->buffstrt) {
	    
	    parsepos = XML_GetCurrentByteIndex(parser);
	    parselim = XML_GetCurrentByteLimit(parser);

	    if (parsepos > parselim)
	      croak("OriginalString: Parse position > Parse limit");

	    parsepos -= cbv->offset;
	    parselim -= cbv->offset;

	    if (parsepos < 0 || parselim > cbv->bufflen)
	      croak("OriginalString: Part of string is outside buffer");

	    RETVAL = mynewSVpv(&cbv->buffstrt[parsepos], parselim - parsepos);
	  }
	  else {
	    RETVAL = newSVpv("", 0);
	  }
	}
    OUTPUT:
	RETVAL

void
XML_SetStartCdataHandler(parser, startcd_sv)
	XML_Parser			parser
	SV *				startcd_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
	  XML_StartCdataSectionHandler scdhndl =
	    (XML_StartCdataSectionHandler) 0;
	  XML_EndCdataSectionHandler ecdhndl =
	    (XML_EndCdataSectionHandler) 0;

	  if (SvTRUE(startcd_sv))
	    {
	      XMLP_UPD(startcd_sv);
	      scdhndl = startCdata;
	    }
	  else
	    {
	      SvREFCNT_dec(cbv->startcd_sv);
	      cbv->startcd_sv = (SV *) 0;
	    }

	  if (cbv->endcd_sv)
	    ecdhndl = endCdata;

	  XML_SetCdataSectionHandler(parser, scdhndl, ecdhndl);
	}

void
XML_SetEndCdataHandler(parser, endcd_sv)
	XML_Parser			parser
	SV *				endcd_sv
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
	  XML_StartCdataSectionHandler scdhndl =
	    (XML_StartCdataSectionHandler) 0;
	  XML_EndCdataSectionHandler ecdhndl =
	    (XML_EndCdataSectionHandler) 0;

	  if (SvTRUE(endcd_sv))
	    {
	      XMLP_UPD(endcd_sv);
	      ecdhndl = endCdata;
	    }
	  else
	    {
	      SvREFCNT_dec(cbv->endcd_sv);
	      cbv->endcd_sv = (SV *) 0;
	    }

	  if (cbv->startcd_sv)
	    scdhndl = startCdata;

	  XML_SetCdataSectionHandler(parser, scdhndl, ecdhndl);
	}

void
XML_UnsetAllHandlers(parser)
	XML_Parser			parser
    CODE:
	{
	  CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
	  
	  XML_SetElementHandler(parser,
				(XML_StartElementHandler) 0,
				(XML_EndElementHandler) 0);

	  if (cbv->ns) {
	    XML_SetNamespaceDeclHandler(parser,
					(XML_StartNamespaceDeclHandler) 0,
					(XML_EndNamespaceDeclHandler) 0);
	  }

	  XML_SetCharacterDataHandler(parser,
				      (XML_CharacterDataHandler) 0);
	  XML_SetProcessingInstructionHandler(parser,
					      (XML_ProcessingInstructionHandler) 0);
	  XML_SetCommentHandler(parser,
				(XML_CommentHandler) 0);
	  XML_SetCdataSectionHandler(parser,
				     (XML_StartCdataSectionHandler) 0,
				     (XML_EndCdataSectionHandler) 0);
	  XML_SetDefaultHandler(parser,
				(XML_DefaultHandler) 0);
	  XML_SetUnparsedEntityDeclHandler(parser,
					    (XML_UnparsedEntityDeclHandler) 0);
	  XML_SetNotationDeclHandler(parser,
				     (XML_NotationDeclHandler) 0);
	  XML_SetExternalEntityRefHandler(parser,
					  (XML_ExternalEntityRefHandler) 0);
	  XML_SetUnknownEncodingHandler(parser,
					(XML_UnknownEncodingHandler) 0,
					(void *) 0);
	}

int
XML_ElementIndex(parser)
        XML_Parser                      parser
    CODE:
        {
          CallbackVector * cbv = (CallbackVector *) XML_GetUserData(parser);
          RETVAL = cbv->st_serial_stack[cbv->st_serial_stackptr];
        }
    OUTPUT:
        RETVAL
