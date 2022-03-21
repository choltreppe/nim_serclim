import std/compilesettings

import flatty
import fusion/matching
export matching, flatty


when querySetting(command) == "js":
  import serclim/client
  export client
else:
  import serclim/server
  export server