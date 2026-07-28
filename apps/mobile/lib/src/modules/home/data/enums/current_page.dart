import "package:stera/src/core/constants/app_assets.dart";

enum CurrentPage { home, addUpload, upload }

extension CurrentPageLabel on CurrentPage {
  String get label {
    switch (this) {
      case CurrentPage.home:
        return "Home";
      case CurrentPage.addUpload:
      case CurrentPage.upload:
        return "Library";
    }
  }
}

extension CurrentPageIconPath on CurrentPage {
  String get iconPath {
    switch (this) {
      case CurrentPage.home:
        return AppAssets.navHomeIcon;
      case CurrentPage.addUpload:
        return AppAssets.navPlusIcon;
      case CurrentPage.upload:
        return AppAssets.announcement;
    }
  }
}
