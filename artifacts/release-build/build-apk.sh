#!/bin/bash
set -euxo pipefail
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
mkdir -p "$ANDROID_HOME/cmdline-tools" /opt/gradle
curl -fL --retry 3 https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -o /tmp/sdk.zip
echo 'e025545c62a8e64c7559119566a569fb1dec5f60  /tmp/sdk.zip' | sha1sum -c -
unzip -q /tmp/sdk.zip -d /tmp/sdk
mv /tmp/sdk/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
set +o pipefail
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
set -o pipefail
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'platforms;android-35' 'build-tools;35.0.0' 'cmake;3.22.1'
curl -fL --retry 3 https://services.gradle.org/distributions/gradle-8.7-bin.zip -o /tmp/gradle.zip
curl -fL --retry 3 https://services.gradle.org/distributions/gradle-8.7-bin.zip.sha256 -o /tmp/gradle.sha256
printf '%s  /tmp/gradle.zip\n' "$(cat /tmp/gradle.sha256)" | sha256sum -c -
unzip -q /tmp/gradle.zip -d /opt/gradle
cd /src/companion
/opt/gradle/gradle-8.7/bin/gradle --no-daemon --max-workers=4 assembleDebug
"$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --verbose --print-certs app/build/outputs/apk/debug/app-debug.apk
