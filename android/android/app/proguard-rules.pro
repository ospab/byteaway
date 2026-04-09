# Keep gomobile bridge classes used by xraywrapper.aar
-keep class go.** { *; }
-keep class xraywrapper.** { *; }

# Keep JNI entry points from being renamed/removed.
-keepclasseswithmembernames class * {
    native <methods>;
}
