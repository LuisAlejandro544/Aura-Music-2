# ProGuard / R8 reglas para conservar clases de Media3 ExoPlayer, Chaquopy y puentes nativos
-keep class androidx.media3.** { *; }
-keep class com.auramusic.player.** { *; }
-keep class com.chaquo.python.** { *; }
-dontwarn com.chaquo.python.**
