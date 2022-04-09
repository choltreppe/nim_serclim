import std/macros
import std/strutils


proc typeOfLit*(literal: NimNode): NimNode =
  let litTypeStr = ($literal.kind)[3 ..< ^3].toLower
  ident(
    if litTypeStr.endsWith("str"): "string"
    else: litTypeStr
  )