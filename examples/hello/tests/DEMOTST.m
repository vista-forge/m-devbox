DEMOTST ; examples/hello — unit tests for DEMO (STDASSERT).
        ; doc: @tag v0.1.0
        ; Proves the devbox stack is REAL, layer by layer: every assertion
        ; below runs a DEMO entry point that calls the library it advertises —
        ; MSL (STD*) alone, then FSL (FSL*) on top of a resident FileMan 22.2.
        ; A green run is the falsifiable form of "the environment works".
        new pass,fail
        do start^STDASSERT(.pass,.fail)
        do tHelloIsResident(.pass,.fail)
        do tGreetUsesMsl(.pass,.fail)
        do tAsJsonUsesMsl(.pass,.fail)
        do tFmDateUsesFsl(.pass,.fail)
        do tFieldTypeUsesFsl(.pass,.fail)
        do tCrudUsesFsl(.pass,.fail)
        do tFindUsesFsl(.pass,.fail)
        do tFailureIsAnEnvelope(.pass,.fail)
        do cleanup
        do report^STDASSERT(pass,fail)
        quit
        ;
cleanup ; Leave the engine as we found it — drop the demo fixture files.
        ; The suite runs during the image bake, so anything left behind is
        ; shipped; the fixture is rebuilt on demand by $$setup^DEMO().
        if $$noFsl quit
        do remove^FSLFIX
        quit
        ;
noFsl() ; True where the FSL/FileMan layer is NOT available (RSM).
        ; FileMan is resident on the image's YottaDB only; RSM is the
        ; reference third engine (m-rsm operator ruling, 2026-08-07) and the
        ; FSL cases below SKIP there — visibly, one passing assertion each
        ; naming the reason — so "what is not available on RSM" is something
        ; this suite TEACHES rather than a wall of faults.
        quit $$engine^STDHARN()="rsm"
        ;
skipFsl(pass,fail)      ; Record the visible FSL skip (integrity: every case asserts).
        do true^STDASSERT(.pass,.fail,1,"SKIPPED on rsm: FSL/FileMan is not available on this engine")
        quit
        ;
tHelloIsResident(pass,fail)     ;@TEST "the hello-world app is present and linkable"
        ; $TEXT is the residency probe — and referencing HELLO here is what
        ; makes the image bake compile HELLO.o, so the routine links with no
        ; write to a read-only rootfs (verify G16). Do not drop this.
        do true^STDASSERT(.pass,.fail,$text(+1^HELLO)'="","HELLO is on the routine path")
        quit
        ;
tGreetUsesMsl(pass,fail)        ;@TEST "greet() formats via MSL $$f^STDFMT + $$toUpperASCII^STDSTR"
        do eq^STDASSERT(.pass,.fail,$$greet^DEMO("world"),"Hello, WORLD!","greeting is formatted and upper-cased")
        do eq^STDASSERT(.pass,.fail,$$greet^DEMO(""),"Hello, !","empty name is handled")
        quit
        ;
tAsJsonUsesMsl(pass,fail)       ;@TEST "asJson() builds an STDJSON tree and serialises it"
        do eq^STDASSERT(.pass,.fail,$$asJson^DEMO("HAMMER",10),"{""name"":""HAMMER"",""qty"":10}","object tree encodes to JSON")
        quit
        ;
tFmDateUsesFsl(pass,fail)       ;@TEST "fmDate() converts ISO -> FileMan internal via FSL $$toFm^FSLDATE"
        if $$noFsl do skipFsl(.pass,.fail) quit
        do eq^STDASSERT(.pass,.fail,$$fmDate^DEMO("2026-01-15"),3260115,"date-only maps to FM internal")
        do eq^STDASSERT(.pass,.fail,$$fmDate^DEMO("2026-01-15T14:30:45"),"3260115.143045","datetime maps to FM internal")
        do eq^STDASSERT(.pass,.fail,$$fmDate^DEMO("not-a-date"),"","invalid input returns empty, never a guess")
        quit
        ;
tFieldTypeUsesFsl(pass,fail)    ;@TEST "fieldType() reads the live data dictionary via FSL FSLDD"
        if $$noFsl do skipFsl(.pass,.fail) quit
        do true^STDASSERT(.pass,.fail,$$setup^DEMO(),"fixture files installed")
        do eq^STDASSERT(.pass,.fail,$$fieldType^DEMO(999300,"STATUS"),"set","STATUS is a set-of-codes")
        do eq^STDASSERT(.pass,.fail,$$fieldType^DEMO(999300,"WHEN"),"date","WHEN is a date")
        do eq^STDASSERT(.pass,.fail,$$fieldType^DEMO(999300,"CAT"),"pointer","CAT points to another file")
        quit
        ;
tCrudUsesFsl(pass,fail) ;@TEST "add/qty/setQty/drop drive FileMan through FSL FSLDB"
        if $$noFsl do skipFsl(.pass,.fail) quit
        new ien
        do true^STDASSERT(.pass,.fail,$$setup^DEMO(),"fixture reset to its seed state")
        set ien=$$addWidget^DEMO("CHISEL",3)
        do eq^STDASSERT(.pass,.fail,ien,6,"create returns the new IEN (seed holds 1..5)")
        do eq^STDASSERT(.pass,.fail,$$widgetQty^DEMO(ien),3,"read returns what was filed")
        do true^STDASSERT(.pass,.fail,$$setQty^DEMO(ien,9),"update reports success")
        do eq^STDASSERT(.pass,.fail,$$widgetQty^DEMO(ien),9,"read sees the update")
        do true^STDASSERT(.pass,.fail,$$dropWidget^DEMO(ien),"delete reports success")
        do eq^STDASSERT(.pass,.fail,$$widgetQty^DEMO(ien),"","the record is gone")
        quit
        ;
tFindUsesFsl(pass,fail) ;@TEST "findWidget() looks up through the B index via FSL FSLQ"
        if $$noFsl do skipFsl(.pass,.fail) quit
        do true^STDASSERT(.pass,.fail,$$setup^DEMO(),"fixture reset to its seed state")
        do eq^STDASSERT(.pass,.fail,$$findWidget^DEMO("HAMMER"),1,"seed widget found by name")
        do eq^STDASSERT(.pass,.fail,$$findWidget^DEMO("ZZZNOPE"),0,"no match returns 0, not an error")
        quit
        ;
tFailureIsAnEnvelope(pass,fail) ;@TEST "a bad write returns an FSLERR failure envelope, never a raw FM error"
        if $$noFsl do skipFsl(.pass,.fail) quit
        new out
        do true^STDASSERT(.pass,.fail,$$setup^DEMO(),"fixture reset to its seed state")
        set out=$$badWrite^DEMO()
        do contains^STDASSERT(.pass,.fail,out,"""ok"":false","failure is reported as ok:false")
        do contains^STDASSERT(.pass,.fail,out,"FSL-NOFIELD","the FSL error code names the problem")
        do contains^STDASSERT(.pass,.fail,out,"""field"":""BOGUS""","the offending field is named")
        quit
