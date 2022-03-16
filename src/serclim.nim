import std/macros
import std/compilesettings

import flatty
export flatty


func serializeCall(data: NimNode): NimNode =
  newCall(ident("toFlatty"), data)

template deserializeCall(data: NimNode, typedecl: NimNode): NimNode =
  newCall(ident("fromFlatty"), data, typedecl)


when querySetting(command) == "js":
  include serclim/client
else:
  include serclim/server