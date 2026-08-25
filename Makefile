# Convenience entrypoints. Real logic lives in the scripts these invoke.
#
#   make check      offline repo-wide syntax/lint sweep (scripts/check.sh)
#   make doctor     host-side setup sanity check (det doctor, no phone needed)
#   make module     build the Magisk module zip for the current version
#   make zygisk     ndk-build the Zygisk module (both ABIs required)
#   make companion  assemble the companion APK debug build
#   make payload    build the USB install payload
#   make kernel     merge config overlay and compile the kernel (slow)

.PHONY: check doctor module zygisk companion payload kernel

check:
	./scripts/check.sh

doctor:
	./det doctor

module:
	./magisk-module/build-module.sh

zygisk:
	cd zygisk && ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=jni/Android.mk NDK_APPLICATION_MK=jni/Application.mk

companion:
	~/android-sdk/gradle-8.7/bin/gradle --no-daemon -p companion assembleDebug

payload:
	./usb-install/build-usb-payload.sh

kernel:
	./kernel/build.sh
