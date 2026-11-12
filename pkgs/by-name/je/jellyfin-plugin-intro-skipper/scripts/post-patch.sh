# shellcheck shell=bash
# The tag's csproj still contains the previous assembly version; the
# upstream release workflow replaces it before compilation.
assemblyVersion=$(sed -n 's/.*<AssemblyVersion>\([^<]*\)<\/AssemblyVersion>.*/\1/p' IntroSkipper/IntroSkipper.csproj)
fileVersion=$(sed -n 's/.*<FileVersion>\([^<]*\)<\/FileVersion>.*/\1/p' IntroSkipper/IntroSkipper.csproj)
test -n "$assemblyVersion"
test "$assemblyVersion" = "$fileVersion"
substituteInPlace IntroSkipper/IntroSkipper.csproj \
  --replace-fail "<AssemblyVersion>$assemblyVersion</AssemblyVersion>" \
  '<AssemblyVersion>@version@</AssemblyVersion>' \
  --replace-fail "<FileVersion>$fileVersion</FileVersion>" \
  '<FileVersion>@version@</FileVersion>'
substituteInPlace IntroSkipper/Helper/Commit.cs \
  --replace-fail 'string.Empty' '"@source_rev@"'
