version       = "0.1.0"
author        = "choltreppe"
description   = "A client-server webframework"
license       = "Apache-2.0"
srcDir        = "src"


requires "nim >= 1.6.4"
requires "prologue >= 0.5.4"
requires "flatty >= 0.2.4"

task testapp, "run test app":
  exec "nim c -o:tests/_build/app tests/app.nim"
  exec "nim js -o:tests/_build/static/client.js tests/app.nim"
  exec "cd tests/_build/ && ./app"