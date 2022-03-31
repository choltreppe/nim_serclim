version       = "0.0.1"
author        = "Joel Lienhard"
description   = "A client-server webframework"
license       = "MIT"
srcDir        = "src"


requires "nim >= 1.6.4"
requires "flatty >= 0.2.4"


task test, "run tests":
  exec "nim c -r tests/testServer.nim"

task testapp, "run test app":
  exec "nim c -o:testapp/app testapp/app.nim"
  exec "nim js -o:testapp/client.js testapp/app.nim"
  exec "cd testapp && ./app"