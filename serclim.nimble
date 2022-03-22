version       = "0.0.1"
author        = "Joel Lienhard"
description   = "A client-server webframework"
license       = "Apache-2.0"
srcDir        = "src"


requires "nim >= 1.6.4"
requires "flatty >= 0.2.4"


task testapp, "run test app":
  exec "nim c -o:testapp/app testapp/app.nim"
  exec "nim js -o:testapp/client.js testapp/app.nim"
  exec "cd testapp && ./app"