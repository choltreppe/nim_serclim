import std/[macros, strutils]


const clientFile* {.strdefine.} = "client.js"


func `&/`*(a,b: string): string =
  if   b[0 ] == '/': b
  elif a[^1] == '/': a & b
  else             : a & "/" & b


proc typeOfLit*(literal: NimNode): NimNode =
  let litTypeStr = ($literal.kind)[3 ..< ^3].toLower
  ident(
    if litTypeStr.endsWith("str"): "string"
    else: litTypeStr
  )