# Floor plans are read with ML Kit's Latin text model only. The plugin also
# references the Chinese, Devanagari, Japanese and Korean models, which aren't
# bundled; without these lines R8 fails the release build on those missing
# classes. (Flutter adds this file to release builds automatically.)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
