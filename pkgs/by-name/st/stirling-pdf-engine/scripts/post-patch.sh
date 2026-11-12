# shellcheck shell=bash
patch --fuzz=0 --no-backup-if-mismatch src/stirling/agents/math_presentation.py <@math_intent_patch@
patch --fuzz=0 --no-backup-if-mismatch src/stirling/agents/orchestrator.py <@privacy_report_routing_patch@
