import std/macros


proc ajaxSerializeCall*(data: NimNode): NimNode =
  newCall(ident("toFlatty"), data)

proc ajaxDeserializeCall*(data: NimNode, typedecl: NimNode): NimNode =
  newCall(ident("fromFlatty"), data, typedecl)