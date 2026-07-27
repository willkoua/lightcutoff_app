#!/bin/bash
# Bascule les fichiers de config Firebase NATIFS entre staging et prod.
# (Le côté Dart est géré au build par APP_ENV ; mais google-services.json et
# GoogleService-Info.plist sont lus par les plugins natifs Gradle/Xcode et
# doivent correspondre au projet visé — notamment pour Google Sign-In.)
#
# Usage : tool/use_env.sh staging|prod   (puis flutter build … APP_ENV=<env>)
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  prod)
    cp android/app/google-services.prod.json android/app/google-services.json
    cp ios/Runner/GoogleService-Info.prod.plist ios/Runner/GoogleService-Info.plist
    echo "✅ Configs natives → PROD (njuka-prod). Build avec --dart-define=APP_ENV=prod" ;;
  staging)
    git checkout -- android/app/google-services.json 2>/dev/null || true
    # Repli sans git : les fichiers staging versionnés sont la référence.
    grep -q '"project_id": "lightcutoff-dev"' android/app/google-services.json || {
      echo "⚠️ google-services.json n'est pas revenu en staging — restaure-le manuellement"; exit 1; }
    git checkout -- ios/Runner/GoogleService-Info.plist 2>/dev/null || true
    echo "✅ Configs natives → STAGING (lightcutoff-dev)." ;;
  *) echo "Usage: tool/use_env.sh staging|prod"; exit 1 ;;
esac
grep -m1 '"project_id"' android/app/google-services.json
