# shellcheck shell=bash
substituteInPlace src/scripts/settings/userSettings.js \
  --replace-fail 'const defaultSubtitleAppearanceSettings = {' \
  'const defaultSubtitleAppearanceSettings = {
    font: "",
    textSize: "medium",
    textColor: "#ffffff",
    textWeight: "normal",
    dropShadow: "uniform",
    textBackground: "transparent",'
