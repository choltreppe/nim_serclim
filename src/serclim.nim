import jsony
import fusion/matching

export matching
export jsony.toJson, jsony.fromJson


when defined(js):
  import serclim/client
  export client

else:
  import std/[compilesettings, osproc, strformat, strutils, sequtils]
  import serclim/private/common

  let compileDefines = querySetting(commandLine).split(" ").filterIt(it.startsWith("-d:")).join(" ")
  discard execCmd(fmt"nim js -o:{querySetting(outDir) &/ clientFile} {compileDefines} {querySetting(projectFull)}")

  import serclim/server
  export server