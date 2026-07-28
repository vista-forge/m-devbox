DEMO    ; examples/hello — the demo app: a guided tour of the devbox stack.
        ; doc: @tag v0.1.0
        ;
        ; Run it (▷ Run Code, or `do ^DEMO` at the direct-mode prompt) and it
        ; walks the whole stack the image ships, bottom to top, printing what
        ; it calls as it calls it:
        ;
        ;   engine   YottaDB               — the M engine everything runs on
        ;   MSL      m-stdlib, STD*        — engine-neutral: strings, JSON,
        ;                                    dates, formatting. No VistA, no
        ;                                    FileMan; runs on a bare engine.
        ;   FileMan  VA FileMan 22.2       — resident, standalone (no Kernel)
        ;   FSL      f-stdlib, FSL*        — FileMan through a typed JSON API:
        ;                                    DD introspection, CRUD, queries,
        ;                                    one error envelope. FSL calls MSL
        ;                                    (the f -> m waterline); MSL never
        ;                                    calls FSL.
        ;
        ; HOW TO USE THESE LIBRARIES IN YOUR OWN CODE
        ; -------------------------------------------
        ; 1. There is no import. Both libraries are compiled onto the engine's
        ;    routine path ($ydb_routines), so `$$label^ROUTINE(args)` is the
        ;    entire calling convention. `m lib list` shows what is installed.
        ; 2. Pick the layer by the question "does this need FileMan?" — no:
        ;    STD*; yes: FSL*. That is the same waterline the org enforces
        ;    between its m-* and v-* repos.
        ; 3. Every FSL verb returns an ENVELOPE — {"ok":true,"data":{...}} or
        ;    {"ok":false,"errors":[...]} — never a raw FileMan error array.
        ;    Parse it with MSL's $$parse^STDJSON, as unpack() below does.
        ; 4. FileMan on a standalone engine has no Kernel to seed DUZ/DT/U:
        ;    call $$init^FSLENV() once (setup() does) before any FileMan work.
        ; 5. Look things up with `m doc STDSTR` / `m doc FSLDB` (every module,
        ;    every signature), or read tests/DEMOTST.m — it asserts on exactly
        ;    the entry points below, so it doubles as worked examples.
        ;
        ; Every step of the tour is a public extrinsic you can call yourself:
        ;   $$greet^DEMO(name)            MSL  format + upper-case
        ;   $$asJson^DEMO(name,qty)       MSL  build a tree, serialise it
        ;   $$fmDate^DEMO(iso)            FSL  ISO 8601 -> FileMan internal
        ;   $$setup^DEMO()                FSL  seed the env + demo files
        ;   $$fieldType^DEMO(file,field)  FSL  read the data dictionary
        ;   $$addWidget^DEMO(name,qty)    FSL  create a record
        ;   $$widgetQty^DEMO(ien)         FSL  read a record
        ;   $$setQty^DEMO(ien,qty)        FSL  update a record
        ;   $$dropWidget^DEMO(ien)        FSL  delete a record
        ;   $$findWidget^DEMO(name)       FSL  look up by name (B index)
        ;   $$badWrite^DEMO()             FSL  what a failure looks like
        do tour
        quit
        ;
        ; ---------- the tour ----------
        ;
