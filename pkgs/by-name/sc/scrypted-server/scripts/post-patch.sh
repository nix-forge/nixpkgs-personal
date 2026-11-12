# shellcheck shell=bash
@nodejs_24@/bin/node @manifestProgram@ @dependencyPolicy@
cp @package_lock_json@ package-lock.json
chmod u+w package-lock.json
