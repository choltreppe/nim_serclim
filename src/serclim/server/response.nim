import std/[httpcore, options, sequtils, strutils]

type
  ResponseKind* = enum respHtml, respOther
  RespHeaders* = seq[(string, string)]
  Response* = object
    case kind*: ResponseKind
      of respHtml: html*: tuple[head, body : string]
      of respOther: text*: string  # won't include client code
    code*: HttpCode
    headers*: RespHeaders


func add*(headers, addHeaders: RespHeaders): RespHeaders =
  result = headers
  for header in addHeaders:
    result.keepItIf(cmpIgnoreCase(header[0], it[0]) != 0)
  result = result & addHeaders


func resp*(code: HttpCode, head,body: string): Response =
  Response(
    kind: respHtml,
    html: (head, body),
    code: code
  )

func resp*(code: HttpCode, body: string): Response =
  Response(
    kind: respHtml,
    html: ("", body),
    code: code
  )

func respOk*(head,body: string): Response =
  Response(
    kind: respHtml,
    html: (head, body),
    code: Http200
  )

func respOk*(body: string): Response =
  Response(
    kind: respHtml,
    html: ("", body),
    code: Http200
  )

func respText*(code: HttpCode, text: string): Response =
  Response(
    kind: respOther,
    text: text,
    code: code
  )

func respTextOk*(text: string): Response =
  Response(
    kind: respOther,
    text: text,
    code: Http200
  )