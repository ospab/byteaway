# Keep gomobile bridge classes used by boxwrapper.aar
-keep class go.** { *; }
-keep class boxwrapper.** { *; }
-keep class xraywrapper.** { *; }

# Keep JNI entry points from being renamed/removed.
-keepclasseswithmembernames class * {
    native <methods>;
}
