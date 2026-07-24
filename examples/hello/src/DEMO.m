DEMO    ; examples/hello - a runnable demo. Unlike HELLO (a library whose top
        ; label just quits), this routine's top label DOES output, so hitting
        ; Run Code (Code Runner -> m-run -> do ^DEMO) prints something. It calls
        ; HELLO's extrinsics, resolved because m-run puts this file's directory
        ; on $ydb_routines.
        write $$greet^HELLO("m-devbox"),!
        write "ISO 2026-07-24 in FileMan form: ",$$fmDate^HELLO("2026-07-24"),!
        quit
