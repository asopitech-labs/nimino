## Applied to every build of nimino.nim, including the one nimble performs for
## the `bin` entry during `nimble install`. That path passes no -d: flags, so a
## setting that only lives in a nimble task is absent from the binary a reader
## actually installs.
##
## The CLI fetches over HTTPS in two places: icon discovery, and downloading a
## released host for a platform this machine cannot build. Without ssl both
## fail at run time with a plain "unable to download", which reads like a
## network problem rather than a missing compile flag.
switch("define", "ssl")
