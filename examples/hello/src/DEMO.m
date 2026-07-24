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
        new ien
        write "== m-devbox: the stack, demonstrated ==",!!
        write "1. MSL (m-stdlib) — no FileMan, no VistA, just the engine.",!
        write "   $$greet^DEMO(""world"")            -> ",$$greet("world"),!
        write "   $$asJson^DEMO(""HAMMER"",10)       -> ",$$asJson("HAMMER",10),!!
        write "2. FSL date conversion — FSL on top of MSL (the f -> m waterline).",!
        write "   $$fmDate^DEMO(""2026-01-15"")      -> ",$$fmDate("2026-01-15"),!
        write "   (FSLDATE parses the ISO string with MSL's STDDATE, then maps",!
        write "    it to FileMan's internal form: 3260115 = 15 Jan 2026.)",!!
        write "3. FileMan is resident. Seeding the standalone environment and",!
        write "   installing the two demo files (#999300 ZFSL WIDGET, #999301",!
        write "   ZFSL CATEGORY) with five widgets to play with...",!
        if '$$setup() write "   FIXTURE INSTALL FAILED — the engine is not in the expected state.",! quit
        write "   ready.",!!
        write "4. The data dictionary is data — read it with FSLDD.",!
        write "   STATUS is a ",$$fieldType(999300,"STATUS"),", WHEN is a ",$$fieldType(999300,"WHEN")
        write ", CAT is a ",$$fieldType(999300,"CAT"),".",!
        write "   (Whole-file DD as JSON: write $$json^FSLDD(999300))",!!
        write "5. CRUD through FSLDB — real FileMan filing, typed JSON in and out.",!
        set ien=$$addWidget("CHISEL",3)
        write "   created CHISEL, IEN ",ien,", QTY ",$$widgetQty(ien),!
        write "   set QTY to 9 -> ok=",$$setQty(ien,9),", QTY now ",$$widgetQty(ien),!
        write "   found by name -> IEN ",$$findWidget("CHISEL"),"  (FSLQ, B index)",!
        write "   deleted -> ok=",$$dropWidget(ien),!!
        write "6. Failures are structured, never raw FileMan error arrays.",!
        write "   $$badWrite^DEMO() -> ",$$badWrite(),!!
        write "The fixture files are left installed — poke at them:",!
        write "   write $$read^FSLDB(999300,1,"""","""")",!
        write "   write $$list^FSLQ(999300,""ST"","""",10,"""",""QTY"",""STATUS = A"")",!
        write "Remove them with: do remove^FSLFIX",!
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
