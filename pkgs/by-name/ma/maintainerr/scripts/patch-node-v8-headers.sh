# shellcheck shell=bash
if ! grep -Fq '#include <climits>' deps/v8/src/base/memcopy.h; then
  substituteInPlace deps/v8/src/base/memcopy.h \
    --replace-fail '#include <stdlib.h>' $'#include <climits>\n#include <stdlib.h>'
fi
