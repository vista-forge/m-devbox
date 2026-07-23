HELLOTST        ; examples/hello — unit tests for HELLO (STDASSERT).
        ; doc: @tag v0.1.0
        ; Proves the devbox has BOTH libraries resident: the greeting path
        ; calls MSL (STDSTR), the date path calls FSL (FSLDATE -> MSL STDDATE).
        new pass,fail
        do start^STDASSERT(.pass,.fail)
        do tGreetUsesMsl(.pass,.fail)
        do tFmDateUsesFsl(.pass,.fail)
        do report^STDASSERT(pass,fail)
        quit
        ;
tGreetUsesMsl(pass,fail)        ;@TEST "greet() upper-cases via MSL $$toUpperASCII^STDSTR"
        do eq^STDASSERT(.pass,.fail,$$greet^HELLO("world"),"HELLO, WORLD!","greeting is upper-cased")
        do eq^STDASSERT(.pass,.fail,$$greet^HELLO(""),"HELLO, !","empty name is handled")
        quit
        ;
tFmDateUsesFsl(pass,fail)       ;@TEST "fmDate() converts ISO -> FileMan internal via FSL $$toFm^FSLDATE"
        do eq^STDASSERT(.pass,.fail,$$fmDate^HELLO("2026-01-15"),3260115,"date-only maps to FM internal")
        do eq^STDASSERT(.pass,.fail,$$fmDate^HELLO("2026-01-15T14:30:45"),"3260115.143045","datetime maps to FM internal")
        do eq^STDASSERT(.pass,.fail,$$fmDate^HELLO("not-a-date"),"","invalid input returns empty, never a guess")
        quit
