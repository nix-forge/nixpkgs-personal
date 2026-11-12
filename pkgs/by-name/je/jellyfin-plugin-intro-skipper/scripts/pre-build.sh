# shellcheck shell=bash
pnpm --dir web build
test -s IntroSkipper/Configuration/introskipper.js
test -s IntroSkipper/Configuration/introskipper.css
