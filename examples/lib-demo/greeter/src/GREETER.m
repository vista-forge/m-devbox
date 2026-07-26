GREETER ; examples/lib-demo — the smallest installable library. See ../../README.md
        ; doc: @tag v0.1.0
        ;
        ; This routine exists to be INSTALLED and UNINSTALLED, so you can watch
        ; `m lib` manage a library on a live engine. It is deliberately tiny:
        ; one function, one library call.
        ;
        ; The one library call is the point: $$toUpperASCII^STDSTR is MSL
        ; (m-stdlib), already on the engine's routine path. A library you
        ; install can freely call the libraries already installed — no import,
        ; no dependency file, just the name.
        ;
        ; A library's top label does nothing on purpose (compare src/HELLO.m in
        ; examples/hello, an APP whose top label writes). You call its
        ; functions: write $$greet^GREETER("devbox")
        quit
        ;
greet(who) ; doc: greeting for WHO (default "world"), shouted via MSL.
        quit "Hello, "_$$toUpperASCII^STDSTR($get(who,"world"))_"!"