tour    ; Print the guided tour. Called by the top label; safe to re-run.
        ; Each demonstration prints as three lines — call / returns / means —
        ; so a reader can see what ran, what came back, and why it matters.
        ; Seed the environment + demo files FIRST: FileMan's own sign-on path
        ; writes a stray blank line, and doing it here keeps that off the tour.
        new ien,ready
        set ready=$$setup()
        do rule
        write "  m-devbox — a guided tour of the stack you are standing on",!
        do rule
        write !
        write "You just ran an M (MUMPS) routine on a live YottaDB engine. This",!
        write "container also ships two code libraries and a real VA FileMan",!
        write "database, already installed and running. The tour below calls each",!
        write "layer in turn and explains what came back.",!!
        write "Every call it makes is in src/DEMO.m — open that file and read",!
        write "along. Each demonstration prints three lines:",!
        write "   call     what was run",!
        write "   returns  what came back",!
        write "   means    what it tells you",!!
        ;
        do head("STEP 1 of 6","MSL, the engine-neutral library (routines named STD*)")
        write "MSL is m-stdlib: strings, JSON, dates, formatting, logging, crypto,",!
        write "HTTP. It needs no database and no VistA, so it runs on a bare M",!
        write "engine. There is nothing to install and nothing to import — the",!
        write "routines are already on the engine's routine path, so you call them",!
        write "by name: $$label^ROUTINE(args). That is the whole ceremony.",!!
        do show("$$greet^DEMO(""world"")",$$greet("world"))
        write "  means    Two MSL calls did that: $$f^STDFMT for Python-style",!
        write "           ""{}"" formatting, $$toUpperASCII^STDSTR for the case.",!!
        do show("$$asJson^DEMO(""HAMMER"",10)",$$asJson("HAMMER",10))
        write "  means    JSON is a TREE in M — one node per value. This one was",!
        write "           built as t=""o"" (an object), t(""name"")=""s:HAMMER"" (a",!
        write "           string), t(""qty"")=""n:10"" (a number), then handed to",!
        write "           $$encode^STDJSON. $$parse^STDJSON reads it back.",!!
        ;
        do head("STEP 2 of 6","FSL sits on MSL: one library calling the other")
        write "FSL is f-stdlib: VA FileMan wrapped in a typed JSON API. FileMan",!
        write "keeps dates in its own internal format, so FSL converts them — and",!
        write "does the ISO parsing with MSL underneath. FSL may call MSL; MSL",!
        write "never calls FSL. That one-way rule is the ""waterline"", and it is",!
        write "how you choose a library: does this need FileMan? No -> STD*.",!
        write "Yes -> FSL*.",!!
        do show("$$fmDate^DEMO(""2026-01-15"")",$$fmDate("2026-01-15"))
        write "  means    FileMan's internal date form: 326 = the year 2026",!
        write "           (years since 1700), 01 = January, 15 = the day. Give",!
        write "           FSL ISO 8601, get FileMan's form; $$fromFm^FSLDATE",!
        write "           goes the other way. Junk in returns """" — never a guess.",!!
        ;
        do head("STEP 3 of 6","FileMan is resident, and needs one line of setup")
        write "VA FileMan 22.2 is installed in this image. On a real VistA system",!
        write "Kernel signs a user on and sets DUZ (who you are), DT (today) and U",!
        write "(""^""); there is no Kernel here, so $$init^FSLENV() seeds those",!
        write "once. It refuses, and changes nothing, if something already owns",!
        write "them — so it is safe to call.",!!
        if 'ready do  quit
        . write "The demo files would NOT install, so the engine is not in the",!
        . write "state this tour expects, and the rest of it is skipped. Start",!
        . write "here: m test --engine ydb /opt/examples/hello/tests",!
        write "Two demo files have already been installed for you:",!
        write "   #999300 ZFSL WIDGET    NAME, CODE, QTY, STATUS, WHEN, CAT, ...",!
        write "   #999301 ZFSL CATEGORY  NAME",!
        write "seeded with five widgets: HAMMER, WRENCH, GADGET, ANVIL, PLIERS.",!
        write "They are ordinary FileMan files, built through FileMan's own API —",!
        write "the same as any file a VistA package owns.",!!
        ;
        do head("STEP 4 of 6","The data dictionary is data: read it with FSLDD")
        write "FileMan stores the DESCRIPTION of every file in the database too:",!
        write "field names, types, indexes, pointers. That is the data dictionary",!
        write "(the ""DD""). FSLDD hands it to you as JSON, so a program can",!
        write "discover a file's shape instead of hard-coding it.",!!
        do show("$$fieldType^DEMO(999300,""STATUS"")",$$fieldType(999300,"STATUS"))
        write "  means    STATUS holds a set of codes (A = ACTIVE, I = INACTIVE).",!
        write "           WHEN is a ",$$fieldType(999300,"WHEN"),"; CAT is a ",$$fieldType(999300,"CAT")
        write " — it points at",!
        write "           file #999301, FileMan's version of a foreign key.",!
        write "  more     write $$json^FSLDD(999300) prints the whole file: every",!
        write "           field, type, index and key, as one JSON document.",!!
        ;
        do head("STEP 5 of 6","Create, read, update, delete with FSLDB")
        write "FSLDB is FileMan filing with a typed JSON front door. You pass",!
        write "values keyed by FIELD NAME; it returns an envelope (more on that in",!
        write "step 6). Dates are ISO both ways. Watch one record's whole life:",!!
        set ien=$$addWidget("CHISEL",3)
        do show("$$addWidget^DEMO(""CHISEL"",3)",ien)
        write "  means    A new record was filed and 6 is its IEN — the internal",!
        write "           entry number, FileMan's row id (the seed holds 1..5, so",!
        write "           the new one is 6). FSL sent {""NAME"":""CHISEL"",""QTY"":3}",!
        write "           to FileMan's own record filer.",!!
        do show("$$widgetQty^DEMO("_ien_")",$$widgetQty(ien))
        write "  means    Read it back. FSLDB asked FileMan for field 2 (QTY) —",!
        write "           the field NUMBER, which FSLDD resolved from the name.",!!
        write "  call     $$setQty^DEMO(",ien,",9)",!
        write "  returns  ",$$setQty(ien,9),"   (1 = filed)",!
        write "  means    An edit through FileMan's field filer. Reading QTY back",!
        write "           now gives ",$$widgetQty(ien),".",!!
        do show("$$findWidget^DEMO(""CHISEL"")",$$findWidget("CHISEL"))
        write "  means    A lookup by name, through FileMan's ""B"" index — the",!
        write "           cross-reference FileMan maintains on the .01 field.",!
        write "           FSLQ also does paged listing and filtering.",!!
        write "  call     $$dropWidget^DEMO(",ien,")",!
        write "  returns  ",$$dropWidget(ien),"   (1 = deleted)",!
        write "  means    A reference-checked delete: FSLDB refuses if another",!
        write "           record still points at this one, instead of leaving a",!
        write "           dangling pointer behind.",!!
        ;
        do head("STEP 6 of 6","When something goes wrong, you get an envelope")
        write "Every FSL verb answers with the same shape — an ""envelope"":",!
        write "   {""ok"":true, ""data"":{...}}      it worked; read data",!
        write "   {""ok"":false,""errors"":[...]}    it did not; read errors",!
        write "Your code checks ""ok"" first and never has to touch FileMan's own",!
        write "error arrays. Here is a deliberate mistake — writing to a field",!
        write "that does not exist on the file:",!!
        do show("$$badWrite^DEMO()",$$badWrite())
        write "  means    ok:false, so nothing was filed. The error names its own",!
        write "           code (FSL-NOFIELD), the offending field (BOGUS) and a",!
        write "           readable message. Unpack it with MSL's $$parse^STDJSON,",!
        write "           the way $$ok^DEMO and $$unpack^DEMO do.",!!
        ;
        do rule
        write "  WHAT NOW",!
        do rule
        write !
        write "Read the code you just watched run:",!
        write "   /opt/examples/hello/src/DEMO.m     every call above, commented",!
        write "   /opt/examples/hello/src/HELLO.m    the three-line hello world",!
        write "   /opt/examples/hello/README.md      which library to reach for",!!
        write "Run the tests — they assert on exactly these calls, so they are",!
        write "worked examples that cannot go stale:",!
        write "   cd /opt/examples/hello && m test",!!
        write "Look anything up (every module, every signature):",!
        write "   m doc STDJSON      m doc STDSTR      m doc STDDATE",!
        write "   m doc FSLDB        m doc FSLDD       m doc FSLQ",!
        write "   m lib list                          what is installed",!!
        write "The two demo files are still there — try them from a shell:",!
        write "   m engine exec --engine ydb --transport local \",!
        write "     'set x=$$setup^DEMO() write $$read^FSLDB(999300,1,"""","""")'",!
        write "     -> widget 1 (HAMMER) as JSON, including its word-processing",!
        write "        NOTES and its ITEMS sub-records",!
        write "   ... write $$list^FSLQ(999300,""ST"","""",10,"""",""QTY"",""STATUS = A"")",!
        write "     -> the active widgets, walked through the STATUS index",!!
        write "Start your own project by copying this folder; put your routines",!
        write "beside these and name test suites *TST.m. When you are done with",!
        write "the demo files, remove them with:  do remove^FSLFIX",!
        quit
        ;
rule    ; A horizontal rule, so the sections are findable in a long scroll.
        write "──────────────────────────────────────────────────────────────────",!
        quit
        ;
head(step,title)        ; A section heading.
        write !,step," — ",title,!
        write "──────────────────────────────────────────────────────────────────",!
        quit
        ;
show(call,result)       ; One demonstration: what was run, and what came back.
        write "  call     ",call,!
        write "  returns  ",result,!
        quit
        ;
        ; ---------- MSL: the engine-neutral layer ----------
        ;
greet(name)     ; Greet `name`. MSL: $$f^STDFMT (format) + $$toUpperASCII^STDSTR.
        quit $$f^STDFMT("Hello, {}!",$$toUpperASCII^STDSTR($get(name)))
        ;
asJson(name,qty)        ; Build an STDJSON tree and serialise it. MSL: STDJSON.
        ; The storage convention is one M node per JSON value: "o" = object,
        ; "s:" = string, "n:" = number (see `m doc STDJSON`).
        new t
        set t="o"
        set t("name")="s:"_$get(name)
        set t("qty")="n:"_+$get(qty)
        quit $$encode^STDJSON(.t)
        ;
        ; ---------- FSL: FileMan, typed ----------
        ;
fmDate(iso)     ; ISO 8601 -> FileMan internal ("" if invalid). FSL: FSLDATE.
        quit $$toFm^FSLDATE($get(iso))
        ;
setup() ; Seed the standalone env + the demo files; 1 = ready. FSL: FSLENV/FSLFIX.
        ; init^FSLENV seeds DUZ/DUZ(0)/U/DT in the CALLER's scope and refuses
        ; if something already owns them — so it is never NEWed here.
        if '$$seeded^FSLENV(),'$$init^FSLENV() quit 0
        quit $$install^FSLFIX()
        ;
fieldType(file,field)   ; The FSL type of one DD field. FSL: FSLDD.
        ; FSLDD hands back an STDJSON tree, so t("type") is "s:<type>";
        ; strip the type tag to get the bare value.
        new t,num
        set num=$$fldnum^FSLDD($get(file),$get(field))
        if num="" quit ""
        do field^FSLDD(file,num,.t)
        quit $piece($get(t("type")),":",2,999)
        ;
widgetJson(name,qty)    ; Typed JSON for one widget — the shape FSLDB files.
        ; FSL takes FileMan INTERNAL values keyed by FIELD NAME (or number);
        ; MSL builds the tree. Omitted keys are simply left out.
        new t
        set t="o"
        if $get(name)'="" set t("NAME")="s:"_name
        if $get(qty)'="" set t("QTY")="n:"_+qty
        quit $$encode^STDJSON(.t)
        ;
addWidget(name,qty)     ; File a new widget; return its IEN (0 on failure). FSL: FSLDB.
        new out
        set out=$$create^FSLDB(999300,$$widgetJson($get(name),$get(qty)))
        quit +$$unpack(out,"ien")
        ;
widgetQty(ien)  ; Read one widget's QTY ("" if there is no such record). FSL: FSLDB.
        ; The field SPEC is FileMan's own (field numbers, ";"-separated) —
        ; resolve the name with FSLDD rather than hard-coding "2". Read data
        ; comes back keyed by field NAME. Pass "" for the spec to get it all.
        new out
        set out=$$read^FSLDB(999300,$get(ien),$$fldnum^FSLDD(999300,"QTY"),"")
        quit $$unpack(out,"QTY")
        ;
setQty(ien,qty) ; Update one widget's QTY; 1 = filed. FSL: FSLDB.
        new out
        set out=$$update^FSLDB(999300,$get(ien),$$widgetJson("",$get(qty)))
        quit $$ok(out)
        ;
dropWidget(ien) ; Delete one widget; 1 = deleted. FSL: FSLDB (reference-checked).
        new out
        set out=$$delete^FSLDB(999300,$get(ien),"")
        quit $$ok(out)
        ;
findWidget(name)        ; Look up a widget by name; IEN, or 0 if not found. FSL: FSLQ.
        new out,tree
        set out=$$find^FSLQ(999300,$get(name),"","")
        if '$$parse^STDJSON(out,.tree) quit 0
        quit +$piece($get(tree("data","items",1,"ien")),":",2,999)
        ;
badWrite()      ; Demonstrate the failure envelope: write to a field that isn't there.
        quit $$create^FSLDB(999300,"{""NAME"":""OOPS"",""BOGUS"":1}")
        ;
        ; ---------- envelope helpers (the pattern every caller uses) ----------
        ;
ok(envelope)    ; 1 iff the envelope reports success.
        new tree
        if '$$parse^STDJSON($get(envelope),.tree) quit 0
        quit $get(tree("ok"))="t"
        ;
unpack(envelope,key)    ; One scalar out of an ok envelope's data ("" if absent/failed).
        ; STDJSON leaves are tagged ("s:HAMMER", "n:10"), so drop the tag.
        new tree
        if '$$parse^STDJSON($get(envelope),.tree) quit ""
        if $get(tree("ok"))'="t" quit ""
        quit $piece($get(tree("data",$get(key))),":",2,999)
