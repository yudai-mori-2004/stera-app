import "package:stera/src/modules/home/data/enums/current_page.dart";
import "package:stera/src/modules/home/ui/home_page.dart";
import "package:stera/src/modules/upload/ui/add_upload_page.dart";
import "package:stera/src/modules/upload/ui/upload_page.dart";
import "package:flutter/material.dart";

class NavigationProvider extends ChangeNotifier {
  NavigationProvider({CurrentPage initialPage = CurrentPage.home})
    : _currentPage = initialPage;

  CurrentPage _currentPage;
  CurrentPage get currentPage => _currentPage;

  // Order matches [CurrentPage] indices: home, add upload, uploaded videos
  List<Widget> get pages => const [
    HomePage(),
    AddUploadPage(),
    UploadPage(),
  ];

  int get currentIndex => CurrentPage.values.indexOf(_currentPage);

  void setCurrentPage(CurrentPage page) {
    if (_currentPage == page) return;
    _currentPage = page;
    notifyListeners();
  }

  void reset() {
    _currentPage = CurrentPage.home;
    notifyListeners();
  }
}
