import std/httpcore

type
  ResponseKind* = enum respHtml, respOther
  Response* = object
    case kind*: ResponseKind
      of respHtml: html*: tuple[head, body : string]
      of respOther: text*: string  # won't include client code
    code*: HttpCode

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