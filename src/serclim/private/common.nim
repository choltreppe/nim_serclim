import std/macros
import std/strutils


proc ajaxSerializeCall*(data: NimNode): NimNode =
  newCall(ident("toJson"), data)

proc ajaxDeserializeCall*(data: NimNode, typedecl: NimNode): NimNode =
  newCall(ident("fromJson"), data, typedecl)


proc typeOfLit*(literal: NimNode): NimNode =
  let litTypeStr = ($literal.kind)[3 ..< ^3].toLower
  ident(
    if litTypeStr.endsWith("str"): "string"
    else: litTypeStr
  )