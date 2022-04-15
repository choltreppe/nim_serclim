version       = "0.1.0"
author        = "Joel Lienhard"
description   = "A client-server webframework"
license       = "MIT"
srcDir        = "src"


requires "nim >= 1.6.4"
requires "jsony >= 1.1.3"


task test, "run tests":
  exec "nim c -r tests/testServer.nim"

task testapp, "run test app":
  exec "nim c -r -d:clientFile=app.js testapp/app.nim"