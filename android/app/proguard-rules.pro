# google_mlkit_text_recognition mentions the Chinese/Japanese/Korean/Devanagari recognizers,
# which Bayar does not bundle (bills are Latin script). Tell R8 they are optional.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit starts itself by creating its "registrar" classes by name at runtime. Without this,
# R8 strips their constructors and scanning silently does nothing in release builds.
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
