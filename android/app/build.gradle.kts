plugins {
    id("com.android.application")
    id("kotlin-android")
    // O plugin do Flutter deve vir após Android e Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cbeta.noctratv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Atualizado para Java 17, que é o padrão das versões recentes do Flutter
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.cbeta.noctratv"
        
        // Fixado em 21 porque o plugin video_player exige no mínimo o Android 5.0
        minSdk = 21 
        targetSdk = flutter.targetSdkVersion
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Configuração padrão de debug para permitir build de release sem chave própria por enquanto
            signingConfig = signingConfigs.getByName("debug")
            
            // Otimizações para deixar o app mais leve
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
