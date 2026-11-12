# shellcheck shell=bash
# next/font/google downloads Inter during the build. Keep the same font,
# supplied by nixpkgs, so builds stay offline and fonts are served locally.
mkdir -p app/fonts
cp @inter@/share/fonts/truetype/InterVariable.ttf app/fonts/InterVariable.ttf
substituteInPlace app/layout.tsx \
  --replace-fail "import { Inter } from 'next/font/google';" "import localFont from 'next/font/local';" \
  --replace-fail "const inter = Inter({ subsets: ['latin', 'latin-ext'], variable: '--font-inter', display: 'swap' });" \
  "const inter = localFont({ src: './fonts/InterVariable.ttf', variable: '--font-inter', display: 'swap' });"
