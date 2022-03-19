import std/macros
import std/compilesettings

import flatty
export flatty

import fusion/matching
export matching
{.experimental: "caseStmtMacros".}


proc serializeCall(data: NimNode): NimNode =
  newCall(ident("toFlatty"), data)

proc deserializeCall(data: NimNode, typedecl: NimNode): NimNode =
  newCall(ident("fromFlatty"), data, typedecl)


when querySetting(command) == "js":
  include serclim/client
else:
  include serclim/server