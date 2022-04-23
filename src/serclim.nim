import jsony
import fusion/matching

export matching
export jsony.toJson, jsony.fromJson


when defined(js):
  import serclim/client
  export client

else:
  import std/[compilesettings, os, osproc, strformat, strutils, sequtils]
  import serclim/private/common

  setCurrentDir(getAppDir())
  let compileDefines = querySetting(commandLine).split(" ").filterIt(it.startsWith("-d:")).join(" ")
  discard execCmd(fmt"nim js -o:{clientFile} {compileDefines} {querySetting(projectFull)}")

  import serclim/server
  export server