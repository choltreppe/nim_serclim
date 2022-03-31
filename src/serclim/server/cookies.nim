import std/[tables, times, strformat, strutils, sequtils]


type
  CookieJar* = object
    cookies: Table[string, string]
    setCookies: seq[string]


func newCookieJar*(cookies: Table[string, string]): CookieJar =
  CookieJar(cookies: cookies)

func parseCookies*(cookiesStr: string): CookieJar =
  var cookies: Table[string, string]
  for cookie in cookiesStr.replace(" ").split(";"):
    let data = cookie.split("=")
    try: cookies[data[0]] = data[1]
    except: discard
  CookieJar(cookies: cookies)

func withCookies*(headers: seq[(string, string)], jar: CookieJar): seq[(string, string)] =
  headers & jar.setCookies.mapIt(("Set-Cookie", it))


func contains*(jar: CookieJar, name: string): bool =
  jar.cookies.contains(name)


func `[]`*(jar: CookieJar, name: string): string =
  jar.cookies[name]

proc `[]=`*(jar: var CookieJar, name, value: string) =
  jar.cookies[name] = value
  jar.setCookies.add(fmt"{name}={value}")

proc del*(jar: var CookieJar, name: string) =
  jar.cookies.del(name)
  jar.setCookies.add(fmt"{name}=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT")


proc gmtFormat(dt: DateTime): string {.inline.} =
  dt.utc().format("ddd, dd MMM yyyy HH:mm:ss") & " GMT"

func setCookieWithoutExpire(jar: var CookieJar, name, value: string, path, domain = "", secure, httpOnly = false): string =
  var setCookie = fmt"{name}={value}"
  if path != ""   : setCookie.add("; Path=" & path)  
  if domain != "" : setCookie.add("; Domain=" & domain)
  if secure       : setCookie.add("; Secure")
  if httpOnly     : setCookie.add("; HttpOnly")
  setCookie

proc add*(jar: var CookieJar, name, value: string, path, domain = "", secure, httpOnly = false) =
  let setCookie = jar.setCookieWithoutExpire(name, value, path, domain, secure, httpOnly)
  jar.cookies[name] = value
  jar.setCookies.add(setCookie)

proc add*(jar: var CookieJar, name, value: string, expires: DateTime, path, domain = "", secure, httpOnly = false) =
  var setCookie = jar.setCookieWithoutExpire(name, value, path, domain, secure, httpOnly)
  setCookie.add("; Expires=" & expires.gmtFormat)
  jar.cookies[name] = value
  jar.setCookies.add(setCookie)