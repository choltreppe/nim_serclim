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


func resp*(code: HttpCode, head,body: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respHtml,
    html: (head, body),
    code: code,
    headers: headers
  )

func resp*(code: HttpCode, body: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respHtml,
    html: ("", body),
    code: code,
    headers: headers
  )

func respOk*(head,body: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respHtml,
    html: (head, body),
    code: Http200,
    headers: headers
  )

func respOk*(body: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respHtml,
    html: ("", body),
    code: Http200,
    headers: headers
  )

func respText*(code: HttpCode, text: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respOther,
    text: text,
    code: code,
    headers: headers
  )

func respTextOk*(text: string, headers: RespHeaders = @[]): Response =
  Response(
    kind: respOther,
    text: text,
    code: Http200,
    headers: headers
  )