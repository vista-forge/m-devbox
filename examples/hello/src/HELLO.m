HELLO   ; examples/hello — a starting M project for the m-devbox environment.
        ; doc: @tag v0.1.0
        ;
        ; The devbox ships two libraries and this sample touches both, so a
        ; green `m test` proves each is resident and callable:
        ;   MSL  (m-stdlib, STD*) — $$toUpperASCII^STDSTR
        ;   FSL  (f-stdlib, FSL*) — $$toFm^FSLDATE  (which itself calls MSL
        ;                           STDDATE, so it also exercises the f->m
        ;                           waterline on a live engine)
        ;
        ; Public extrinsics:
        ;   $$greet^HELLO(name)  — an upper-cased greeting (MSL)
        ;   $$fmDate^HELLO(iso)  — ISO 8601 -> FileMan internal date (FSL)
        quit
        ;
greet(name)     ; Return an upper-cased greeting. MSL: $$toUpperASCII^STDSTR.
        quit "HELLO, "_$$toUpperASCII^STDSTR($get(name))_"!"
        ;
fmDate(iso)     ; ISO 8601 date/time -> FileMan internal form. FSL: $$toFm^FSLDATE.
        quit $$toFm^FSLDATE($get(iso))
