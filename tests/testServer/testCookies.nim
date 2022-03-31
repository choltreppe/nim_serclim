import unittest
import std/[tables, times]
import serclim/server/cookies


let emptyHeaders: seq[(string, string)] = @[]

var cookieJar = newCookieJar({"cookieA": "bla", "cookieB": "blub"}.toTable)


test "cookies: init":

  check cookieJar["cookieA"] == "bla"
  check cookieJar["cookieB"] == "blub"


test "cookies: delete":

  cookieJar.del("cookieA")

  check not(cookieJar.contains("cookieA"))
  check cookieJar.contains("cookieB")
  check emptyHeaders.withCookies(cookieJar) == @[
    ("Set-Cookie", "cookieA=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
  ]


test "cookies: edit (basic)":

  cookieJar["cookieB"] = "foo"
  cookieJar["cookieC"] = "ba"

  check cookieJar["cookieB"] == "foo"
  check cookieJar["cookieC"] == "ba"
  check emptyHeaders.withCookies(cookieJar) == @[
    ("Set-Cookie", "cookieA=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT"),
    ("Set-Cookie", "cookieB=foo"),
    ("Set-Cookie", "cookieC=ba")
  ]


cookieJar = newCookieJar(initTable[string, string]())

test "cookies: edit with attributes":
  
  cookieJar.add("withAttrA", "test1", path = "/bla", secure = true)
  cookieJar.add("withAttrB", "test2", path = "/bla", domain = "example.org", httpOnly=true)
  cookieJar.add("withAttrC", "test3", expires = dateTime(1999, mJun, 10, 13, 37, 42, 0, utc()), domain = "example.org")

  check cookieJar["withAttrA"] == "test1"
  check cookieJar["withAttrB"] == "test2"
  check cookieJar["withAttrC"] == "test3"
  check emptyHeaders.withCookies(cookieJar) == @[
    ("Set-Cookie", "withAttrA=test1; Path=/bla; Secure"),
    ("Set-Cookie", "withAttrB=test2; Path=/bla; Domain=example.org; HttpOnly"),
    ("Set-Cookie", "withAttrC=test3; Domain=example.org; Expires=Thu, 10 Jun 1999 13:37:42 GMT")
  ]


test "cookies: parsing header":
  
  let cookieJar1 = parseCookies("cookieA =  a")
  check cookieJar1["cookieA"] == "a"

  let cookieJar2 = parseCookies("cookieA=a; cookieB = b")
  check cookieJar2["cookieA"] == "a"
  check cookieJar2["cookieB"] == "b"

  let cookieJar3 = parseCookies("cookieA=a; cookieB = b;;cookieC= c;  ")
  check cookieJar3["cookieA"] == "a"
  check cookieJar3["cookieB"] == "b"
  check cookieJar3["cookieC"] == "c"
