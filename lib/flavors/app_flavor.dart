enum AppFlavor { dev, staging, prod }

class FlavorConfig {
  static AppFlavor _flavor = AppFlavor.prod;

  static void setFlavor(AppFlavor flavor) {
    _flavor = flavor;
  }

  static AppFlavor get flavor => _flavor;

  static String get flavorName => _flavor.name;

  static bool get isDev => _flavor == AppFlavor.dev;
  static bool get isStaging => _flavor == AppFlavor.staging;
  static bool get isProd => _flavor == AppFlavor.prod;

  static String get appName {
    switch (_flavor) {
      case AppFlavor.dev:
        return '语言避难所 Dev';
      case AppFlavor.staging:
        return '语言避难所 Staging';
      case AppFlavor.prod:
        return '语言避难所';
    }
  }

  static String get bundleId {
    switch (_flavor) {
      case AppFlavor.dev:
        return 'com.shadowing.english.dev';
      case AppFlavor.staging:
        return 'com.shadowing.english.staging';
      case AppFlavor.prod:
        return 'com.shadowing.english';
    }
  }
}
