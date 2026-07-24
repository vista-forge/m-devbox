HELLO   ; examples/hello — the hello-world app. Run it; it writes.
        ; doc: @tag v0.1.0
        ;
        ; The smallest thing that proves the environment is alive. Its TOP
        ; label writes, so **Run Code** (▷, or Ctrl+Alt+N) — which runs
        ; `do ^HELLO` through m-run — prints something.
        ;
        ; One library call is in here on purpose: $$toUpperASCII^STDSTR is MSL
        ; (m-stdlib), already compiled onto the engine's routine path. Calling
        ; a library here needs no import, no build step, no dependency file —
        ; just the name. That is the whole ceremony.
        ;
        ; When you want the rest of the stack — FileMan through FSL, JSON,
        ; dates, the error envelope — open src/DEMO.m and run that instead.
        write "Hello, "_$$toUpperASCII^STDSTR("world")_"!",!
        write "This is m-devbox. Edit src/HELLO.m and Run Code again to see it change.",!
        write "For the guided tour of MSL + FSL + FileMan, run src/DEMO.m.",!
        quit
