DEMO    ; examples/hello - a runnable demo. Unlike HELLO (a library whose top
        ; label just quits), this routine's top label writes output, so hitting
        ; Run Code (Code Runner -> m-run -> do ^DEMO) prints something. It calls
        ; HELLO's greet extrinsic, resolved because m-run puts this file's
        ; directory on $ydb_routines.
        write "Welcome to the m-devbox!",!
        write $$greet^HELLO("developer"),!
        write "Edit this routine and Run Code again to see your changes.",!
        quit
